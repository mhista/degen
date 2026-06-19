// ai_handler.dart
//
// The agentic AI handler — processes all non-command Telegram messages.
//
// HOW THE AGENT LOOP WORKS (plain English):
//   1. User sends a message: "What coins are you watching?"
//   2. We send that message to the LLM (Gemini/OpenAI via dartantic_ai)
//      along with a list of TOOLS the LLM can call.
//   3. The LLM decides: "I should call the `getWatchlist` tool"
//   4. dartantic_ai calls that tool and gets the result
//   5. The LLM reads the result and writes a human reply
//   6. We send that reply back to the user
//
//   The LLM never touches the blockchain directly.
//   It calls TOOLS — our Dart functions — which do the real work.
//   The LLM is the brain; our code is the hands.
//
// DARTANTIC_AI TOOL PATTERN:
//   Each tool is a Tool object with:
//     • name: string identifier the LLM uses to call it
//     • description: plain English — the LLM reads this to decide when to use it
//     • parameters: JSON Schema defining what inputs the tool accepts
//     • execute: the Dart function that actually runs
//
// CONVERSATION MEMORY:
//   dartantic_ai Agent maintains a message history per session.
//   We key sessions by Telegram user ID so each user has their own
//   conversation context. Currently in-memory (resets on restart).
//   Step 3 will move this to Supabase for persistence.

import 'dart:convert';
import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:degenbot_server/src/config/env.dart';
import 'package:degenbot_server/src/services/repository/user_repository.dart';
import 'package:degenbot_server/src/services/repository/trade_repository.dart';
import 'package:degenbot_server/src/services/dex/dexscreener_service.dart';
import 'package:degenbot_server/degen_logger.dart';

class AiHandler {
  final Bot _bot;
  final _users = const UserRepository();
  final _trades = const TradeRepository();
  final _dex =  DexScreenerService();

  // Per-user agent instances. Each user gets their own conversation history.
  // Map key: Telegram user ID
  final Map<int, Agent> _agents = {};

  AiHandler(this._bot);

  /// Register the catch-all text handler. Must be called LAST in bot setup.
  void register() {
    // Handle all text messages that aren't commands
    _bot.onText(_handleMessage);
    // _bot.text( _handleMessage);
  }

  // ── MAIN HANDLER ──────────────────────────────────────────────────────────

  Future<void> _handleMessage(Context ctx) async {
    final telegramUser = ctx.from;
    final text = ctx.text;
    if (telegramUser == null || text == null || text.trim().isEmpty) return;

    final telegramId = telegramUser.id;
    Log.info('📩 [AI Handler] Message from Telegram ID $telegramId: "$text"');

    // Show typing indicator while AI thinks
    await ctx.api.sendChatAction(
      ChatID(telegramId),
       ChatAction.typing,
    );

    try {
      final agent = _getOrCreateAgent(telegramId);
      Log.debug('Sending query to LLM for user $telegramId...');
      
      // send system prompt message first to ensure context is set
      final result = await agent.send(text, history: [
        ChatMessage.system(_buildSystemPrompt()),
      ]);
      
      Log.success('LLM response generated for user $telegramId: "${result.output}"');
      await ctx.reply(result.output ?? "I couldn't process that. Try again.");
    } catch (e, st) {
      Log.error('Error in AI handler for user $telegramId', error: e, stackTrace: st);
      await ctx.reply(
        '⚠️ Something went wrong. Try again or use a command like /help.',
      );
    }
  }

  // ── AGENT FACTORY ─────────────────────────────────────────────────────────

  Agent _getOrCreateAgent(int telegramId) {
    return _agents.putIfAbsent(telegramId, () => _buildAgent(telegramId));
  }

  Agent _buildAgent(int telegramId) {
    Log.info('Initializing new AI agent session for user $telegramId using provider: ${Env.aiProvider}');
    // Select provider based on config
    Provider agent = switch (Env.aiProvider) {
      'openai' => OpenAIProvider(apiKey: Env.openaiApiKey),
      'google' || 'gemini' => GoogleProvider(apiKey: Env.geminiApiKey),
      _ => AnthropicProvider(apiKey: Env.anthropicApiKey),
    };

    return Agent.forProvider(agent,
        tools: _buildTools(telegramId),
    );
  }


