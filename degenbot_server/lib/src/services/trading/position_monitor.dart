// position_monitor.dart
//
// THE SELL BRAIN. This is where the trader's exit strategy lives.
//
// PLAIN ENGLISH — THE TRADER'S SELL RULES:
//
//   After a coin is bought, we track it continuously as its price moves.
//   Here's the exact exit strategy the trader uses:
//
//   1. RECORD THE ATL (All-Time Low):
//      When we buy a coin, its entry price IS its current ATL.
//      As the price falls further (sometimes it dips before it pumps),
//      we keep updating the ATL downward. We never update it upward.
//
//   2. FIRST SELL AT +800% FROM ATL:
//      When the price reaches 9x the ATL (9x = 800% gain from the
//      bottom), we execute the first sell. This captures the massive
//      move from bottom to peak that degen coins make.
//      Example: ATL = $0.001 → first sell at $0.009
//
//   3. AFTER FIRST SELL — WATCH FOR 80% RETRACE:
//      Degen coins almost always retrace 80%+ after a pump. So after
//      the first sell, we don't celebrate and walk away — we watch the
//      price. When it drops 80% from where we sold, we BUY BACK IN.
//      Example: Sold at $0.009 → rebuy at $0.0018 (80% below $0.009)
//
//   4. REPEAT:
//      After the rebuy, we're back to tracking ATL for the next
//      800% trigger. The coin rides multiple cycles until we manually
//      close it or it dies.
//
// WHY THIS IS DIFFERENT FROM A STANDARD TP/SL:
//   A standard take-profit is a fixed % above entry. The trader's
//   strategy uses ATL instead of entry — which means if the coin
//   dumps further after you buy, your first-sell target ALSO moves
//   down, keeping the gain target relative to the actual bottom.
//   This is a more sophisticated, more realistic exit strategy for
//   volatile degen tokens.
//
// DATA REQUIREMENT:
//   The Trade model needs two new fields for this to work:
//     - allTimeLowPriceUsd (double) — the lowest price seen since buy
//     - firstSellExecuted (bool) — whether the first sell has happened
//     - firstSellPriceUsd (double?) — price at which we first sold
//   These are added to trade.spy.yaml (see that file's update).

import 'package:degenbot_server/degen_logger.dart';
import 'package:degenbot_server/src/services/dex/dexscreener_service.dart';

/// The outcome of a position check on a single open trade.
enum PositionAction {
  /// Hold — no action needed.
  hold,

  /// Price hit 800% from ATL — execute first sell now.
  firstSell,

  /// After first sell, price dropped 80% from peak — rebuy now.
  rebuy,

  /// Manual close or position is stale/dead.
  close,
}

/// The result of monitoring one position.
class PositionCheckResult {
  const PositionCheckResult({
    required this.contractAddress,
    required this.chain,
    required this.tokenSymbol,
    required this.action,
    required this.currentPriceUsd,
    required this.currentAtlUsd,
    required this.gainFromAtlPercent,
    this.firstSellPriceUsd,
    this.retraceFromPeakPercent,
    this.reason,
  });

  final String contractAddress;
  final String chain;
  final String tokenSymbol;
  final PositionAction action;
  final double currentPriceUsd;
  final double currentAtlUsd;
  final double gainFromAtlPercent;

  /// Only set when action == firstSell.
  final double? firstSellPriceUsd;

  /// How far price has fallen from the first-sell peak. Only set post-sell.
  final double? retraceFromPeakPercent;
  final String? reason;
}

/// In-memory state for an open position.
/// This mirrors what should also be persisted in the Trade row in Supabase.
class PositionState {
  PositionState({
    required this.contractAddress,
    required this.chain,
    required this.tokenSymbol,
    required this.entryPriceUsd,
    required this.openedAt,
  })  : allTimeLowPriceUsd = entryPriceUsd,
        firstSellExecuted = false,
        firstSellPriceUsd = null;

  final String contractAddress;
  final String chain;
  final String tokenSymbol;
  final double entryPriceUsd;
  final DateTime openedAt;

  /// The lowest price seen since this position was opened.
  /// Starts at entry price and only ever moves DOWN.
  double allTimeLowPriceUsd;

  /// True once the 800%-from-ATL sell has been executed.
  bool firstSellExecuted;

  /// The price at which the first sell was executed.
  double? firstSellPriceUsd;
}

