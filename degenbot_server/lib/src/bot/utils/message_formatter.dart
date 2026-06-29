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
import 'package:degenbot_server/src/services/intelligence/token_intelligence_report.dart';
import 'package:degenbot_server/src/services/trading/position_monitor.dart';

import '../../services/messaging/messaging_result.dart';

class MessageFormatter {
  MessageFormatter._(); // static-only class

  // ADD to message_formatter.dart:

  /// Builds the button row for a token report — adapts to what's actually
  /// known. A confirmed honeypot never gets a Buy button. Chart/Holders
  /// only appear if we have a real pair/contract address to link to.
  static List<MessageButton> tokenAnalysisButtons(TokenIntelligenceReport report) {
    final buttons = <MessageButton>[];
    final isHoneypot = report.honeypot?.isHoneypot ?? report.safety?.isHoneypot ?? false;
    final pairAddr = report.market?.pairAddress;

    if (pairAddr != null && pairAddr.isNotEmpty) {
      final dexScreenerChain = report.chain == 'bnb' ? 'bsc' : report.chain;
      buttons.add(MessageButton(
        id: 'chart',
        text: '📊 Chart',
        url: 'https://dexscreener.com/$dexScreenerChain/$pairAddr',
      ));
    }

    buttons.add(MessageButton(
      id: 'holders',
      text: '👥 Holders',
      callbackData: 'token_holders:${report.contractAddress}:${report.chain}',
    ));

    if (!isHoneypot && report.verdict != TokenVerdict.reject) {
      buttons.add(MessageButton(
        id: 'buy',
        text: '🛒 Buy',
        callbackData: 'token_buy:${report.contractAddress}:${report.chain}',
      ));
    }

    buttons.add(MessageButton(
      id: 'refresh',
      text: '🔄 Refresh',
      callbackData: 'token_refresh:${report.contractAddress}:${report.chain}',
    ));

    return buttons;
  }

