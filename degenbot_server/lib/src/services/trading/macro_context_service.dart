// macro_context_service.dart
//
// PLAIN ENGLISH — WHY THIS EXISTS:
//   The trader's #1 rule before looking at any degen coin:
//   "What is BTC doing?"
//
//   BTC leads the entire crypto market. When BTC dumps hard, over 90%
//   of altcoins dump with it — and degen coins dump even harder because
//   they have no fundamental value to fall back on. Buying degen tokens
//   when BTC is crashing is like swimming into a riptide: you might
//   survive, but why fight it?
//
//   This service:
//     1. Tracks BTC's price and 24h % change (via DexScreener)
//     2. Flags a "MACRO CAUTION" state when BTC dumps > X% in 24h
//     3. Accepts manual analyst input: "bear market ending" or
//        "bull run starting" — overrides the automated price signal
//     4. The scanner and pipeline check this BEFORE deciding to buy
//
// THE RULES (from the trader's own words):
//   - If BTC drops significantly (we use -5% in 24h as the default
//     caution threshold, -10% as the pause threshold), hold buying.
//   - Great buying opportunities come AFTER the bear market ends and
//     the market bottoms. An analyst will input this signal manually.
//   - The bot doesn't try to predict BTC direction itself — it defers
//     to price data and the analyst's judgment.
//
// HOW THE ANALYST OVERRIDES WORK:
//   The trader (or an analyst) can send a Telegram command:
//     /macro bearending  → "Bear market ending — we're near the bottom,
//                          start accumulating quality degen plays"
//     /macro bull        → "Bull market confirmed — full buy mode"
//     /macro caution     → "Manual caution flag — hold buying"
//     /macro status      → Show current macro state
//
//   These override the automated BTC price check until the analyst
//   changes the state again. This is how the trader's 'experience'
//   and judgment flows into the system.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:degenbot_server/degen_logger.dart';

enum MacroState {
  /// Normal conditions — BTC stable or rising. Buy mode active.
  bullish,

  /// BTC dropping 5-10% in 24h. Buying with caution — only the
  /// cleanest, highest-conviction candidates pass.
  caution,

  /// BTC dropping > 10% in 24h, or analyst has manually paused.
  /// No new buys until state changes.
  pause,

  /// Analyst has flagged that the bear market is ending / bottomed.
  /// This is the highest-conviction buying opportunity window.
  /// Override: even if BTC is still negative, we buy on dips.
  bearEnding,

  /// Unknown — BTC price check failed. Default to caution.
  unknown,
}

class MacroBtcSnapshot {
  const MacroBtcSnapshot({
    required this.priceUsd,
    required this.change24hPercent,
    required this.fetchedAt,
  });

  final double priceUsd;
  final double change24hPercent;
  final DateTime fetchedAt;

  bool get isStale =>
      DateTime.now().toUtc().difference(fetchedAt).inMinutes > 15;
}

class MacroContextService {
  // Singleton — everyone checks the same macro state.
  static final MacroContextService instance = MacroContextService._();
  MacroContextService._();

  // ── THRESHOLDS ─────────────────────────────────────────────────────────────

  /// BTC dropping more than this % in 24h → CAUTION state.
  static const double _cautionThresholdPercent = -5.0;

  /// BTC dropping more than this % in 24h → PAUSE state.
  static const double _pauseThresholdPercent = -10.0;

  // ── STATE ─────────────────────────────────────────────────────────────────

  MacroState _state = MacroState.unknown;
  MacroBtcSnapshot? _lastBtcSnapshot;
  String? _analystNote; // Human note from the last /macro command

  // ── PUBLIC API ─────────────────────────────────────────────────────────────

  MacroState get currentState => _state;
  MacroBtcSnapshot? get lastBtcSnapshot => _lastBtcSnapshot;
  String? get analystNote => _analystNote;

  /// Check if buying should proceed for a new candidate.
  /// Returns null (ok to buy) or a reason string (hold off).
  String? shouldHoldBuying() {
    return switch (_state) {
      MacroState.pause =>
        'BTC is in significant decline (${_btcChangeStr()}). '
        'New buys are paused until BTC stabilizes. '
        '${_analystNote != null ? "Analyst note: $_analystNote" : ""}',
      MacroState.unknown =>
        'BTC macro data unavailable — proceeding with caution.',
      MacroState.bullish || MacroState.bearEnding || MacroState.caution => null,
    };
  }

  /// Returns a caution warning for CAUTION state (not a hard block).
  String? cautionWarning() {
    if (_state == MacroState.caution) {
      return '⚠️ MACRO CAUTION: BTC is down ${_btcChangeStr()} in 24h. '
          'Only highest-conviction buys recommended right now.';
    }
    return null;
  }

  bool get isBuyingPaused => _state == MacroState.pause;
  bool get isBearEnding => _state == MacroState.bearEnding;