class PositionMonitor {
  // Singleton.
  static final PositionMonitor instance = PositionMonitor._();
  PositionMonitor._();

  final DexScreenerService _dex = DexScreenerService();

  // Map from contractAddress → PositionState
  final Map<String, PositionState> _positions = {};

  // ── CONSTANTS (trader's numbers) ──────────────────────────────────────────

  /// First sell trigger: price must reach this multiple of ATL.
  /// 9x = 800% gain from ATL (9x − 1 = 8 = 800%).
  static const double _firstSellMultiplier = 9.0;

  /// Rebuy trigger: price must fall this % below first-sell price.
  /// 80% drop = price at 20% of peak = 0.20 × peak.
  static const double _rebuyRetracePercent = 80.0;

  // ── POSITION MANAGEMENT ───────────────────────────────────────────────────

  /// Register a new position after a buy is executed.
  void openPosition({
    required String contractAddress,
    required String chain,
    required String tokenSymbol,
    required double entryPriceUsd,
  }) {
    _positions[contractAddress.toLowerCase()] = PositionState(
      contractAddress: contractAddress,
      chain: chain,
      tokenSymbol: tokenSymbol,
      entryPriceUsd: entryPriceUsd,
      openedAt: DateTime.now().toUtc(),
    );
    Log.info(
      '📈 [PositionMonitor] Opened position: $tokenSymbol @ \$${entryPriceUsd.toStringAsFixed(8)}',
    );
  }

  /// Remove a position after it's fully closed.
  void closePosition(String contractAddress) {
    final pos = _positions.remove(contractAddress.toLowerCase());
    if (pos != null) {
      Log.info(
        '📉 [PositionMonitor] Closed position: ${pos.tokenSymbol}',
      );
    }
  }

  /// Mark the first sell as executed and record the price.
  void recordFirstSell(String contractAddress, double sellPriceUsd) {
    final pos = _positions[contractAddress.toLowerCase()];
    if (pos == null) return;
    pos.firstSellExecuted = true;
    pos.firstSellPriceUsd = sellPriceUsd;
    Log.info(
      '💰 [PositionMonitor] First sell executed for ${pos.tokenSymbol} '
      '@ \$${sellPriceUsd.toStringAsFixed(8)}',
    );
  }

  // ── MAIN CHECK LOOP ───────────────────────────────────────────────────────

  /// Check ALL open positions for sell/rebuy triggers.
  /// Call this periodically (e.g. every 5-15 minutes from the scanner loop).
  Future<List<PositionCheckResult>> checkAllPositions() async {
    if (_positions.isEmpty) return const [];

    Log.info(
      '🔍 [PositionMonitor] Checking ${_positions.length} open position(s)...',
    );

    final results = <PositionCheckResult>[];
    for (final pos in _positions.values) {
      try {
        final result = await _checkPosition(pos);
        if (result != null) results.add(result);
      } catch (e) {
        Log.warning(
          '⚠️ [PositionMonitor] Error checking ${pos.tokenSymbol}: $e',
        );
      }
    }

    return results;
  }