  // ── TOKEN ANALYSIS REPORT — dense, scannable, crypto-native formatting ──
 // ── TOKEN ANALYSIS REPORT — dense, scannable, crypto-native formatting ──
  static String tokenAnalysisReport(TokenIntelligenceReport report) {
    final verdictTag = switch (report.verdict) {
      TokenVerdict.buy => '🟢 BUY',
      TokenVerdict.watch => '🟡 WATCH',
      TokenVerdict.reject => '🔴 REJECT',
      TokenVerdict.error => '❌ ERROR',
    };

    final name = _esc(report.tokenName);
    final symbol = _esc(report.tokenSymbol);
    final chainLabel = report.chain.toUpperCase();

    final buffer = StringBuffer();

    final isHoneypot = report.honeypot?.isHoneypot ?? report.safety?.isHoneypot ?? false;
    final honeypotTag = isHoneypot ? '🍯 HONEYPOT' : '✅ No HoneyPot';
    buffer.writeln('📌 *$name ($symbol)* | $honeypotTag');

    final hasSuspicious = (report.safety?.hasMintFunction ?? false) ||
        (report.safety?.hasProxyContract ?? false) ||
        (report.honeypot?.isProxy ?? false);
    buffer.writeln(hasSuspicious
        ? '⚠️ *Suspicious functions found:* ${_suspiciousFunctionsList(report)}'
        : '✅ No suspicious functions detected');
    buffer.writeln();

    if (report.ownership?.creatorAddress != null) {
      buffer.writeln('👨‍💻 Deployer: `${_shortAddr(report.ownership!.creatorAddress!)}`');
    }
    buffer.writeln('🔸 Chain: $chainLabel | ⚖️ Age: ${_ageLabel(report.market?.tokenAgeHours ?? 0)}');
    buffer.writeln();

    if (report.market != null) {
      final m = report.market!;
      final liqPct = (m.liquidityUsd > 0 && m.marketCapUsd != null && m.marketCapUsd! > 0)
          ? ' (${((m.liquidityUsd / m.marketCapUsd!) * 100).toStringAsFixed(0)}%)'
          : '';
      buffer.writeln('💰 MC: ${_fmtUsd(m.marketCapUsd)} | Liq: ${_fmtUsd(m.liquidityUsd)}$liqPct');

      if (report.ownership != null) {
        final locked = report.ownership!.isLiquidityLocked;
        final platform = report.ownership!.liquidityLockPlatform;
        buffer.writeln(locked
            ? '🔒 LP Lock: Locked${platform != null ? ' ($platform)' : ''}'
            : '🔓 LP Lock: ⚠️ NOT locked');
      }

      final buyTax = report.honeypot?.buyTaxPercent ?? report.safety?.buyTaxPercent ?? 0;
      final sellTax = report.honeypot?.sellTaxPercent ?? report.safety?.sellTaxPercent ?? 0;
      final transferTax = report.honeypot?.transferTaxPercent ?? 0;
      buffer.writeln('💳 Tax: B: ${buyTax.toStringAsFixed(0)}% | S: ${sellTax.toStringAsFixed(0)}% | T: ${transferTax.toStringAsFixed(0)}%');

      buffer.writeln('📉 24h: ${_signed(m.priceChange24h)}% | V: ${_fmtUsd(m.volumeUsd24h)} | B:${_fmtCompact(m.buyCount24h)} S:${_fmtCompact(m.sellCount24h)}');
      buffer.writeln();

      buffer.writeln('💲 Price: \$${m.priceUsd.toStringAsFixed(m.priceUsd < 0.01 ? 8 : 4)}');
      buffer.writeln();
    }

    final holders = report.market?.holderCount ?? report.honeypot?.totalHolders;
    if (holders != null || report.ownership != null) {
      if (holders != null) {
        buffer.writeln('👩‍👧‍👦 Holders: ${_fmtCompact(holders)}'
            '${report.ownership != null ? ' | Top10: ${report.ownership!.top10HoldersPercent.toStringAsFixed(1)}%' : ''}');
      }
      if (report.ownership != null) {
        final o = report.ownership!;
        buffer.writeln(o.isOwnershipRenounced ? '👤 Owner: RENOUNCED ✅' : '👤 Owner: Deployer ⚠️');
        if (o.deployerHoldingPercent > 0) {
          buffer.writeln('💼 Deployer holds: ${o.deployerHoldingPercent.toStringAsFixed(2)}% of supply');
        }
      }
      buffer.writeln();
    }

    final insiderFlags = report.flags.where((f) =>
        f.source == 'RugCheck' && f.message.toLowerCase().contains('insider')).toList();
    if (insiderFlags.isNotEmpty || (report.onChain?.isWashTrading ?? false)) {
      buffer.writeln('🕸️ *Wallet Clustering*');
      for (final f in insiderFlags) {
        buffer.writeln('   ${_severityIcon(f.severity)} ${_esc(f.message)}');
      }
      if (report.onChain?.isWashTrading ?? false) {
        buffer.writeln('   🔴 Wash trading pattern detected on-chain');
      }
      buffer.writeln();
    }

    if (report.sentiment != null) {
      final s = report.sentiment!;
      buffer.writeln('📣 Sentiment: ${s.sentimentLabel} | KOL mentions (24h): ${s.kolMentionCount}'
          '${s.isOrganicGrowth ? '' : ' ⚠️ possibly inorganic'}');
      buffer.writeln();
    }

    // Rule-based verdict — no AI score. The trader's rules made this call.
    buffer.writeln('🏆 *Verdict:* $verdictTag');
    if (report.aiReasoning.isNotEmpty) {
      buffer.writeln('📋 _${_esc(report.aiReasoning)}_');
    }

    final remainingFlags = report.flags.where((f) =>
        !(f.source == 'RugCheck' && f.message.toLowerCase().contains('insider'))).toList();
    if (remainingFlags.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('🚩 *Flags (${remainingFlags.length})*');
      for (final f in remainingFlags.take(8)) {
        buffer.writeln('${_severityIcon(f.severity)} [${_esc(f.source)}] ${_esc(f.message)}');
      }
      if (remainingFlags.length > 8) {
        buffer.writeln('   _...and ${remainingFlags.length - 8} more_');
      }
    }

    buffer.writeln();
    buffer.write('📌 `${report.contractAddress}`');

    return buffer.toString();
  }
  // ── HELPERS specific to the report formatter ────────────────────────────

   // ── SAFETY: escape Telegram MarkdownV1 special chars in untrusted
  // strings (token names/symbols come straight from a smart contract —
  // a single unescaped * or _ breaks the ENTIRE message, not just that line). ──
  static String _esc(String? s) {
    if (s == null || s.isEmpty) return '?';
    return s.replaceAllMapped(
      RegExp(r'[_*`\[]'),
      (m) => '\\${m[0]}',
    );
  }

