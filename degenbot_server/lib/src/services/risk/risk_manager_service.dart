// risk_manager_service.dart
//
// THE GATE. Every trade the bot wants to make passes through here FIRST.
// If this service says no, nothing gets bought — no matter how clean
// the rule engine's verdict was.
//
// PLAIN ENGLISH — WHAT THIS CHECKS, IN ORDER:
//   1. Is the bot even active for this user?
//   2. Has the user hit their daily trade limit already?
//   3. Is the macro context blocking buys? (BTC dumping hard)
//   4. Does the wallet have enough balance to trade at all?
//   5. What's the MAXIMUM this specific trade is allowed to be,
//      based on the user's risk percentage setting?
//   6. Set the backstop stop-loss price (catastrophic floor only —
//      the PRIMARY exit is the ATL-based 800% sell via PositionMonitor).
//
// HOW THE SELL STRATEGY WORKS NOW:
//   The old design set a fixed take-profit % above entry.
//   The trader's actual strategy tracks the All-Time Low (ATL) after
//   buying and sells at +800% FROM ATL — not from entry. This is handled
//   live by PositionMonitor, not here.
//
//   What we set here: a backstop stop-loss as a catastrophic floor
//   (e.g. -70% from entry). The ATL strategy handles the normal case;
//   the stop-loss handles total collapse. NO fixed take-profit is set
//   because the 800%/ATL exit is dynamic.
//
// DAILY RESET:
//   trades_today resets to 0 once per UTC day. We check-and-reset lazily
//   (on the first risk check of a new day) rather than running a separate
//   cron job — simpler, and a Dart Docker container doesn't need a
//   scheduler just for this one counter.

import 'package:logging/logging.dart';
import 'package:degenbot_server/src/generated/protocol.dart';
import 'package:degenbot_server/src/services/repository/trade_repository.dart';
import 'package:degenbot_server/src/services/repository/user_repository.dart';
import 'package:degenbot_server/src/services/trading/macro_context_service.dart';
import 'risk_decision.dart';

final _log = Logger('RiskManagerService');

class RiskManagerService {
  final TradeRepository _trades;
  final UserRepository _users;

  const RiskManagerService({
    TradeRepository? tradeRepository,
    UserRepository? userRepository,
  })  : _trades = tradeRepository ?? const TradeRepository(),
        _users = userRepository ?? const UserRepository();

  // ── MAIN ENTRY POINT ──────────────────────────────────────────────────────

