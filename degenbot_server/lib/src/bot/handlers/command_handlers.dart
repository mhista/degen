// command_handlers.dart
//
// All Telegram /command handlers.
//
// COMMANDS:
//   /start      → Welcome + setup guide with inline quick-action buttons
//   /status     → Bot state, wallet, open trades + action buttons
//   /wallet     → Set/change wallet (guided multi-step conversation)
//   /chain      → Switch blockchain via inline keyboard
//   /analyze    → Run 5-layer token analysis on a contract address
//   /activate   → Turn trading bot ON
//   /deactivate → Turn trading bot OFF
//   /positions  → Open trades with ATL tracking status
//   /history    → Last 10 closed trades
//   /stats      → ROI summary
//   /risk       → View or change risk settings
//   /macro      → View/override BTC macro context
//   /mcap       → Set MCap filter range (default $300–$3000)
//   /reanalyze  → Force re-analysis of a cached address
//   /cache      → Token cache stats (scanned, rejected, candidates)
//   /features   → Toggle intelligence data sources on/off
//   /help       → Command reference
//
// INLINE KEYBOARDS:
//   Every message that has a logical "next action" ships with inline buttons.
//   Users can navigate the whole bot by tapping — rarely need to type.
//
//   CRITICAL: All callbackQuery handlers are registered ONCE in
//   registerCallbacks() — NOT inside individual command handlers.
//   Registering inside a handler re-registers on every call = stacked listeners.
//
// CONVERSATION PLUGIN:
//   Multi-step commands (/wallet) use Televerse's ConversationPlugin.

import 'package:logging/logging.dart';
import 'package:televerse/plugins/conversation.dart';
import 'package:televerse/telegram.dart';
import 'package:televerse/televerse.dart';
import 'package:degenbot_server/src/services/repository/user_repository.dart';
import 'package:degenbot_server/src/services/repository/trade_repository.dart';
import 'package:degenbot_server/src/services/repository/feature_flags_repository.dart';
import 'package:degenbot_server/src/services/intelligence/token_intelligence_pipeline.dart';
import 'package:degenbot_server/src/services/trading/macro_context_service.dart';
import 'package:degenbot_server/src/services/trading/token_cache_service.dart';
import 'package:degenbot_server/src/services/trading/trader_rule_engine.dart';
import 'package:degenbot_server/src/services/trading/position_monitor.dart';
import 'package:degenbot_server/src/bot/utils/message_formatter.dart';
import 'package:degenbot_server/src/services/messaging/messaging_result.dart';

final _log = Logger('CommandHandlers');

class CommandHandlers {
  final Bot _bot;
  final TokenIntelligencePipeline _pipeline;
  final _users = const UserRepository();
  final _trades = const TradeRepository();
  final _flags = const FeatureFlagsRepository();

  CommandHandlers(this._bot, this._pipeline);

  // ── REGISTRATION ──────────────────────────────────────────────────────────

  void register({
    required Future<void> Function(List<BotCommand>, int chatId) setCommandsCallback,
  }) {
    _bot.plugin(ConversationPlugin<Context>());
    _bot.use(createConversation('wallet_conversation', _onWallet));

    _bot.command('start', (ctx) => _onStart(ctx, setCommandsCallback: setCommandsCallback));
    _bot.command('analyze', _onAnalyze);
    _bot.command('status', _onStatus);
    _bot.command('wallet', (ctx) => ctx.conversation.enter('wallet_conversation'));
    _bot.command('chain', _onChain);
    _bot.command('activate', _onActivate);
    _bot.command('deactivate', _onDeactivate);
    _bot.command('positions', _onPositions);
    _bot.command('history', _onHistory);
    _bot.command('stats', _onStats);
    _bot.command('risk', _onRisk);
    _bot.command('macro', _onMacro);
    _bot.command('mcap', _onMcap);
    _bot.command('reanalyze', _onReanalyze);
    _bot.command('cache', _onCache);
    _bot.command('features', _onFeatures);
    _bot.command('help', _onHelp);

    _log.info('Registered 17 command handlers');

    // All inline keyboard callbacks registered once here
    _registerCallbacks();
  }

