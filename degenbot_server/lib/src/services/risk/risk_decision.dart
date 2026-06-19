// risk_decision.dart
//
// The output of the Risk Manager — a single yes/no gate that EVERY
// trade must pass through before the bot is allowed to spend money.
//
// PLAIN ENGLISH:
//   Think of the risk manager as a strict accountant standing between
//   the AI's "I want to buy this" and the wallet's "okay, sending funds."
//   The accountant doesn't care how exciting the AI's reasoning is —
//   they only care about the numbers: have we hit today's trade limit?
//   Is this trade size within the allowed percentage of the wallet?
//
//   This is the piece that turns "smart bot" into "smart AND safe bot."
//   An AI can be 100% confident about a coin and still get rejected here
//   if the user has already hit their daily trade limit.

class RiskDecision {
  const RiskDecision({
    required this.approved,
    required this.reason,
    this.approvedAmountNative,
    this.approvedAmountUsd,
    this.takeProfitPriceUsd,
    this.stopLossPriceUsd,
  });

  /// True = the trade may proceed. False = blocked.
  final bool approved;

  /// Human-readable reason — shown to the user either way, so they
  /// understand WHY a trade did or didn't happen.
  final String reason;

  /// If approved, the exact amount (in the chain's native currency,
  /// e.g. SOL/ETH/BNB) the risk manager has cleared for this trade.
  /// This is calculated from the user's max_trade_percent setting,
  /// NOT just copied from what the AI suggested.
  final double? approvedAmountNative;

  /// Same amount, expressed in USD for display purposes.
  final double? approvedAmountUsd;

  /// The take-profit price the risk manager has set for this trade,
  /// based on the user's risk profile and the token's entry price.
  final double? takeProfitPriceUsd;

  /// The stop-loss price, same logic.
  final double? stopLossPriceUsd;

  factory RiskDecision.rejected(String reason) =>
      RiskDecision(approved: false, reason: reason);

  @override
  String toString() => approved
      ? 'APPROVED: $reason (${approvedAmountNative?.toStringAsFixed(4)} native, '
          'TP \$${takeProfitPriceUsd?.toStringAsFixed(8)}, '
          'SL \$${stopLossPriceUsd?.toStringAsFixed(8)})'
      : 'REJECTED: $reason';
}