  /// Evaluate whether a proposed trade is allowed, and if so, exactly how
  /// much to spend and what backstop stop-loss to set.
  ///
  /// [walletBalanceNative] — current wallet balance in the chain's native
  /// currency (SOL/ETH/BNB). The CALLER fetches this from the chain
  /// (Step 4 — wallet service) before calling here. The risk manager
  /// never touches the blockchain itself; it only does math and policy
  /// enforcement on numbers it's given.
  ///
  /// [nativePriceUsd] — price of SOL/ETH/BNB itself, in USD.
  /// [tokenPriceUsd] — price of the token being considered, in USD.
  ///
  /// NOTE: No take-profit price is set here. The primary exit strategy
  /// (+800% from ATL) is managed dynamically by PositionMonitor.
  /// This service only sets the catastrophic stop-loss floor.
  Future<RiskDecision> evaluateTrade({
    required int telegramId,
    required double walletBalanceNative,
    required double nativePriceUsd,
    required double tokenPriceUsd,
  }) async {
    final user = await _users.findByTelegramId(telegramId);
    if (user == null) {
      return RiskDecision.rejected('User not found.');
    }

    // ── CHECK 1: Is the bot active? ────────────────────────────────────────
    if (!user.isBotActive) {
      return RiskDecision.rejected(
        'Bot is not active for this user. Use /activate first.',
      );
    }

    if (user.walletAddress == null || user.walletAddress!.isEmpty) {
      return RiskDecision.rejected('No wallet address set. Use /wallet first.');
    }

    // ── CHECK 2: Daily trade limit ─────────────────────────────────────────
    final profile = await _getProfileWithDailyReset(user.id!);

    // ── CHECK 2b: Macro context — is BTC dumping? ──────────────────────────
    // The trader's rule: don't buy degen tokens when BTC is in freefall.
    // MacroContextService tracks this live and can be paused by the analyst.
    final macroPauseReason = MacroContextService.instance.shouldHoldBuying();
    if (macroPauseReason != null) {
      return RiskDecision.rejected(
        'Macro pause: $macroPauseReason\n'
        'Use /macro status to see current conditions, '
        'or /macro bull to override if you\'re confident.',
      );
    }

    if (profile.tradesToday >= profile.dailyTradeLimit) {
      return RiskDecision.rejected(
        'Daily trade limit reached (${profile.tradesToday}/${profile.dailyTradeLimit}). '
        'Resets at UTC midnight, or raise the limit with /risk.',
      );
    }

    // ── CHECK 3: Sufficient balance ─────────────────────────────────────────
    // Reserve a small buffer for gas/network fees — never spend 100% of
    // the wallet on the trade itself. This flat reserve is a conservative
    // placeholder; Step 4 will replace it with real per-chain fee estimation.
    const gasReserveNative = 0.01;

    final spendableNative = walletBalanceNative - gasReserveNative;
    if (spendableNative <= 0) {
      return RiskDecision.rejected(
        'Wallet balance too low to trade after reserving gas '
        '(balance: ${walletBalanceNative.toStringAsFixed(4)}).',
      );
    }

    // ── CHECK 4: Calculate the approved trade size ──────────────────────────
    // The CORE risk calculation: never risk more than maxTradePercent of
    // the wallet on a single trade, regardless of how confident the AI was.
    final maxTradeNative = spendableNative * (profile.maxTradePercent / 100.0);

    if (maxTradeNative <= 0) {
      return RiskDecision.rejected(
        'Calculated trade size is zero or negative — check risk settings.',
      );
    }

    final approvedAmountUsd = maxTradeNative * nativePriceUsd;

    // Sanity floor: don't bother executing trades so small that gas fees
    // would eat the position. $1 is a reasonable floor for degen plays;
    // adjust per chain once real fee data is wired in (Step 4).
    const minimumTradeUsd = 1.0;
    if (approvedAmountUsd < minimumTradeUsd) {
      return RiskDecision.rejected(
        'Approved trade size (\$${approvedAmountUsd.toStringAsFixed(2)}) is below '
        'the \$$minimumTradeUsd minimum — not worth the gas cost.',
      );
    }

    // ── CHECK 5: Set the backstop stop-loss ─────────────────────────────────
    // The PRIMARY exit is +800% from ATL, managed by PositionMonitor.
    // This stop-loss is a CATASTROPHIC FLOOR only — it triggers if the
    // token collapses completely before we ever get an ATL-based sell.
    // Default: -70% from entry (degen tokens are volatile — we give them room).
    // User can adjust via /risk stoploss <percent>.
    final stopLossPrice =
        tokenPriceUsd * (1 - profile.defaultStopLossPercent / 100.0);

    // NO take-profit price set here — that's handled by PositionMonitor
    // at +800% from ATL. Setting a fixed TP here would conflict with the
    // ATL strategy and could close trades too early.

    _log.info(
      'Trade APPROVED for telegramId=$telegramId: '
      '${maxTradeNative.toStringAsFixed(4)} native (\$${approvedAmountUsd.toStringAsFixed(2)}) | '
      'Backstop SL=\$${stopLossPrice.toStringAsFixed(8)} | '
      'Primary exit: +800% from ATL via PositionMonitor',
    );

    // Caution warning doesn't block the trade but should be shown to the user.
    final cautionWarning = MacroContextService.instance.cautionWarning();

    return RiskDecision(
      approved: true,
      reason: '${cautionWarning != null ? "$cautionWarning\n" : ""}'
          'Trade approved: ${profile.maxTradePercent.toStringAsFixed(0)}% '
          'of available balance (${profile.tradesToday + 1}/${profile.dailyTradeLimit} '
          'trades today). '
          'Exit strategy: +800% from ATL → first sell, then watch for -80% rebuy.',
      approvedAmountNative: maxTradeNative,
      approvedAmountUsd: approvedAmountUsd,
      takeProfitPriceUsd: null, // Set dynamically by PositionMonitor
      stopLossPriceUsd: stopLossPrice, // Backstop floor only
    );
  }

  // ── POST-TRADE BOOKKEEPING ───────────────────────────────────────────────

  /// Call this immediately AFTER a trade is successfully executed —
  /// increments the daily counter so the next evaluateTrade() call sees
  /// the updated count. Kept separate from evaluateTrade() so a trade
  /// that's approved-but-fails-to-execute (e.g. network error) doesn't
  /// count against the daily limit.
  Future<void> recordTradeExecuted(int userId) async {
    final profile = await _trades.getRiskProfile(userId);
    final updated = profile.copyWith(tradesToday: profile.tradesToday + 1);
    await _trades.updateRiskProfile(updated);
    _log.info(
      'Recorded trade for userId=$userId — '
      '${updated.tradesToday}/${updated.dailyTradeLimit} today',
    );
  }

  // ── DAILY RESET (lazy) ────────────────────────────────────────────────────

  Future<RiskProfile> _getProfileWithDailyReset(int userId) async {
    final profile = await _trades.getRiskProfile(userId);

    final now = DateTime.now().toUtc();
    final lastReset = profile.lastResetDate.toUtc();
    final isNewDay = now.year != lastReset.year ||
        now.month != lastReset.month ||
        now.day != lastReset.day;

    if (isNewDay) {
      _log.info('New UTC day detected for userId=$userId — resetting trade counter');
      final reset = profile.copyWith(tradesToday: 0, lastResetDate: now);
      return _trades.updateRiskProfile(reset);
    }

    return profile;
  }
}
