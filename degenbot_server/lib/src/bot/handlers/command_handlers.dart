// command_handlers.dart
//
// All Telegram /command handlers.
//
// EACH COMMAND:
//   /start     → Welcome message, register user
//   /status    → Show bot state, wallet, open trades
//   /wallet    → Set/change wallet address (guided flow)
//   /chain     → Switch blockchain (solana/ethereum/bnb)
//   /activate  → Turn trading bot ON
//   /deactivate→ Turn trading bot OFF
//   /positions → List open trades
//   /history   → Last 10 closed trades
//   /stats     → ROI summary
//   /risk      → View or change risk settings
//   /help      → Command reference
//
// CONVERSATION PLUGIN:
//   Multi-step commands (like /wallet which needs a follow-up address)
//   use Televerse's Conversation plugin. This lets us write:
//
//     await conv.ask(ctx, 'Enter your wallet address:');
//     final response = await conv.waitForTextMessage(ctx);
//     // response.message.text is the user's wallet address
//
//   Much cleaner than managing a state machine manually.

import 'package:logging/logging.dart';
import 'package:televerse/plugins/conversation.dart';
import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import 'package:degenbot_server/src/services/repository/user_repository.dart';
import 'package:degenbot_server/src/services/repository/trade_repository.dart';
import 'package:degenbot_server/src/services/repository/feature_flags_repository.dart';
import 'package:degenbot_server/src/services/intelligence/token_intelligence_pipeline.dart';
import 'package:degenbot_server/src/bot/utils/message_formatter.dart';

final _log = Logger('CommandHandlers');

class CommandHandlers {
  final Bot _bot;
  final TokenIntelligencePipeline _pipeline;
  final _users = const UserRepository();
  final _trades = const TradeRepository();
  final _flags = const FeatureFlagsRepository();

  CommandHandlers(this._bot, this._pipeline);

  /// Register all commands. Called once from DegenTelegramBot.start().
  void register(
  // This callback is passed to CommandHandlers so it can update the command list in Telegram's UI whenever needed (e.g. if we want to add/remove commands based on feature flags or user state).
  {
    required Future<void> Function(List<BotCommand>, int chatId)
    setCommandsCallback,
  }) {
    _bot.plugin(ConversationPlugin<Context>());

    _bot.use(createConversation('create_wallet_conversation', _onWallet));

    _bot.command(
      'start',
      (ctx) => _onStart(ctx, setCommandsCallback: setCommandsCallback),
    );
    _bot.command('analyze', _onAnalyze);
    _bot.command('status', _onStatus);
    _bot.command('wallet', (ctx) async {
      await ctx.conversation.enter("create_wallet_conversation");
    });
    _bot.command('chain', _onChain);
    _bot.command('activate', _onActivate);
    _bot.command('deactivate', _onDeactivate);
    _bot.command('positions', _onPositions);
    _bot.command('history', _onHistory);
    _bot.command('stats', _onStats);
    _bot.command('risk', _onRisk);
    _bot.command('features', _onFeatures);
    _bot.command('help', _onHelp);

    _log.info('Registered ${12} command handlers');
  }

