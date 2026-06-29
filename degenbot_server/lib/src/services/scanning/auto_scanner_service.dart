// auto_scanner_service.dart
//
// THE BRAIN OF THE BOT — the background scan loop that runs without
// any user input.
//
// PLAIN ENGLISH — WHAT THIS DOES:
//   Every 30 minutes (configurable), this service:
//     1. Refreshes the BTC macro context (is the market pumping or dumping?)
//     2. Checks which chains have active users (no point scanning Solana
//        if nobody with the bot on is using Solana)
//     3. For each active chain: fetches trending + newly listed tokens
//        from DexScreener
//     4. Skips any token the TokenCacheService has already processed
//     5. Runs the full 5-layer intelligence pipeline on each new token
//     6. If the rule engine says BUY:
//        → Saves the token to coin_candidates in Supabase
//        → Sends a push notification to every active user on that chain
//     7. If the rule engine says WATCH:
//        → Saves silently to coin_candidates (no notification)
//
// MACRO GATE:
//   If BTC is in PAUSE state (>-10% in 24h), buy candidates are saved
//   but NOT sent as notifications. The scanner keeps running — it just
//   holds the alerts until macro recovers. This is how the trader avoids
//   buying into a market-wide crash.
//
//   CAUTION state (-5% to -10%): scanner still sends alerts, but the
//   notification includes a macro caution warning.
//
// RATE LIMITING & COST:
//   Each analysis costs API calls to GoPlus, RugCheck, Bitquery, etc.
//   TokenCacheService ensures we never re-analyze the same address.
//   After the first cycle, most tokens are cached — subsequent cycles
//   are very cheap (mostly DexScreener calls to discover new addresses).
//
// CONTROLS (available to command handlers):
//   scanner.start()           — begin the loop
//   scanner.stop()            — halt the loop (bot deactivated)
//   scanner.runOnce()         — manual one-shot scan (for testing or /scan command)
//   scanner.isRunning         — check if loop is active
//   scanner.stats             — scan statistics for /status command

import 'dart:async';
import 'package:degenbot_server/degen_logger.dart';
import 'package:degenbot_server/src/services/dex/dexscreener_service.dart';
import 'package:degenbot_server/src/services/intelligence/token_intelligence_pipeline.dart';
import 'package:degenbot_server/src/services/intelligence/token_intelligence_report.dart';
import 'package:degenbot_server/src/services/messaging/messaging_service_interface.dart';
import 'package:degenbot_server/src/services/repository/coin_candidate_repository.dart';
import 'package:degenbot_server/src/services/repository/user_repository.dart';
import 'package:degenbot_server/src/services/trading/macro_context_service.dart';
import 'package:degenbot_server/src/services/trading/token_cache_service.dart';
import 'package:degenbot_server/src/bot/utils/message_formatter.dart';
import 'package:degenbot_server/src/generated/protocol.dart';

/// Scan stats — surfaced by /status command.
class ScannerStats {
  int totalCyclesRun = 0;
  int totalTokensScanned = 0;
  int totalBuyCandidatesFound = 0;
  int totalNotificationsSent = 0;
  int totalMacroGateSuppressed = 0;
  DateTime? lastCycleAt;
  DateTime? lastBuyCandidateAt;
  String? lastBuyCandidateSymbol;

  @override
  String toString() {
    final lastCycle = lastCycleAt != null
        ? _ago(lastCycleAt!)
        : 'never';
    final lastBuy = lastBuyCandidateAt != null
        ? '${lastBuyCandidateSymbol ?? "?"} (${_ago(lastBuyCandidateAt!)})'
        : 'none yet';

    return 'Cycles: $totalCyclesRun | '
        'Scanned: $totalTokensScanned | '
        'Buy signals: $totalBuyCandidatesFound | '
        'Notifications: $totalNotificationsSent | '
        'Last cycle: $lastCycle | '
        'Last buy: $lastBuy';
  }

