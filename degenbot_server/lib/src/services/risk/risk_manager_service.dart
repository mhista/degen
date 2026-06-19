// risk_manager_service.dart
//
// THE GATE. Every trade the bot wants to make passes through here FIRST.
// If this service says no, nothing gets bought — no matter how confident
// the AI's score was.
//
// PLAIN ENGLISH — WHAT THIS CHECKS, IN ORDER:
//   1. Is the bot even active for this user?
//   2. Has the user hit their daily trade limit already?
//   3. Does the wallet have enough balance to trade at all?
//   4. What's the MAXIMUM this specific trade is allowed to be,
//      based on the user's risk percentage setting?
//   5. Calculate the actual take-profit and stop-loss prices for
//      this specific token, based on its current price and the
//      user's percentage preferences.
//
// WHY THIS IS SEPARATE FROM THE AI SCORING ENGINE:
//   The AI answers "is this a good coin?" The risk manager answers
//   "even if it's a good coin, how much should we risk, and are we
//   even allowed to trade right now?" Mixing these two questions
//   together is how bots end up betting too much on a single
//   "obviously great" trade.
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
  /// much to spend and what TP/SL prices to set.
  ///
  /// [walletBalanceNative] — current wallet balance in the chain's native
  /// currency (SOL/ETH/BNB). The CALLER fetches this from the chain
  /// (Step 4 — wallet service) before calling here. The risk manager
  /// never touches the blockchain itself; it only does math and policy
  /// enforcement on numbers it's given.
  ///
  /// [nativePriceUsd] — price of SOL/ETH/BNB itself, in USD.
  /// [tokenPriceUsd] — price of the token being considered, in USD.
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

    // ── CHECK 5: Calculate TP/SL prices for THIS token ──────────────────────
    final takeProfitPrice =
        tokenPriceUsd * (1 + profile.defaultTakeProfitPercent / 100.0);
    final stopLossPrice =
        tokenPriceUsd * (1 - profile.defaultStopLossPercent / 100.0);

    _log.info(
      'Trade APPROVED for telegramId=$telegramId: '
      '${maxTradeNative.toStringAsFixed(4)} native (\$${approvedAmountUsd.toStringAsFixed(2)}), '
      'TP=\$${takeProfitPrice.toStringAsFixed(8)} SL=\$${stopLossPrice.toStringAsFixed(8)}',
    );

    return RiskDecision(
      approved: true,
      reason: 'Trade approved: ${profile.maxTradePercent.toStringAsFixed(0)}% '
          'of available balance (${profile.tradesToday + 1}/${profile.dailyTradeLimit} '
          'trades today).',
      approvedAmountNative: maxTradeNative,
      approvedAmountUsd: approvedAmountUsd,
      takeProfitPriceUsd: takeProfitPrice,
      stopLossPriceUsd: stopLossPrice,
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
