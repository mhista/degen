// message_formatter.dart
//
// All Telegram message templates live here.
//
// WHY CENTRALISE TEMPLATES:
//   Keeps formatting logic out of handlers (single responsibility).
//   When you add the Flutter app, you can reuse the same data
//   formatting logic — just without the Telegram markdown syntax.
//   Easy to update all messages from one file.

import 'package:degenbot_server/src/generated/protocol.dart';
import 'package:degenbot_server/src/services/repository/feature_flags_repository.dart';

class MessageFormatter {
  MessageFormatter._(); // static-only class

  // ── STATUS ─────────────────────────────────────────────────────────────────
  static String statusMessage({
    required User user,
    required int openTradeCount,
    required int tradesToday,
    required RiskProfile riskProfile,
  }) {
    final botStatus = user.isBotActive ? '🟢 Active' : '🔴 Inactive';
    final wallet = user.walletAddress != null
        ? '`${_truncate(user.walletAddress!, 8)}...${user.walletAddress!.substring(user.walletAddress!.length - 4)}`'
        : '⚠️ _Not set_';

    return '''
📊 *DegenBot Status*

*Bot:*          $botStatus
*Chain:*        ${user.activeChain.toUpperCase()}
*Wallet:*       $wallet
*Tier:*         ${user.subscriptionTier}

📈 *Today*
Open positions: $openTradeCount
Trades today:   $tradesToday / ${riskProfile.dailyTradeLimit}

⚙️ *Risk Settings*
Max per trade:  ${riskProfile.maxTradePercent.toStringAsFixed(0)}% of balance
Take profit:    +${riskProfile.defaultTakeProfitPercent.toStringAsFixed(0)}%
Stop loss:      -${riskProfile.defaultStopLossPercent.toStringAsFixed(0)}%

Use /help for all commands.
''';
  }

  // ── POSITIONS ──────────────────────────────────────────────────────────────
  static String positionsList(List<Trade> trades) {
    final buffer = StringBuffer('📂 *Open Positions (${trades.length})*\n\n');

    for (final trade in trades) {
      buffer.write(
        '• *${trade.symbol}* (${trade.chain})\n'
        '  Entry: \$${trade.buyPriceUsd.toStringAsFixed(6)}\n'
        '  Spent: \$${trade.amountSpentUsd.toStringAsFixed(2)}\n'
        '  TP: \$${trade.takeProfitPriceUsd?.toStringAsFixed(6) ?? "—"}  '
        'SL: \$${trade.stopLossPriceUsd?.toStringAsFixed(6) ?? "—"}\n\n',
      );
    }

    return buffer.toString();
  }

  // ── HISTORY ────────────────────────────────────────────────────────────────
  static String tradeHistory(List<Trade> trades) {
    final buffer = StringBuffer('📜 *Recent Trades*\n\n');

    for (final trade in trades) {
      final pnl = trade.realizedPnlUsd ?? 0;
      final roi = trade.roiPercent ?? 0;
      final emoji = pnl >= 0 ? '✅' : '❌';
      final closeReason = switch (trade.closeReason) {
        'take_profit' => '🎯 TP',
        'stop_loss'   => '🛑 SL',
        'manual'      => '🤚 Manual',
        _             => '—',
      };

      buffer.write(
        '$emoji *${trade.symbol}*  $closeReason\n'
        '   PnL: ${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)} '
        '(${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(1)}%)\n\n',
      );
    }

    return buffer.toString();
  }

  // ── STATS ──────────────────────────────────────────────────────────────────
  static String statsMessage(List<Trade> closed, List<Trade> open) {
    if (closed.isEmpty && open.isEmpty) {
      return '📊 No trades yet. Activate the bot to get started → /activate';
    }

    final wins = closed.where((t) => (t.realizedPnlUsd ?? 0) > 0).length;
    final totalPnl = closed.fold<double>(
      0,
      (sum, t) => sum + (t.realizedPnlUsd ?? 0),
    );
    final winRate = closed.isEmpty ? 0.0 : (wins / closed.length) * 100;
    final rois = closed.map((t) => t.roiPercent ?? 0).where((r) => r != 0);
    final bestRoi = rois.isEmpty ? 0.0 : rois.reduce((a, b) => a > b ? a : b);
    final worstRoi = rois.isEmpty ? 0.0 : rois.reduce((a, b) => a < b ? a : b);

    return '''
📊 *Performance Stats*

*Closed trades:*  ${closed.length}
*Win rate:*       ${winRate.toStringAsFixed(1)}%
*Total PnL:*      ${totalPnl >= 0 ? '+' : ''}\$${totalPnl.toStringAsFixed(2)}
*Best trade:*     +${bestRoi.toStringAsFixed(1)}%
*Worst trade:*    ${worstRoi.toStringAsFixed(1)}%
*Open now:*       ${open.length}
''';
  }