  static String _ago(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class AutoScannerService {
  // ── CONFIGURATION ─────────────────────────────────────────────────────────

  /// How often the scanner loop runs.
  /// 30 minutes is the default — enough to catch trending new tokens without
  /// hammering APIs or spamming users.
  static const Duration _scanInterval = Duration(minutes: 30);

  /// Chains the scanner knows how to poll.
  static const List<String> _supportedChains = [
    'solana',
    'ethereum',
    'bnb',
    'base',
  ];

  /// Max tokens to analyze per chain per cycle (cache hits don't count toward
  /// this — we analyze at most N FRESH tokens per chain).
  static const int _maxFreshPerChain = 20;

  /// Delay between individual token analyses within a chain.
  /// Prevents rate-limit bursts on the analysis APIs (GoPlus, Bitquery, etc.)
  static const Duration _interTokenDelay = Duration(milliseconds: 500);

  // ── DEPENDENCIES ──────────────────────────────────────────────────────────

  final TokenIntelligencePipeline _pipeline;
  final DexScreenerService _dex;
  final UserRepository _users;
  final CoinCandidateRepository _candidates;
  final IMessagingService _messaging;

  // ── STATE ─────────────────────────────────────────────────────────────────

  Timer? _scanTimer;
  bool _isRunning = false;
  bool _cycleInProgress = false; // guard against overlapping cycles
  final ScannerStats stats = ScannerStats();

  // ── CONSTRUCTOR ───────────────────────────────────────────────────────────

  AutoScannerService({
    required TokenIntelligencePipeline pipeline,
    required DexScreenerService dexScreenerService,
    required UserRepository userRepository,
    required CoinCandidateRepository coinCandidateRepository,
    required IMessagingService messagingService,
  })  : _pipeline = pipeline,
        _dex = dexScreenerService,
        _users = userRepository,
        _candidates = coinCandidateRepository,
        _messaging = messagingService;

  // ── PUBLIC API ─────────────────────────────────────────────────────────────

  bool get isRunning => _isRunning;

  /// Start the background scan loop.
  /// Runs the first cycle immediately, then repeats every [_scanInterval].
  void start() {
    if (_isRunning) {
      Log.info('🔍 [Scanner] Already running — ignoring duplicate start()');
      return;
    }
    _isRunning = true;
    Log.info(
      '🔍 [Scanner] Starting auto-scan loop (interval: ${_scanInterval.inMinutes}m)',
    );

    // Run immediately, then on schedule.
    _runCycleSafe();
    _scanTimer = Timer.periodic(_scanInterval, (_) => _runCycleSafe());
  }

  /// Stop the scan loop. In-progress cycles complete naturally.
  void stop() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isRunning = false;
    Log.info('🔍 [Scanner] Scan loop stopped');
  }

  /// Force an immediate scan cycle outside the regular schedule.
  /// Used by /scan command or for testing.
  Future<void> runOnce() async {
    Log.info('🔍 [Scanner] Manual one-shot scan triggered');
    await _runCycle();
  }

  // ── CYCLE MANAGEMENT ──────────────────────────────────────────────────────

  void _runCycleSafe() {
    _runCycle().catchError((e, st) {
      Log.warning('🔍 [Scanner] Cycle error (continuing): $e');
    });
  }

  Future<void> _runCycle() async {
    if (_cycleInProgress) {
      Log.info('🔍 [Scanner] Previous cycle still running — skipping this tick');
      return;
    }

    _cycleInProgress = true;
    try {
      await _executeCycle();
    } finally {
      _cycleInProgress = false;
    }
  }

  Future<void> _executeCycle() async {
    stats.totalCyclesRun++;
    Log.info(
      '🔍 [Scanner] ─── Cycle #${stats.totalCyclesRun} started ───',
    );

    // ── 1. Refresh BTC macro context ────────────────────────────────────────
    await MacroContextService.instance.refreshBtcPrice();
    final macroState = MacroContextService.instance.currentState;
    Log.info(
      '🔍 [Scanner] Macro state: ${macroState.name} | '
      '${MacroContextService.instance.statusMessage.split('\n').first}',
    );

    // ── 2. Find which chains have active users ──────────────────────────────
    final activeChains = await _users.getActiveBotChains();
    final scanChains = activeChains
        .where((c) => _supportedChains.contains(c))
        .toList();

    if (scanChains.isEmpty) {
      Log.info('🔍 [Scanner] No active users on any supported chain — idle');
      stats.lastCycleAt = DateTime.now().toUtc();
      return;
    }

    Log.info(
      '🔍 [Scanner] Active chains: ${scanChains.join(', ')}',
    );

    // ── 3. Scan each chain ──────────────────────────────────────────────────
    for (final chain in scanChains) {
      await _scanChain(chain);
    }

    stats.lastCycleAt = DateTime.now().toUtc();
    Log.info(
      '🔍 [Scanner] ─── Cycle #${stats.totalCyclesRun} complete ───',
    );
  }

  // ── CHAIN SCAN ─────────────────────────────────────────────────────────────

  Future<void> _scanChain(String chain) async {
    Log.info('🔍 [Scanner] Scanning $chain...');

    // Fetch candidates from two DexScreener sources:
    //   • Trending (token-boosts): recently promoted, high-volume tokens
    //   • Latest profiles: newest listed tokens
    // We combine them and deduplicate by address.

    final addresses = <String>{};

    try {
      final trending = await _dex.getTrendingCoins(chain: chain, limit: 15);
      for (final pair in trending) {
        final addr = pair['baseToken']?['address'] as String?;
        if (addr != null) addresses.add(addr.toLowerCase());
      }
      Log.info(
        '🔍 [Scanner]   Trending: ${trending.length} pairs → ${addresses.length} addresses',
      );
    } catch (e) {
      Log.warning('🔍 [Scanner]   Trending fetch failed for $chain: $e');
    }

    try {
      final profiles = await _dex.getLatestTokenProfiles(chain: chain);
      for (final profile in profiles.take(15)) {
        final addr = profile['tokenAddress'] as String?;
        if (addr != null) addresses.add(addr.toLowerCase());
      }
      Log.info(
        '🔍 [Scanner]   Profiles: ${profiles.length} tokens → ${addresses.length} total addresses',
      );
    } catch (e) {
      Log.warning('🔍 [Scanner]   Profile fetch failed for $chain: $e');
    }

    if (addresses.isEmpty) {
      Log.info('🔍 [Scanner]   No addresses found for $chain — skipping');
      return;
    }

    // ── Analyze fresh tokens only ──────────────────────────────────────────
    int freshCount = 0;
    for (final address in addresses) {
      // Hard cap: never analyze more than N fresh tokens per chain per cycle
      if (freshCount >= _maxFreshPerChain) {
        Log.info(
          '🔍 [Scanner]   Reached fresh-token cap ($_maxFreshPerChain) for $chain',
        );
        break;
      }

      // Skip if already analyzed (cache hit = zero API cost)
      if (TokenCacheService.instance.isAnalyzed(address)) {
        continue;
      }

      freshCount++;
      stats.totalTokensScanned++;

      Log.info(
        '🔍 [Scanner]   Analyzing token $freshCount/$_maxFreshPerChain: $address',
      );

      try {
        final report = await _pipeline.analyze(
          contractAddress: address,
          chain: chain,
        );
        await _handleReport(report, chain);
      } catch (e) {
        Log.warning(
          '🔍 [Scanner]   Analysis failed for $address: $e — skipping',
        );
      }

      // Brief pause between tokens to avoid hammering APIs
      if (freshCount < _maxFreshPerChain) {
        await Future.delayed(_interTokenDelay);
      }
    }

    Log.info(
      '🔍 [Scanner]   $chain done: $freshCount fresh tokens analyzed '
      '(${addresses.length - freshCount} cache hits skipped)',
    );
  }

  // ── REPORT HANDLING ────────────────────────────────────────────────────────

  Future<void> _handleReport(
    TokenIntelligenceReport report,
    String chain,
  ) async {
    switch (report.verdict) {
      case TokenVerdict.buy:
        await _handleBuyCandidate(report, chain);
      case TokenVerdict.watch:
        await _handleWatchCandidate(report, chain);
      case TokenVerdict.reject:
      case TokenVerdict.error:
        // Rejected/error tokens are in the TokenCacheService but don't go
        // to coin_candidates — no DB write needed.
        Log.info(
          '🔍 [Scanner]   ${report.tokenSymbol} → ${report.verdict.name} (not saved)',
        );
    }
  }

  Future<void> _handleBuyCandidate(
    TokenIntelligenceReport report,
    String chain,
  ) async {
    stats.totalBuyCandidatesFound++;
    stats.lastBuyCandidateAt = DateTime.now().toUtc();
    stats.lastBuyCandidateSymbol = report.tokenSymbol;

    Log.info(
      '✅ [Scanner] BUY candidate: ${report.tokenSymbol} (${report.contractAddress})',
    );

    // Save to DB regardless of macro state — we want the audit trail
    await _saveCandidateToDb(report, chain, status: 'pending');

    // ── Macro gate check ──────────────────────────────────────────────────
    final holdReason = MacroContextService.instance.shouldHoldBuying();
    if (holdReason != null) {
      stats.totalMacroGateSuppressed++;
      Log.warning(
        '⚠️ [Scanner] BUY signal for ${report.tokenSymbol} SUPPRESSED by macro gate: $holdReason',
      );
      return; // save to DB but don't notify
    }

    // ── Notify all active users on this chain ─────────────────────────────
    final activeUsers = await _users.getActiveBotUsers(chain: chain);
    if (activeUsers.isEmpty) {
      Log.info(
        '🔍 [Scanner]   No active users on $chain — buy signal saved but not sent',
      );
      return;
    }

    for (final user in activeUsers) {
      await _notifyUser(user, report);
    }

    Log.info(
      '📣 [Scanner] Notified ${activeUsers.length} user(s) about ${report.tokenSymbol}',
    );
  }

  Future<void> _handleWatchCandidate(
    TokenIntelligenceReport report,
    String chain,
  ) async {
    Log.info(
      '👁️ [Scanner] WATCH candidate: ${report.tokenSymbol} — saving silently',
    );
    // Save to DB as 'pending' with lower score — no push notification
    await _saveCandidateToDb(report, chain, status: 'pending');
  }

  // ── DB WRITE ───────────────────────────────────────────────────────────────

  Future<void> _saveCandidateToDb(
    TokenIntelligenceReport report,
    String chain, {
    required String status,
  }) async {
    try {
      final m = report.market;
      final candidate = CoinCandidate(
        chain: chain,
        contractAddress: report.contractAddress,
        name: report.tokenName,
        symbol: report.tokenSymbol,
        // aiScore 100 for buy candidates, 50 for watch, 0 for others
        aiScore: report.verdict == TokenVerdict.buy ? 100 : 50,
        liquidityUsd: m?.liquidityUsd ?? 0,
        volumeUsd24h: m?.volumeUsd24h ?? 0,
        priceUsd: m?.priceUsd ?? 0,
        marketCapUsd: m?.marketCapUsd,
        holderCount: m?.holderCount,
        priceChange1h: m?.priceChange1h,
        priceChange6h: m?.priceChange6h,
        priceChange24h: m?.priceChange24h,
        aiReasoning: report.aiReasoning,
        status: status,
        scannedAt: DateTime.now().toUtc(),
      );

      await _candidates.upsert(candidate);
    } catch (e) {
      // Never let a DB write failure break the scan loop
      Log.warning(
        '🔍 [Scanner] DB write failed for ${report.tokenSymbol}: $e',
      );
    }
  }

  // ── NOTIFICATION ───────────────────────────────────────────────────────────

  Future<void> _notifyUser(User user, TokenIntelligenceReport report) async {
    try {
      final message = MessageFormatter.buySignalNotification(report);
      final buttons = MessageFormatter.tokenAnalysisButtons(report);

      // Add a "Full Report" button so the user can request the complete analysis
      final allButtons = [
        ...buttons,
        // The full-report callback isn't in command_handlers yet —
        // pressing it will fall through to the AI handler which re-analyzes.
        // Phase 3 will add a proper /fullreport callback.
      ];

      final caution = MacroContextService.instance.cautionWarning();
      final bodyText = caution != null
          ? '$message\n\n$caution'
          : message;

      await _messaging.sendButtons(
        recipient: user.telegramId.toString(),
        bodyText: bodyText,
        buttons: allButtons,
      );

      stats.totalNotificationsSent++;
    } catch (e) {
      // Individual notification failures are non-fatal — keep notifying others
      Log.warning(
        '🔍 [Scanner] Failed to notify user ${user.telegramId} about '
        '${report.tokenSymbol}: $e',
      );
    }
  }
}