    // return Agent(
    //   model: model,
    //   systemPrompt: _buildSystemPrompt(),
    //   tools: _buildTools(telegramId),
    //   // dartantic_ai maintains message history automatically
    // );

  // ── SYSTEM PROMPT ─────────────────────────────────────────────────────────

  String _buildSystemPrompt() => '''
You are DegenBot, an AI-powered cryptocurrency trading assistant.
You help users manage their crypto trading bot via Telegram.

You are concise, friendly, and use emojis sparingly.
Always use the available tools to get real data before answering.
Never make up prices, balances, or trade results.

When a user asks about coins, use the scanTrending tool.
When a user asks about their trades or positions, use getUserStatus.
When a user wants to change risk settings, use updateRiskSetting.
When you're unsure what the user wants, ask a short clarifying question.

Format responses for Telegram (use *bold* for emphasis, not markdown headers).
Keep responses under 300 words unless the user asks for detail.
''';

  // ── TOOL DEFINITIONS ──────────────────────────────────────────────────────
  // Each tool maps to a real service call.
  // The LLM reads `description` to decide when to use each tool.

  List<Tool> _buildTools(int telegramId) => [

    // ── getUserStatus ────────────────────────────────────────────────────
    Tool(
      name: 'getUserStatus',
      description:
          'Get the current status of the user: active chain, wallet address, '
          'bot active state, open positions count, trades today, risk settings.',
     // no inputs needed — telegramId is captured in closure
      onCall: (_) async {
        Log.info('🛠️ [AI Tool] Executing getUserStatus for user $telegramId');
        final user = await _users.findByTelegramId(telegramId);
        if (user == null) {
          Log.warning('   getUserStatus: User not found for Telegram ID $telegramId');
          return 'User not found';
        }

        final openTrades = await _trades.getOpenTrades(user.id!);
        final risk = await _trades.getRiskProfile(user.id!);
        final today = await _trades.countTradesToday(user.id!);

        final status = {
          'chain': user.activeChain,
          'wallet': user.walletAddress ?? 'not set',
          'bot_active': user.isBotActive,
          'open_positions': openTrades.length,
          'trades_today': today,
          'daily_limit': risk.dailyTradeLimit,
          'max_trade_percent': risk.maxTradePercent,
          'take_profit_percent': risk.defaultTakeProfitPercent,
          'stop_loss_percent': risk.defaultStopLossPercent,
        };
        Log.success('   getUserStatus: Success. Data: $status');
        return jsonEncode(status);
      }, 
    ),

    // ── getTradeHistory ──────────────────────────────────────────────────
    Tool(
      name: 'getTradeHistory',
      description:
          'Get the user\'s recent trade history with PnL and ROI. '
          'Use when the user asks about past trades, performance, or profit.',
      inputSchema: Schema.fromMap( {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': 'Number of trades to fetch (default 5, max 20)',
            'default': 5,
          },
        },
        // 'required': ['limit'],
        
      }),
      onCall: (args) async {
        Log.info('🛠️ [AI Tool] Executing getTradeHistory for user $telegramId with args: $args');
        final limit = ((args as Map<String, dynamic>)['limit'] as int?) ?? 5;
        final user = await _users.findByTelegramId(telegramId);
        if (user == null) {
          Log.warning('   getTradeHistory: User not found for Telegram ID $telegramId');
          return 'User not found';
        }

        final trades = await _trades.getTradeHistory(user.id!, limit: limit);
        if (trades.isEmpty) {
          Log.info('   getTradeHistory: No trade history found for user ${user.id}');
          return 'No trade history yet.';
        }

        final result = trades.map((t) => {
          'symbol': t.symbol,
          'pnl_usd': t.realizedPnlUsd,
          'roi_percent': t.roiPercent,
          'close_reason': t.closeReason,
          'sold_at': t.soldAt?.toIso8601String(),
        }).toList();
        
        Log.success('   getTradeHistory: Found ${result.length} trade record(s)');
        return jsonEncode(result);
      },
    ),

    // ── scanTrending ──────────────────────────────────────────────────────
    Tool(
      name: 'scanTrending',
      description:
          'Scan DexScreener for trending/boosted coins on a specific chain. '
          'Use when the user asks "what coins are you watching?", '
          '"any good coins?", "show me trending tokens", etc.',
      inputSchema: Schema.fromMap({
        'type': 'object',
        'properties': {
        'chain': {
          'type': 'string',
          'description': 'Blockchain to scan: solana, ethereum, or bnb',
          'enum': ['solana', 'ethereum', 'bnb'],
        },
        },
        'required': ['chain'],
      }),
      onCall: (args) async {
        Log.info('🛠️ [AI Tool] Executing scanTrending for user $telegramId with args: $args');
        final user = await _users.findByTelegramId(telegramId);
        final chain = ((args as Map<String, dynamic>)['chain'] as String?) ?? user?.activeChain ?? 'solana';

        try {
          final coins = await _dex.getTrendingCoins(chain: chain, limit: 5);
          if (coins.isEmpty) {
            Log.info('   scanTrending: No trending coins returned from DexScreener');
            return 'No trending coins found right now.';
          }

          final result = coins.map((c) => {
            'name': c['name'],
            'symbol': c['symbol'],
            'price_usd': c['priceUsd'],
            'change_24h': c['priceChange']?['h24'],
            'volume_24h': c['volume']?['h24'],
            'liquidity_usd': c['liquidity']?['usd'],
          }).toList();
          
          Log.success('   scanTrending: Successfully found ${result.length} trending coins');
          return jsonEncode(result);
        } catch (e) {
          Log.error('   scanTrending: Failed to scan trending coins', error: e);
          return 'DexScreener scan failed: $e';
        }
      },
    ),

    // ── updateRiskSetting ─────────────────────────────────────────────────
    Tool(
      name: 'updateRiskSetting',
      description:
          'Update one of the user\'s risk management settings. '
          'Use when the user says things like "set stop loss to 15%", '
          '"change take profit to 80%", "limit to 5 trades per day", '
          '"only risk 3% per trade".',
      inputSchema: Schema.fromMap({
        'type': 'object',
        'properties': {
          'field': {
            'type': 'string',
            'description': 'Which setting to change',
            'enum': [
              'max_trade_percent',
            'daily_trade_limit',
            'take_profit_percent',
            'stop_loss_percent',
          ],
        },
        'value': {
          'type': 'number',
          'description': 'The new value (percentage as a number, e.g. 15 for 15%)',
        },
      },}),
      onCall: (args) async {
        Log.info('🛠️ [AI Tool] Executing updateRiskSetting for user $telegramId with args: $args');
        final field = ((args as Map<String, dynamic>)['field'] as String?) ?? '';
        final value = ((args as Map<String, dynamic>)['value'] as num).toDouble();
        final user = await _users.findByTelegramId(telegramId);
        if (user == null) {
          Log.warning('   updateRiskSetting: User not found for Telegram ID $telegramId');
          return 'User not found';
        }

        final profile = await _trades.getRiskProfile(user.id!);

        final updated = switch (field) {
          'max_trade_percent' => profile.copyWith(
              maxTradePercent: value.clamp(1, 100)),
          'daily_trade_limit' => profile.copyWith(
              dailyTradeLimit: value.toInt().clamp(1, 100)),
          'take_profit_percent' => profile.copyWith(
              defaultTakeProfitPercent: value.clamp(1, 1000)),
          'stop_loss_percent' => profile.copyWith(
              defaultStopLossPercent: value.clamp(1, 99)),
          _ => throw ArgumentError('Unknown field: $field'),
        };

        await _trades.updateRiskProfile(updated);
        Log.success('   updateRiskSetting: Successfully updated risk setting $field to $value');
        return jsonEncode({'success': true, 'field': field, 'new_value': value});
      },
    ),
  ];
}