  // ── /start ────────────────────────────────────────────────────────────────
  Future<void> _onStart(
    Context ctx, {
    required Future<void> Function(List<BotCommand>, int chatId)
    setCommandsCallback,
  }) async {
    final user = ctx.update.message?.from;
    if (user == null) return;

    final name = user.firstName;
    // call the callback funtion first
    await setCommandsCallback([
      BotCommand(
        command: 'start',
        description: 'Welcome message and setup instructions',
      ),
      BotCommand(
        command: 'status',
        description: 'Show bot status, wallet, open trades',
      ),
      BotCommand(
        command: 'wallet',
        description: 'Set or change your wallet address',
      ),
      BotCommand(
        command: 'chain',
        description: 'Switch blockchain (solana/ethereum/bnb)',
      ),
      BotCommand(command: 'activate', description: 'Turn the trading bot ON'),
      BotCommand(
        command: 'deactivate',
        description: 'Turn the trading bot OFF',
      ),
      BotCommand(command: 'positions', description: 'List your open trades'),
      BotCommand(
        command: 'history',
        description: 'Show your last 10 closed trades',
      ),
      BotCommand(
        command: 'stats',
        description: 'View your ROI and performance stats',
      ),
      BotCommand(
        command: 'risk',
        description: 'View or change your risk settings',
      ),
      BotCommand(
        command: 'features',
        description: 'Toggle intelligence data sources on/off',
      ),
      BotCommand(command: 'help', description: 'Show this command reference'),
    ], user?.id ?? 0);

    await ctx.reply(
      '👋 Welcome to DegenBot, *$name*!\n\n'
      'I\'m an AI-powered crypto trading bot that scans DexScreener, '
      'identifies high-potential coins, and trades on your behalf.\n\n'
      '*To get started:*\n'
      '1️⃣  Set your wallet address → /wallet\n'
      '2️⃣  Choose your chain → /chain\n'
      '3️⃣  Review risk settings → /risk\n'
      '4️⃣  Activate the bot → /activate\n\n'
      'Or just type naturally — I understand plain English too.\n'
      'Try: _"What coins are you watching?"_\n\n'
      'Type /help for all commands.',
      parseMode: ParseMode.markdown,
    );
  }