  static String _fmtUsd(double? v, {int decimals = 2}) {
    if (v == null) return 'N/A';
    if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) return '\$${(v / 1e3).toStringAsFixed(1)}K';
    return '\$${v.toStringAsFixed(decimals)}';
  }

  static String _fmtCompact(num? v) {
    if (v == null) return 'N/A';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  static String _shortAddr(String addr) {
    if (addr.length <= 10) return addr;
    return '${addr.substring(0, 4)}...${addr.substring(addr.length - 4)}';
  }

  static String _ageLabel(double hours) {
    if (hours < 1) return '${(hours * 60).toStringAsFixed(0)}m';
    if (hours < 24) return '${hours.toStringAsFixed(0)}h';
    return '${(hours / 24).toStringAsFixed(0)}d';
  }

  static String _severityIcon(FlagSeverity s) => switch (s) {
        FlagSeverity.critical => '🔴',
        FlagSeverity.high => '🟠',
        FlagSeverity.medium => '🟡',
        FlagSeverity.low => '🔵',
      };

  static String _signed(double? v) {
    if (v == null) return '?';
    return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';
  }

  static String _suspiciousFunctionsList(TokenIntelligenceReport r) {
    final items = <String>[];
    if (r.safety?.hasMintFunction ?? false) items.add('MINTABLE');
    if (r.safety?.hasProxyContract ?? false) items.add('PROXY');
    if (r.honeypot?.isProxy ?? false) items.add('PROXY_CALLS');
    return items.join(', ');
  }

  // buySellRatio is buys/sells as a single double — these reconstruct
  // approximate counts for display only (not exact, ratio-derived).
  static int? _buysFromRatio(MarketData m) => null; // placeholder — see note below
  static int? _sellsFromRatio(MarketData m) => null; // placeholder — see note below
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

    // ATL state lives in PositionMonitor (in-memory). We read it from there
    // rather than from Trade fields — those fields only exist in the generated
    // model after running `serverpod generate` / `build_runner`.
    final monitor = PositionMonitor.instance;

    for (final trade in trades) {
      buffer.write('• *${trade.symbol}* (${trade.chain})\n');
      buffer.write('  Entry: \$${trade.buyPriceUsd.toStringAsFixed(8)}\n');
      buffer.write('  Spent: \$${trade.amountSpentUsd.toStringAsFixed(2)}\n');

      // Pull live ATL state from PositionMonitor
      final pos = monitor.allPositions
          .where((p) => p.contractAddress.toLowerCase() == trade.contractAddress.toLowerCase())
          .firstOrNull;

      if (pos != null && !pos.firstSellExecuted) {
        final target = pos.allTimeLowPriceUsd * 9.0; // +800% from ATL
        buffer.write('  ATL: \$${pos.allTimeLowPriceUsd.toStringAsFixed(8)}\n');
        buffer.write('  🎯 First sell target: \$${target.toStringAsFixed(8)} (+800% from ATL)\n');
      } else if (pos != null && pos.firstSellExecuted && pos.firstSellPriceUsd != null) {
        final rebuyTarget = pos.firstSellPriceUsd! * 0.20; // -80% from peak
        buffer.write('  ✅ First sell @ \$${pos.firstSellPriceUsd!.toStringAsFixed(8)}\n');
        buffer.write('  🔄 Rebuy target: \$${rebuyTarget.toStringAsFixed(8)} (-80% from sell)\n');
      } else {
        // PositionMonitor doesn't have this in memory (e.g. after server restart)
        buffer.write('  Backstop SL: \$${trade.stopLossPriceUsd?.toStringAsFixed(8) ?? "—"}\n');
        buffer.write('  _ATL tracking: not active — use /activate to resume_\n');
      }

      buffer.writeln();
    }

    buffer.writeln(
      '_Exit strategy: +800% from ATL → first sell, then -80% retrace → rebuy_',
    );

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

  // ── SCANNER BUY SIGNAL NOTIFICATION ───────────────────────────────────────
  // Sent proactively by AutoScannerService when the rule engine approves a
  // token. This is intentionally shorter than tokenAnalysisReport — it's a
  // push alert, not a full deep-dive. The user can tap "Full Report" to see
  // the complete analysis.
  static String buySignalNotification(TokenIntelligenceReport report) {
    final chainLabel = report.chain.toUpperCase();
    final name = _esc(report.tokenName);
    final symbol = _esc(report.tokenSymbol);
    final m = report.market;

    final buffer = StringBuffer();
    buffer.writeln('🚨 *SCANNER ALERT — $chainLabel*');
    buffer.writeln();
    buffer.writeln('📌 *$name ($symbol)*');
    buffer.writeln();

    if (m != null) {
      buffer.writeln(
        '💰 MCap: ${_fmtUsd(m.marketCapUsd)} | Liq: ${_fmtUsd(m.liquidityUsd)}',
      );
      buffer.writeln(
        '📉 24h: ${_signed(m.priceChange24h)}% | Vol: ${_fmtUsd(m.volumeUsd24h)}',
      );
      buffer.writeln(
        '⏰ Age: ${_ageLabel(m.tokenAgeHours)} | B:${_fmtCompact(m.buyCount24h)} S:${_fmtCompact(m.sellCount24h)}',
      );
      buffer.writeln();
    }

    if (report.aiReasoning.isNotEmpty) {
      // First 200 chars of reasoning — keep the push notification concise
      final preview = report.aiReasoning.length > 200
          ? '${report.aiReasoning.substring(0, 200)}...'
          : report.aiReasoning;
      buffer.writeln('🏆 _${_esc(preview)}_');
      buffer.writeln();
    }

    buffer.write('📌 `${report.contractAddress}`');

    return buffer.toString();
  }

  // ── TRADE NOTIFICATION ─────────────────────────────────────────────────────
  // Sent to user when the bot opens a trade.
  // ATL starts at entry — PositionMonitor updates it live as price moves down.
  // We do NOT read trade.allTimeLowPriceUsd here — that field only exists after
  // `serverpod generate` runs. Instead we derive the initial target from entry.
  static String tradeBoughtNotification(Trade trade, String ruleReasoning) {
    final entryPrice = trade.buyPriceUsd;
    final initialTarget = entryPrice * 9.0; // +800% from entry = worst-case first sell target

    return '''
🛒 *Trade Opened*

*Coin:*    ${trade.symbol} (${trade.chain})
*Spent:*   \$${trade.amountSpentUsd.toStringAsFixed(2)} (${trade.amountSpentNative.toStringAsFixed(4)} native)
*Entry:*   \$${entryPrice.toStringAsFixed(8)}
*ATL:*     = Entry (tracking starts now)
*🎯 First sell target:* \$${initialTarget.toStringAsFixed(8)} (+800% from ATL — improves as ATL drops)
*🛑 Backstop SL:*  \$${trade.stopLossPriceUsd?.toStringAsFixed(8) ?? "—"}
*Tx:*      `${_truncate(trade.buyTxHash ?? "pending", 12)}...`

📋 *Why the rules approved this:*
_${ruleReasoning}_

_After first sell, watching for -80% retrace → rebuy signal._
''';
  }

  // Sent to user when a sell is executed (first sell, rebuy, or close)
  static String tradeClosedNotification(Trade trade) {
    final pnl = trade.realizedPnlUsd ?? 0;
    final roi = trade.roiPercent ?? 0;
    final emoji = pnl >= 0 ? '🎉' : '😔';
    final reason = switch (trade.closeReason) {
      'first_sell_800'  => '🎯 +800% from ATL — first sell executed',
      'stop_loss'       => '🛑 Backstop stop-loss triggered',
      'manual'          => '🤚 Closed manually',
      'rebuy'           => '🔄 Rebuy executed after -80% retrace',
      _                 => 'Closed',
    };

    final nextStepNote = trade.closeReason == 'first_sell_800'
        ? '\n_Watching for -80% retrace from this sell price for rebuy..._'
        : '';

    return '''
$emoji *${trade.closeReason == 'rebuy' ? 'Rebuy Executed' : 'Trade Closed'} — $reason*

*Coin:*  ${trade.symbol}
*Entry:* \$${trade.buyPriceUsd.toStringAsFixed(8)}
*Exit:*  \$${trade.sellPriceUsd?.toStringAsFixed(8) ?? "—"}
*PnL:*   ${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}
*ROI:*   ${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(2)}%$nextStepNote
''';
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────
  static String _truncate(String s, int length) {
    return s.length <= length ? s : s.substring(0, length);
  }
}