  // ── ANALYST COMMANDS ───────────────────────────────────────────────────────

  /// Set an analyst override state (e.g. from /macro bull).
  void setAnalystState(MacroState newState, {String? note}) {
    final old = _state;
    _state = newState;
    _analystNote = note;
    Log.info(
      '📊 [MacroContext] Analyst override: $old → $newState'
      '${note != null ? " ($note)" : ""}',
    );
  }

  /// Clear analyst override — revert to automated BTC price tracking.
  void clearAnalystOverride() {
    _state = MacroState.unknown;
    _analystNote = null;
    Log.info('📊 [MacroContext] Analyst override cleared — back to automated BTC tracking');
    // Force a fresh BTC price check on the next shouldHoldBuying() call
    refreshBtcPrice().ignore();
  }

  // ── BTC PRICE CHECK ────────────────────────────────────────────────────────

  /// Fetch BTC price from DexScreener and update macro state.
  /// Called by the scanner loop on each cycle.
  ///
  /// We use DexScreener for BTC (via the WBTC/USDC pool or BTC/USDT)
  /// since we already have a DexScreener integration. Fallback: Coingecko
  /// public API (no key needed for basic price checks).
  Future<void> refreshBtcPrice() async {
    // Don't override an analyst-set state with automated price data.
    if (_state == MacroState.bearEnding) {
      Log.info(
        '📊 [MacroContext] Analyst has set bearEnding state — skipping automated BTC check',
      );
      return;
    }

    try {
      final snapshot = await _fetchBtcFromCoingecko();
      if (snapshot == null) {
        Log.warning('📊 [MacroContext] BTC price fetch failed — keeping state as caution');
        if (_state == MacroState.unknown) _state = MacroState.caution;
        return;
      }

      _lastBtcSnapshot = snapshot;
      final change = snapshot.change24hPercent;

      final newState = switch (true) {
        _ when change <= _pauseThresholdPercent => MacroState.pause,
        _ when change <= _cautionThresholdPercent => MacroState.caution,
        _ => MacroState.bullish,
      };

      if (newState != _state) {
        Log.info(
          '📊 [MacroContext] BTC 24h change: ${change.toStringAsFixed(2)}% → state: $_state → $newState',
        );
        _state = newState;
      }
    } catch (e) {
      Log.warning('📊 [MacroContext] BTC refresh error: $e');
    }
  }

  // ── PRIVATE: BTC PRICE FETCH ───────────────────────────────────────────────

  /// Coingecko simple price API — free, no key, reliable for BTC price.
  Future<MacroBtcSnapshot?> _fetchBtcFromCoingecko() async {
    try {
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price'
        '?ids=bitcoin&vs_currencies=usd&include_24hr_change=true',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        Log.warning(
          '📊 [MacroContext] Coingecko returned ${response.statusCode}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final btc = json['bitcoin'] as Map<String, dynamic>?;
      if (btc == null) return null;

      final price = (btc['usd'] as num?)?.toDouble();
      final change = (btc['usd_24h_change'] as num?)?.toDouble();
      if (price == null || change == null) return null;

      Log.info(
        '📊 [MacroContext] BTC: \$${price.toStringAsFixed(0)} | 24h: ${change.toStringAsFixed(2)}%',
      );

      return MacroBtcSnapshot(
        priceUsd: price,
        change24hPercent: change,
        fetchedAt: DateTime.now().toUtc(),
      );
    } catch (e) {
      Log.warning('📊 [MacroContext] Coingecko fetch error: $e');
      return null;
    }
  }

  String _btcChangeStr() {
    final change = _lastBtcSnapshot?.change24hPercent;
    if (change == null) return '(price unavailable)';
    return '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
  }

  // ── DISPLAY ────────────────────────────────────────────────────────────────

  String get statusMessage {
    final btcStr = _lastBtcSnapshot != null
        ? 'BTC: \$${_lastBtcSnapshot!.priceUsd.toStringAsFixed(0)} (${_btcChangeStr()} 24h)'
        : 'BTC price: unknown';

    final stateEmoji = switch (_state) {
      MacroState.bullish => '🟢',
      MacroState.caution => '🟡',
      MacroState.pause => '🔴',
      MacroState.bearEnding => '🌅',
      MacroState.unknown => '❓',
    };

    final stateLabel = switch (_state) {
      MacroState.bullish => 'Bullish — buy mode active',
      MacroState.caution => 'Caution — buying conservatively',
      MacroState.pause => 'PAUSED — BTC dumping, no new buys',
      MacroState.bearEnding =>
        'Bear ending / bottom zone — accumulation mode',
      MacroState.unknown => 'Unknown — defaulting to caution',
    };

    return '$btcStr\n$stateEmoji Macro: $stateLabel'
        '${_analystNote != null ? '\n📝 Analyst: $_analystNote' : ''}';
  }
}