  /// Check a single position. Returns null if the action is HOLD
  /// (nothing to report) — only returns a result when action is needed.
  Future<PositionCheckResult?> _checkPosition(PositionState pos) async {
    // Fetch current price from DexScreener.
    final pairs = await _dex.getTokenData(
      contractAddress: pos.contractAddress,
      chain: pos.chain,
    );

    if (pairs.isEmpty) {
      Log.warning(
        '⚠️ [PositionMonitor] No DexScreener data for ${pos.tokenSymbol} — skipping',
      );
      return null;
    }

    final currentPrice = DexScreenerService.parsePriceUsd(pairs.first);
    if (currentPrice == null || currentPrice <= 0) return null;

    // ── Update ATL if price has dropped ─────────────────────────────────
    if (currentPrice < pos.allTimeLowPriceUsd) {
      Log.info(
        '📉 [PositionMonitor] ${pos.tokenSymbol} new ATL: '
        '\$${currentPrice.toStringAsFixed(8)} '
        '(was \$${pos.allTimeLowPriceUsd.toStringAsFixed(8)})',
      );
      pos.allTimeLowPriceUsd = currentPrice;
    }

    final gainFromAtl = ((currentPrice / pos.allTimeLowPriceUsd) - 1) * 100;

    // ── CASE A: First sell not yet executed — watch for +800% from ATL ──
    if (!pos.firstSellExecuted) {
      final targetPrice = pos.allTimeLowPriceUsd * _firstSellMultiplier;

      Log.info(
        '📊 [PositionMonitor] ${pos.tokenSymbol}: '
        '\$${currentPrice.toStringAsFixed(8)} | '
        'ATL: \$${pos.allTimeLowPriceUsd.toStringAsFixed(8)} | '
        'Target (800%): \$${targetPrice.toStringAsFixed(8)} | '
        'Gain: +${gainFromAtl.toStringAsFixed(1)}%',
      );

      if (currentPrice >= targetPrice) {
        Log.success(
          '🎯 [PositionMonitor] FIRST SELL TRIGGER for ${pos.tokenSymbol}! '
          '+${gainFromAtl.toStringAsFixed(0)}% from ATL',
        );
        return PositionCheckResult(
          contractAddress: pos.contractAddress,
          chain: pos.chain,
          tokenSymbol: pos.tokenSymbol,
          action: PositionAction.firstSell,
          currentPriceUsd: currentPrice,
          currentAtlUsd: pos.allTimeLowPriceUsd,
          gainFromAtlPercent: gainFromAtl,
          firstSellPriceUsd: currentPrice,
          reason:
              '${pos.tokenSymbol} is up ${gainFromAtl.toStringAsFixed(0)}% '
              'from its all-time low of \$${pos.allTimeLowPriceUsd.toStringAsFixed(8)}. '
              'Trader rule: first sell at +800% from ATL.',
        );
      }

      return null; // HOLD
    }

    // ── CASE B: First sell executed — watch for 80% retrace for rebuy ───
    final peakPrice = pos.firstSellPriceUsd!;
    final rebuyTarget = peakPrice * (1 - (_rebuyRetracePercent / 100));
    final retraceFromPeak = ((peakPrice - currentPrice) / peakPrice) * 100;

    Log.info(
      '📊 [PositionMonitor] ${pos.tokenSymbol} (post-sell): '
      '\$${currentPrice.toStringAsFixed(8)} | '
      'Sold at: \$${peakPrice.toStringAsFixed(8)} | '
      'Rebuy target: \$${rebuyTarget.toStringAsFixed(8)} | '
      'Retrace: ${retraceFromPeak.toStringAsFixed(1)}%',
    );

    if (currentPrice <= rebuyTarget) {
      Log.success(
        '🔄 [PositionMonitor] REBUY TRIGGER for ${pos.tokenSymbol}! '
        '${retraceFromPeak.toStringAsFixed(0)}% retrace from peak',
      );
      return PositionCheckResult(
        contractAddress: pos.contractAddress,
        chain: pos.chain,
        tokenSymbol: pos.tokenSymbol,
        action: PositionAction.rebuy,
        currentPriceUsd: currentPrice,
        currentAtlUsd: pos.allTimeLowPriceUsd,
        gainFromAtlPercent: gainFromAtl,
        firstSellPriceUsd: peakPrice,
        retraceFromPeakPercent: retraceFromPeak,
        reason:
            '${pos.tokenSymbol} has retraced ${retraceFromPeak.toStringAsFixed(0)}% '
            'from the first-sell price of \$${peakPrice.toStringAsFixed(8)}. '
            'Trader rule: rebuy after 80% retrace from peak.',
      );
    }

    return null; // HOLD — waiting for rebuy entry
  }

  // ── STATUS ────────────────────────────────────────────────────────────────

  int get openPositionCount => _positions.length;

  List<PositionState> get allPositions => _positions.values.toList();

  String positionSummary(String contractAddress) {
    final pos = _positions[contractAddress.toLowerCase()];
    if (pos == null) return 'Not tracked';

    if (!pos.firstSellExecuted) {
      final targetPrice = pos.allTimeLowPriceUsd * _firstSellMultiplier;
      return 'Entry: \$${pos.entryPriceUsd.toStringAsFixed(8)} | '
          'ATL: \$${pos.allTimeLowPriceUsd.toStringAsFixed(8)} | '
          'First sell target: \$${targetPrice.toStringAsFixed(8)} (+800% from ATL)';
    }

    final rebuyTarget =
        pos.firstSellPriceUsd! * (1 - (_rebuyRetracePercent / 100));
    return 'First sell executed @ \$${pos.firstSellPriceUsd!.toStringAsFixed(8)} | '
        'Watching for rebuy at \$${rebuyTarget.toStringAsFixed(8)} (-80% from peak)';
  }
}