  // ── /analyze ──────────────────────────────────────────────────────────────
  Future<void> _onAnalyze(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    final text = ctx.update.message?.text?.trim() ?? '';
    final args = text.split(' ').where((s) => s.isNotEmpty).toList();
    if (args.length < 2) {
      await ctx.reply(
        '❌ *Please specify a contract address.*\n\n'
        'Usage:\n'
        '`/analyze <contract_address> [chain]`\n'
        'Example: `/analyze 0x1234...`',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    final contractAddress = args[1].trim();
    // Support custom chain as optional 3rd argument, otherwise use user's activeChain
    final chain = args.length >= 3
        ? args[2].trim().toLowerCase()
        : user.activeChain;

    await ctx.reply(
      '🔍 *Running 5-layer token analysis...*\nThis takes a few seconds.',
      parseMode: ParseMode.markdown,
    );

    try {
      final report = await _pipeline.analyze(
        contractAddress: contractAddress,
        chain: chain,
      );

      await ctx.reply(
        MessageFormatter.tokenAnalysisReport(report),
        parseMode: ParseMode.markdown,
      );
    } catch (e, st) {
      _log.severe('Error in /analyze command', e, st);
      await ctx.reply('❌ An error occurred during analysis: $e');
    }
  }

  // ── /status ───────────────────────────────────────────────────────────────
  Future<void> _onStatus(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    final openTrades = await _trades.getOpenTrades(user.id!);
    final riskProfile = await _trades.getRiskProfile(user.id!);
    final tradesToday = await _trades.countTradesToday(user.id!);

    await ctx.reply(
      MessageFormatter.statusMessage(
        user: user,
        openTradeCount: openTrades.length,
        tradesToday: tradesToday,
        riskProfile: riskProfile,
      ),
      parseMode: ParseMode.markdown,
    );
  }

  // ── /wallet ───────────────────────────────────────────────────────────────
  // Multi-step: ask for address, validate format, save.
  Future<void> _onWallet(
    Conversation<Context> conversation,
    Context ctx,
  ) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    // Show current wallet if set
    if (user.walletAddress != null) {
      await ctx.reply(
        '📍 Current wallet (${user.activeChain}):\n`${user.walletAddress}`\n\n'
        'Send your new wallet address to change it, or /cancel to keep the current one.',
        parseMode: ParseMode.markdown,
      );
    } else {
      await ctx.reply(
        '💳 Enter your *${user.activeChain}* wallet address:\n\n'
        '⚠️ This is your *public* address only — never share your private key.',
        parseMode: ParseMode.markdown,
      );
    }

    // Use Televerse conversation to wait for the next non-empty text message
    final response = await conversation.waitUntil(
      (event) => (event.message?.text ?? '').isNotEmpty,
      timeout: const Duration(minutes: 1),
      otherwise: (ctx) async => await ctx.reply('Timeout — wallet unchanged.'),
    );
    // final response = await conv.waitForTextMessage(ctx);
    final address = response.text?.trim() ?? '';

    if (address == '/cancel') {
      await ctx.reply('Cancelled — wallet unchanged.');
      return;
    }

    // Basic format validation per chain
    final isValid = _validateWalletAddress(address, user.activeChain);
    if (!isValid) {
      await ctx.reply(
        '❌ That doesn\'t look like a valid *${user.activeChain}* address.\n'
        'Try /wallet again.',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    // Save
    await _users.update(user.copyWith(walletAddress: address));
    await ctx.reply(
      '✅ Wallet saved!\n`$address`\n\n'
      'Ready to activate? → /activate',
      parseMode: ParseMode.markdown,
    );
  }

  // ── /chain ────────────────────────────────────────────────────────────────
  Future<void> _onChain(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    // Show inline keyboard for chain selection
    final keyboard = InlineKeyboard()
        .text('☀️ Solana', 'chain:solana')
        .text('🔷 Ethereum', 'chain:ethereum')
        .text('🟡 BNB', 'chain:bnb');

    await ctx.reply(
      '🔗 Select your blockchain:',
      replyMarkup: keyboard,
    );

    // Handle button callback
    _bot.callbackQuery(RegExp(r'^chain:'), (ctx) async {
      final chain = ctx.callbackQuery?.data?.split(':').last ?? 'solana';
      final userId = ctx.callbackQuery?.from.id;
      if (userId == null) return;

      final user = await _users.findByTelegramId(userId);
      if (user == null) return;

      await _users.update(
        user.copyWith(
          activeChain: chain,
          walletAddress: null,
          isBotActive: false,
          updatedAt: DateTime.now().toUtc(),
        ),
      );

      await ctx.answerCallbackQuery(text: 'Switched to $chain ✅');
      await ctx.editMessageText(
        '✅ Chain set to *$chain*\n\nSet your wallet address → /wallet',
        parseMode: ParseMode.markdown,
      );
    });
  }

  // ── /activate ─────────────────────────────────────────────────────────────
  Future<void> _onActivate(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    if (user.isBotActive) {
      await ctx.reply('⚡ Bot is already active. Use /deactivate to stop it.');
      return;
    }

    if (user.walletAddress == null) {
      await ctx.reply(
        '⚠️ Set a wallet address first → /wallet',
      );
      return;
    }

    await _users.setBotActive(user.id!, active: true);
    await ctx.reply(
      '🚀 *Bot activated!*\n\n'
      'I\'m now scanning DexScreener on *${user.activeChain}* '
      'and will notify you when I make a move.\n\n'
      'Use /deactivate to stop.',
      parseMode: ParseMode.markdown,
    );
  }

  // ── /deactivate ───────────────────────────────────────────────────────────
  Future<void> _onDeactivate(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    await _users.setBotActive(user.id!, active: false);
    await ctx.reply(
      '🛑 Bot deactivated.\n\n'
      'Open positions are not automatically closed — '
      'use /positions to check them manually.',
    );
  }

  // ── /positions ────────────────────────────────────────────────────────────
  Future<void> _onPositions(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    final trades = await _trades.getOpenTrades(user.id!);

    if (trades.isEmpty) {
      await ctx.reply('📭 No open positions right now.');
      return;
    }

    await ctx.reply(
      MessageFormatter.positionsList(trades),
      parseMode: ParseMode.markdown,
    );
  }

  // ── /history ──────────────────────────────────────────────────────────────
  Future<void> _onHistory(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    final trades = await _trades.getTradeHistory(user.id!, limit: 10);

    if (trades.isEmpty) {
      await ctx.reply('📭 No trade history yet.');
      return;
    }

    await ctx.reply(
      MessageFormatter.tradeHistory(trades),
      parseMode: ParseMode.markdown,
    );
  }

  // ── /stats ────────────────────────────────────────────────────────────────
  Future<void> _onStats(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    final history = await _trades.getTradeHistory(user.id!, limit: 100);
    final openTrades = await _trades.getOpenTrades(user.id!);

    await ctx.reply(
      MessageFormatter.statsMessage(history, openTrades),
      parseMode: ParseMode.markdown,
    );
  }

  // ── /risk ─────────────────────────────────────────────────────────────────
  Future<void> _onRisk(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    final profile = await _trades.getRiskProfile(user.id!);

    await ctx.reply(
      MessageFormatter.riskProfile(profile),
      parseMode: ParseMode.markdown,
    );
  }

  // ── /features ─────────────────────────────────────────────────────────────
  // Lets the user see and toggle every intelligence data source live,
  // with no server restart needed. Each button flips that one source.
  Future<void> _onFeatures(Context ctx) async {
    final allFlags = await _flags.getAllFlags();
    await ctx.reply(
      MessageFormatter.featuresOverview(allFlags),
      parseMode: ParseMode.markdown,
      replyMarkup: _buildFeaturesKeyboard(allFlags),
    );
  }

  InlineKeyboard _buildFeaturesKeyboard(Map<String, bool> flags) {
    final keyboard = InlineKeyboard();
    for (final name in FeatureFlag.all) {
      final isOn = flags[name] ?? false;
      final emoji = isOn ? '🟢' : '⚪';
      keyboard.text('$emoji $name', 'feature_toggle:$name');
      keyboard.row(); // one button per row — keeps labels readable
    }
    return keyboard;
  }

  /// Registers the callback handler for feature toggle buttons.
  /// Call this once during bot setup (see telegram_bot.dart).
  void registerFeatureToggleCallback() {
    _bot.callbackQuery(RegExp(r'^feature_toggle:'), (ctx) async {
      final flagName = ctx.callbackQuery?.data?.split(':').last;
      if (flagName == null) return;

      final newValue = await _flags.toggle(flagName);
      await ctx.answerCallbackQuery(
        text: '${newValue ? "Enabled" : "Disabled"} $flagName',
      );

      // Refresh the message with updated button states
      final allFlags = await _flags.getAllFlags();
      await ctx.editMessageText(
        MessageFormatter.featuresOverview(allFlags),
        parseMode: ParseMode.markdown,
        replyMarkup: _buildFeaturesKeyboard(allFlags),
      );
    });
  }

  // ── /help ─────────────────────────────────────────────────────────────────
  Future<void> _onHelp(Context ctx) async {
    await ctx.reply(
      '📖 *DegenBot Commands*\n\n'
      '`/status`     — Bot state, wallet, open trades\n'
      '`/wallet`     — Set wallet address\n'
      '`/chain`      — Switch blockchain\n'
      '`/activate`   — Start the bot\n'
      '`/deactivate` — Stop the bot\n'
      '`/positions`  — Open trades\n'
      '`/history`    — Last 10 trades\n'
      '`/stats`      — ROI & win rate\n'
      '`/risk`       — Risk settings\n'
      '`/features`   — Toggle data sources on/off (incl. paid APIs)\n'
      '`/help`       — This message\n\n'
      '💬 *Natural language also works:*\n'
      '_"What\'s my balance?", "Show me trending coins", '
      '"Set stop loss to 15%"_',
      parseMode: ParseMode.markdown,
    );
  }

  // ── VALIDATION HELPERS ────────────────────────────────────────────────────

  bool _validateWalletAddress(String address, String chain) {
    return switch (chain) {
      // Solana: base58, 32–44 chars
      'solana' => RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(address),
      // Ethereum/BNB: 0x + 40 hex chars
      'ethereum' || 'bnb' => RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address),
      _ => false,
    };
  }
}