  void _registerCallbacks() {
    // Chain selection (from /chain keyboard)
    _bot.callbackQuery(RegExp(r'^chain:'), _onChainCallback);
    // Feature flag toggles (from /features keyboard)
    _bot.callbackQuery(RegExp(r'^feature_toggle:'), _onFeatureToggleCallback);
    // Generic command shortcuts embedded in message keyboards
    _bot.callbackQuery(RegExp(r'^cmd:'), _onCommandShortcut);
  }

  /// Backwards-compat — telegram_bot.dart calls this after register().
  /// Callbacks are now wired inside register() so this is a no-op.
  void registerFeatureToggleCallback() {}

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMAND HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  // ── /start ────────────────────────────────────────────────────────────────
  Future<void> _onStart(
    Context ctx, {
    required Future<void> Function(List<BotCommand>, int chatId) setCommandsCallback,
  }) async {
    final user = ctx.update.message?.from;
    if (user == null) return;

    await setCommandsCallback(_allBotCommands(), user.id);

    final name = user.firstName;

    final keyboard = InlineKeyboard()
        .text('💳 Set Wallet', 'cmd:wallet')
        .text('🔗 Choose Chain', 'cmd:chain')
        .row()
        .text('⚙️ Risk Settings', 'cmd:risk')
        .text('❓ Help', 'cmd:help')
        .row()
        .text('🚀 Activate Bot', 'cmd:activate');

    await ctx.reply(
      '👋 Welcome to *DegenBot*, $name!\n\n'
      '🤖 I\'m a rule-based crypto trading bot. I scan DexScreener, run a '
      '5-layer safety check, and apply your exact trading rules to decide '
      'buy / watch / reject — deterministic logic, no LLM voting.\n\n'
      '*Get started in 2 minutes:*\n'
      '1️⃣  Set your wallet → /wallet\n'
      '2️⃣  Choose your chain → /chain\n'
      '3️⃣  Review risk settings → /risk\n'
      '4️⃣  Activate the bot → /activate\n\n'
      '💡 Or paste any contract address — I\'ll analyse it instantly.\n'
      '_Try: "What coins are you watching?"_',
      parseMode: ParseMode.markdown,
      replyMarkup: keyboard,
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
        '❌ *Specify a contract address.*\n\n'
        'Usage: `/analyze <address> [chain]`\n\n'
        'Or just paste the address directly — chain is auto-detected.',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    final contractAddress = args[1].trim();
    final chain = args.length >= 3 ? args[2].trim().toLowerCase() : user.activeChain;

    await ctx.reply(
      '🔍 *Scanning* `$contractAddress`...\n⏳ Running 5-layer analysis.',
      parseMode: ParseMode.markdown,
    );

    try {
      final report = await _pipeline.analyze(
        contractAddress: contractAddress,
        chain: chain,
      );

      final buttons = MessageFormatter.tokenAnalysisButtons(report);

      await ctx.reply(
        MessageFormatter.tokenAnalysisReport(report),
        parseMode: ParseMode.markdown,
        replyMarkup: _buttonsToKeyboard(buttons),
      );
    } catch (e, st) {
      _log.severe('Error in /analyze', e, st);
      await ctx.reply('❌ Analysis failed — check the address and try again.');
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

    final keyboard = InlineKeyboard();
    if (user.isBotActive) {
      keyboard.text('🛑 Deactivate', 'cmd:deactivate');
    } else {
      keyboard.text('🚀 Activate', 'cmd:activate');
    }
    keyboard
        .text('📂 Positions', 'cmd:positions')
        .row()
        .text('📊 Stats', 'cmd:stats')
        .text('📜 History', 'cmd:history')
        .row()
        .text('⚙️ Risk', 'cmd:risk')
        .text('🔗 Chain', 'cmd:chain');

    await ctx.reply(
      MessageFormatter.statusMessage(
        user: user,
        openTradeCount: openTrades.length,
        tradesToday: tradesToday,
        riskProfile: riskProfile,
      ),
      parseMode: ParseMode.markdown,
      replyMarkup: keyboard,
    );
  }

  // ── /wallet ───────────────────────────────────────────────────────────────
  Future<void> _onWallet(Conversation<Context> conversation, Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    if (user.walletAddress != null) {
      await ctx.reply(
        '📍 *Current wallet* (${user.activeChain.toUpperCase()}):\n'
        '`${user.walletAddress}`\n\n'
        'Send a new address to change it, or type /cancel to keep the current one.',
        parseMode: ParseMode.markdown,
      );
    } else {
      await ctx.reply(
        '💳 Enter your *${user.activeChain.toUpperCase()}* wallet address:\n\n'
        '⚠️ Public address only — never share your private key or seed phrase.',
        parseMode: ParseMode.markdown,
      );
    }

    final response = await conversation.waitUntil(
      (event) => (event.message?.text ?? '').isNotEmpty,
      timeout: const Duration(minutes: 2),
      otherwise: (ctx) async => await ctx.reply('⏰ Timed out — wallet unchanged. Try /wallet again.'),
    );

    final address = response.text?.trim() ?? '';
    if (address == '/cancel') {
      await ctx.reply('Cancelled — wallet unchanged.');
      return;
    }

    if (!_validateWalletAddress(address, user.activeChain)) {
      await ctx.reply(
        '❌ That doesn\'t look like a valid *${user.activeChain.toUpperCase()}* address.\n'
        'Try /wallet again.',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    await _users.update(user.copyWith(walletAddress: address));

    final keyboard = InlineKeyboard()
        .text('🚀 Activate Bot', 'cmd:activate')
        .text('⚙️ Risk Settings', 'cmd:risk');

    await ctx.reply(
      '✅ *Wallet saved!*\n`$address`\n\n'
      'Ready to trade? Activate the bot below.',
      parseMode: ParseMode.markdown,
      replyMarkup: keyboard,
    );
  }

  // ── /chain ────────────────────────────────────────────────────────────────
  // NOTE: callback is in _onChainCallback(), registered once in _registerCallbacks()
  Future<void> _onChain(Context ctx) async {
    final keyboard = InlineKeyboard()
        .text('☀️ Solana', 'chain:solana')
        .text('🔷 Ethereum', 'chain:ethereum')
        .row()
        .text('🟡 BNB Chain', 'chain:bnb')
        .text('🔵 Base', 'chain:base');

    await ctx.reply(
      '🔗 *Select your blockchain:*\n\n'
      '_Switching chain clears your wallet address — you\'ll need to set a new one._',
      parseMode: ParseMode.markdown,
      replyMarkup: keyboard,
    );
  }

  // ── /activate ─────────────────────────────────────────────────────────────
  Future<void> _onActivate(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    if (user.isBotActive) {
      await ctx.reply(
        '⚡ *Bot is already active.*',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard()
            .text('📂 Positions', 'cmd:positions')
            .text('🛑 Deactivate', 'cmd:deactivate'),
      );
      return;
    }

    if (user.walletAddress == null) {
      await ctx.reply(
        '⚠️ *Wallet required before activating.*\nSet your address first.',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard().text('💳 Set Wallet', 'cmd:wallet'),
      );
      return;
    }

    await _users.setBotActive(user.id!, active: true);

    await ctx.reply(
      '🚀 *Bot activated!*\n\n'
      'Scanning DexScreener on *${user.activeChain.toUpperCase()}*.\n'
      'You\'ll get a notification when I find a candidate or a position needs action.\n\n'
      '_Exit strategy: +800% from ATL → first sell → watch for -80% rebuy._',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard()
          .text('📂 Positions', 'cmd:positions')
          .text('🛑 Deactivate', 'cmd:deactivate')
          .row()
          .text('⚙️ Risk Settings', 'cmd:risk'),
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
      '🛑 *Bot deactivated.*\n\n'
      'Open positions are not automatically closed — check them below.',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard()
          .text('📂 Check Positions', 'cmd:positions')
          .text('🚀 Reactivate', 'cmd:activate'),
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
      await ctx.reply(
        '📭 *No open positions.*\n'
        'The bot will notify you when it opens a trade.',
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard()
            .text('📊 Stats', 'cmd:stats')
            .text('📜 History', 'cmd:history'),
      );
      return;
    }

    await ctx.reply(
      MessageFormatter.positionsList(trades),
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard()
          .text('📊 Stats', 'cmd:stats')
          .text('📜 History', 'cmd:history')
          .row()
          .text('🔄 Refresh', 'cmd:positions'),
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
      await ctx.reply('📭 *No trade history yet.*', parseMode: ParseMode.markdown);
      return;
    }

    await ctx.reply(
      MessageFormatter.tradeHistory(trades),
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard()
          .text('📊 Stats', 'cmd:stats')
          .text('📂 Positions', 'cmd:positions'),
    );
  }

  // ── /stats ────────────────────────────────────────────────────────────────
  Future<void> _onStats(Context ctx) async {
    final telegramId = ctx.update.message?.from?.id;
    if (telegramId == null) return;

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return;

    final history = await _trades.getTradeHistory(user.id!, limit: 100);
    final open = await _trades.getOpenTrades(user.id!);

    await ctx.reply(
      MessageFormatter.statsMessage(history, open),
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard()
          .text('📂 Positions', 'cmd:positions')
          .text('📜 History', 'cmd:history'),
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
      replyMarkup: InlineKeyboard()
          .text('📊 Status', 'cmd:status')
          .text('🚀 Activate', 'cmd:activate'),
    );
  }

  // ── /features ─────────────────────────────────────────────────────────────
  Future<void> _onFeatures(Context ctx) async {
    final allFlags = await _flags.getAllFlags();
    await ctx.reply(
      MessageFormatter.featuresOverview(allFlags),
      parseMode: ParseMode.markdown,
      replyMarkup: _buildFeaturesKeyboard(allFlags),
    );
  }

  // ── /macro ────────────────────────────────────────────────────────────────
  Future<void> _onMacro(Context ctx) async {
    final text = ctx.update.message?.text?.trim() ?? '';
    final args = text.split(' ').where((s) => s.isNotEmpty).toList();
    final macro = MacroContextService.instance;

    if (args.length < 2) {
      await macro.refreshBtcPrice();
      await ctx.reply(
        macro.statusMessage,
        parseMode: ParseMode.markdown,
        replyMarkup: InlineKeyboard()
            .text('🟢 Bull', 'cmd:macro_bull')
            .text('🟡 Caution', 'cmd:macro_caution')
            .row()
            .text('⛔ Pause', 'cmd:macro_pause')
            .text('🔄 Bear Ending', 'cmd:macro_bearending')
            .row()
            .text('🔃 Refresh BTC Price', 'cmd:macro_refresh'),
      );
      return;
    }

    final overrideStr = args[1].toLowerCase();
    MacroState? state = switch (overrideStr) {
      'bull' || 'bullish' => MacroState.bullish,
      'caution' => MacroState.caution,
      'pause' => MacroState.pause,
      'bearending' || 'bear' => MacroState.bearEnding,
      _ => null,
    };

    if (overrideStr == 'auto' || overrideStr == 'reset') {
      macro.clearAnalystOverride();
      await ctx.reply('✅ Macro override cleared — back to automated BTC tracking.');
      return;
    }

    if (state == null) {
      await ctx.reply(
        '❌ Unknown state. Options: `bull` | `caution` | `pause` | `bearending` | `auto`',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    final note = args.length > 2 ? args.sublist(2).join(' ') : null;
    macro.setAnalystState(state, note: note);
    await ctx.reply(
      '✅ Macro set to *${overrideStr.toUpperCase()}*${note != null ? '\n_${note}_' : ''}',
      parseMode: ParseMode.markdown,
    );
  }

  // ── /mcap ─────────────────────────────────────────────────────────────────
  Future<void> _onMcap(Context ctx) async {
    final text = ctx.update.message?.text?.trim() ?? '';
    final args = text.split(' ').where((s) => s.isNotEmpty).toList();

    if (args.length < 3) {
      final current = _pipeline.mcapFilter;
      await ctx.reply(
        '📐 *MCap Filter*\n\n'
        'Current: *\$${_fmtK(current.minUsd)} – \$${_fmtK(current.maxUsd)}*\n\n'
        'Usage: `/mcap <min> <max>` (in USD)\n'
        'Example: `/mcap 500 5000`\n\n'
        '_Default: \$300 – \$3,000_',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    final minUsd = double.tryParse(args[1]);
    final maxUsd = double.tryParse(args[2]);

    if (minUsd == null || maxUsd == null || minUsd >= maxUsd || minUsd < 0) {
      await ctx.reply('❌ Invalid range. Example: `/mcap 300 3000`', parseMode: ParseMode.markdown);
      return;
    }

    _pipeline.setMcapFilter(McapFilter(minUsd: minUsd, maxUsd: maxUsd));
    await ctx.reply(
      '✅ MCap filter: *\$${_fmtK(minUsd)} – \$${_fmtK(maxUsd)}*\n'
      '_Applies to all future scans this session._',
      parseMode: ParseMode.markdown,
    );
  }

  // ── /reanalyze ────────────────────────────────────────────────────────────
  Future<void> _onReanalyze(Context ctx) async {
    final text = ctx.update.message?.text?.trim() ?? '';
    final args = text.split(' ').where((s) => s.isNotEmpty).toList();

    if (args.length < 2) {
      await ctx.reply(
        '❌ Usage: `/reanalyze <address>`',
        parseMode: ParseMode.markdown,
      );
      return;
    }

    final address = args[1].trim();
    final wasInCache = TokenCacheService.instance.isAnalyzed(address);
    TokenCacheService.instance.evict(address);

    await ctx.reply(
      wasInCache
          ? '🔄 Cache cleared for `$address`.\nPaste the address to run a fresh analysis.'
          : '⚠️ `$address` was not cached — will be analysed fresh when you paste it.',
      parseMode: ParseMode.markdown,
    );
  }

  // ── /cache ────────────────────────────────────────────────────────────────
  Future<void> _onCache(Context ctx) async {
    final cache = TokenCacheService.instance;
    final candidates = cache.buyCandidates;

    final buf = StringBuffer('💾 *Token Cache*\n\n');
    buf.writeln('Analysed: *${cache.size}* tokens');
    buf.writeln('Buy candidates: *${cache.candidateCount}*');
    buf.writeln('Rejected: *${cache.rejectedCount}*');

    if (candidates.isNotEmpty) {
      buf.writeln('\n🟢 *Buy Candidates:*');
      for (final c in candidates.take(10)) {
        final shortAddr = c.contractAddress.length > 8
            ? '${c.contractAddress.substring(0, 8)}...'
            : c.contractAddress;
        buf.writeln('• *${c.tokenSymbol}* — `$shortAddr`');
      }
    }

    await ctx.reply(
      buf.toString(),
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard()
          .text('📂 Positions', 'cmd:positions')
          .text('📊 Status', 'cmd:status'),
    );
  }

  // ── /help ─────────────────────────────────────────────────────────────────
  Future<void> _onHelp(Context ctx) async {
    await ctx.reply(
      '📖 *DegenBot Commands*\n\n'
      '*⚙️ Setup*\n'
      '/wallet — Set or change wallet address\n'
      '/chain — Switch blockchain (Solana / ETH / BNB / Base)\n'
      '/risk — View or change risk settings\n'
      '/features — Toggle data sources on/off\n\n'
      '*📊 Status*\n'
      '/status — Bot state, wallet, open trades\n'
      '/positions — Open trades with ATL tracking\n'
      '/history — Last 10 closed trades\n'
      '/stats — ROI and performance summary\n\n'
      '*🧠 Strategy*\n'
      '/macro [state] — BTC macro context or analyst override\n'
      '/mcap [min] [max] — MCap filter range\n\n'
      '*🔍 Analysis*\n'
      '/analyze <address> — Run 5-layer token analysis\n'
      '/reanalyze <address> — Force re-analysis (clears cache)\n'
      '/cache — Cached token stats and buy candidates\n\n'
      '*🤖 Control*\n'
      '/activate — Turn bot ON\n'
      '/deactivate — Turn bot OFF\n\n'
      '_Tip: Paste any contract address to analyse without typing /analyze_',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard()
          .text('📊 Status', 'cmd:status')
          .text('🚀 Activate', 'cmd:activate'),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALLBACK HANDLERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _onChainCallback(Context ctx) async {
    final chain = ctx.callbackQuery?.data?.split(':').last ?? 'solana';
    final userId = ctx.callbackQuery?.from.id;
    if (userId == null) return;

    final user = await _users.findByTelegramId(userId);
    if (user == null) return;

    await _users.update(user.copyWith(
      activeChain: chain,
      walletAddress: null,
      isBotActive: false,
      updatedAt: DateTime.now().toUtc(),
    ));

    await ctx.answerCallbackQuery(text: 'Switched to ${chain.toUpperCase()} ✅');
    await ctx.editMessageText(
      '✅ Chain set to *${chain.toUpperCase()}*\n\n'
      'Wallet cleared — set your new address below.',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard()
          .text('💳 Set Wallet', 'cmd:wallet')
          .text('📊 Status', 'cmd:status'),
    );
  }

  Future<void> _onFeatureToggleCallback(Context ctx) async {
    final flagName = ctx.callbackQuery?.data?.split(':').last;
    if (flagName == null) return;

    final newValue = await _flags.toggle(flagName);
    await ctx.answerCallbackQuery(
      text: '${newValue ? "Enabled" : "Disabled"} $flagName',
    );

    final allFlags = await _flags.getAllFlags();
    await ctx.editMessageText(
      MessageFormatter.featuresOverview(allFlags),
      parseMode: ParseMode.markdown,
      replyMarkup: _buildFeaturesKeyboard(allFlags),
    );
  }

  Future<void> _onCommandShortcut(Context ctx) async {
    final data = ctx.callbackQuery?.data ?? '';
    final shortcut = data.replaceFirst('cmd:', '');
    final userId = ctx.callbackQuery?.from.id;
    if (userId == null) return;

    await ctx.answerCallbackQuery();

    switch (shortcut) {
      case 'wallet':
        await ctx.reply('💳 Type /wallet to set your address.');
      case 'chain':
        await ctx.reply(
          '🔗 *Select your blockchain:*',
          parseMode: ParseMode.markdown,
          replyMarkup: InlineKeyboard()
              .text('☀️ Solana', 'chain:solana')
              .text('🔷 Ethereum', 'chain:ethereum')
              .row()
              .text('🟡 BNB Chain', 'chain:bnb')
              .text('🔵 Base', 'chain:base'),
        );
      case 'activate':
        final user = await _users.findByTelegramId(userId);
        if (user == null) return;
        if (user.isBotActive) { await ctx.reply('⚡ Already active.'); return; }
        if (user.walletAddress == null) {
          await ctx.reply('⚠️ Set a wallet first → /wallet');
          return;
        }
        await _users.setBotActive(user.id!, active: true);
        await ctx.reply('🚀 *Bot activated!* Scanning on ${user.activeChain.toUpperCase()}.', parseMode: ParseMode.markdown);
      case 'deactivate':
        final user = await _users.findByTelegramId(userId);
        if (user == null) return;
        await _users.setBotActive(user.id!, active: false);
        await ctx.reply('🛑 Bot deactivated.');
      case 'positions':
        await ctx.reply('Use /positions to see open trades.');
      case 'history':
        await ctx.reply('Use /history to see closed trades.');
      case 'stats':
        await ctx.reply('Use /stats for your performance summary.');
      case 'status':
        await ctx.reply('Use /status for full bot status.');
      case 'risk':
        await ctx.reply('Use /risk to view or update risk settings.');
      case 'help':
        await ctx.reply('Use /help for the full command list.');
      case 'analyze_prompt':
        await ctx.reply('Paste any contract address and I\'ll analyse it — no command needed.');
      case 'macro_bull':
        MacroContextService.instance.setAnalystState(MacroState.bullish);
        await ctx.reply('🟢 Macro override: *BULLISH* — buying active.', parseMode: ParseMode.markdown);
      case 'macro_caution':
        MacroContextService.instance.setAnalystState(MacroState.caution);
        await ctx.reply('🟡 Macro override: *CAUTION* — buying conservatively.', parseMode: ParseMode.markdown);
      case 'macro_pause':
        MacroContextService.instance.setAnalystState(MacroState.pause);
        await ctx.reply('⛔ Macro override: *PAUSE* — no new buys.', parseMode: ParseMode.markdown);
      case 'macro_bearending':
        MacroContextService.instance.setAnalystState(MacroState.bearEnding);
        await ctx.reply('🔄 Macro: *BEAR ENDING* — accumulation mode.', parseMode: ParseMode.markdown);
      case 'macro_refresh':
        await MacroContextService.instance.refreshBtcPrice();
        await ctx.reply(MacroContextService.instance.statusMessage, parseMode: ParseMode.markdown);
      default:
        _log.warning('Unknown cmd shortcut: $shortcut');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  InlineKeyboard _buildFeaturesKeyboard(Map<String, bool> flags) {
    final keyboard = InlineKeyboard();
    for (final name in FeatureFlag.all) {
      final isOn = flags[name] ?? false;
      keyboard.text('${isOn ? "🟢" : "⚪"} $name', 'feature_toggle:$name');
      keyboard.row();
    }
    return keyboard;
  }

  /// Convert MessageFormatter's MessageButton list to an InlineKeyboard.
  /// Returns null if no buttons — callers pass null replyMarkup to omit keyboard.
  InlineKeyboard? _buttonsToKeyboard(List<MessageButton> buttons) {
    if (buttons.isEmpty) return null;
    final keyboard = InlineKeyboard();
    for (final btn in buttons) {
      if (btn.url != null) {
        keyboard.url(btn.text, btn.url!);
      } else if (btn.callbackData != null) {
        keyboard.text(btn.text, btn.callbackData!);
      }
    }
    return keyboard;
  }

  bool _validateWalletAddress(String address, String chain) {
    return switch (chain) {
      'solana' => RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(address),
      'ethereum' || 'bnb' || 'base' => RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address),
      _ => address.length >= 10,
    };
  }

  String _fmtK(double v) =>
      v >= 1000 ? '\$${(v / 1000).toStringAsFixed(0)}K' : '\$${v.toStringAsFixed(0)}';

  List<BotCommand> _allBotCommands() => [
    BotCommand(command: 'start',      description: 'Welcome and setup guide'),
    BotCommand(command: 'status',     description: 'Bot status, wallet, open trades'),
    BotCommand(command: 'wallet',     description: 'Set or change wallet address'),
    BotCommand(command: 'chain',      description: 'Switch blockchain (Solana/ETH/BNB/Base)'),
    BotCommand(command: 'analyze',    description: 'Analyse a token by contract address'),
    BotCommand(command: 'activate',   description: 'Turn the trading bot ON'),
    BotCommand(command: 'deactivate', description: 'Turn the trading bot OFF'),
    BotCommand(command: 'positions',  description: 'Open trades with ATL tracking'),
    BotCommand(command: 'history',    description: 'Last 10 closed trades'),
    BotCommand(command: 'stats',      description: 'ROI and performance summary'),
    BotCommand(command: 'risk',       description: 'View or change risk settings'),
    BotCommand(command: 'macro',      description: 'BTC macro context or analyst override'),
    BotCommand(command: 'mcap',       description: 'Set MCap filter range (default \$300–\$3000)'),
    BotCommand(command: 'reanalyze',  description: 'Force re-analysis (clears cache)'),
    BotCommand(command: 'cache',      description: 'Cached token stats and buy candidates'),
    BotCommand(command: 'features',   description: 'Toggle data sources on/off'),
    BotCommand(command: 'help',       description: 'Full command reference'),
  ];
}