  // ── RISK PROFILE ───────────────────────────────────────────────────────────
  static String riskProfile(RiskProfile profile) {
    return '''
⚙️ *Risk Settings*

*Max per trade:*   ${profile.maxTradePercent.toStringAsFixed(0)}% of wallet
*Daily limit:*     ${profile.dailyTradeLimit} trades/day
*Trades today:*    ${profile.tradesToday}
*Take profit:*     +${profile.defaultTakeProfitPercent.toStringAsFixed(0)}%
*Stop loss:*       -${profile.defaultStopLossPercent.toStringAsFixed(0)}%

To change a setting, just tell me:
_"Set max trade to 3%"_
_"Set stop loss to 15%"_
_"Set daily limit to 5"_
''';
  }

  // ── FEATURE FLAGS ──────────────────────────────────────────────────────────
  static String featuresOverview(Map<String, bool> flags) {
    final buffer = StringBuffer(
      '🔌 *Data sources*\n\n'
      'Tap any source below to turn it on or off. Changes apply to the '
      '*next* token scan — no restart needed.\n\n',
    );

    for (final name in FeatureFlag.all) {
      final isOn = flags[name] ?? false;
      final emoji = isOn ? '🟢' : '⚪';
      final label = FeatureFlag.labels[name] ?? name;
      buffer.write('$emoji $label\n');
    }

    buffer.write(
      '\n💡 _Free sources (GoPlus, RugCheck, DexScreener, Etherscan/BscScan) '
      'can stay on permanently. Paid sources (TokenSniffer, ChainGPT) are '
      'off by default — switch them on only once you\'ve decided the cost is '
      'worth it._',
    );

    return buffer.toString();
  }

  // ── TRADE NOTIFICATION ─────────────────────────────────────────────────────
  // Sent to user when the bot opens a trade
  static String tradeBoughtNotification(Trade trade, String aiReasoning) {
    return '''
🛒 *Trade Opened*

*Coin:*    ${trade.symbol} (${trade.chain})
*Spent:*   \$${trade.amountSpentUsd.toStringAsFixed(2)} (${trade.amountSpentNative.toStringAsFixed(4)} native)
*Entry:*   \$${trade.buyPriceUsd.toStringAsFixed(8)}
*Target:*  \$${trade.takeProfitPriceUsd?.toStringAsFixed(8) ?? "—"} (+${trade.takeProfitPriceUsd != null ? (((trade.takeProfitPriceUsd! / trade.buyPriceUsd) - 1) * 100).toStringAsFixed(0) : "?"}%)
*Stop:*    \$${trade.stopLossPriceUsd?.toStringAsFixed(8) ?? "—"}
*Tx:*      `${_truncate(trade.buyTxHash ?? "pending", 12)}...`

🤖 *AI reasoning:*
_${aiReasoning}_
''';
  }

  // Sent to user when a trade closes
  static String tradeClosedNotification(Trade trade) {
    final pnl = trade.realizedPnlUsd ?? 0;
    final roi = trade.roiPercent ?? 0;
    final emoji = pnl >= 0 ? '🎉' : '😔';
    final reason = switch (trade.closeReason) {
      'take_profit' => '🎯 Take profit hit',
      'stop_loss'   => '🛑 Stop loss triggered',
      'manual'      => '🤚 Closed manually',
      _             => 'Closed',
    };

    return '''
$emoji *Trade Closed — $reason*

*Coin:*  ${trade.symbol}
*Entry:* \$${trade.buyPriceUsd.toStringAsFixed(8)}
*Exit:*  \$${trade.sellPriceUsd?.toStringAsFixed(8) ?? "—"}
*PnL:*   ${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}
*ROI:*   ${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(2)}%
''';
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────
  static String _truncate(String s, int length) {
    return s.length <= length ? s : s.substring(0, length);
  }
}
