// token_intelligence_report.dart
//
// The single unified output of the entire intelligence pipeline.
//
// When the AI scoring engine receives data from all five layers,
// it fills in this object. This is the ONLY thing the trading bot
// looks at before making a buy decision.
//
// PLAIN ENGLISH:
//   Imagine a detective's case file. Every piece of evidence from
//   every source gets filed here. The AI reads the full file and
//   writes its verdict at the bottom.

/// Overall verdict from the intelligence pipeline.
enum TokenVerdict {
  /// Strong buy signal — passes all checks, high AI score.
  buy,

  /// Passes checks but score too low to buy now — watch it.
  watch,

  /// Failed one or more hard checks — do not trade.
  reject,

  /// Pipeline error — could not complete analysis. Treat as reject.
  error,
}

/// Severity of a specific flag raised during analysis.
enum FlagSeverity {
  critical, // Instant reject (honeypot, blacklist, high sell tax)
  high,     // Strong warning (unlocked LP, whale concentration)
  medium,   // Caution (low liquidity, new deployer)
  low,      // FYI only (unverified contract source, no audit)
}

/// A single warning flag raised by any data source.
class IntelligenceFlag {
  const IntelligenceFlag({
    required this.source,
    required this.severity,
    required this.message,
  });

  /// Which data source raised this flag.
  final String source;

  final FlagSeverity severity;

  /// Human-readable description of the flag.
  final String message;

  bool get isCritical => severity == FlagSeverity.critical;

  @override
  String toString() => '[${severity.name.toUpperCase()}] $source: $message';
}

/// Layer 1 — Raw DexScreener market data.
class MarketData {
  const MarketData({
    required this.priceUsd,
    required this.liquidityUsd,
    required this.volumeUsd24h,
    required this.marketCapUsd,
    required this.holderCount,
    required this.tokenAgeHours,
    required this.priceChange1h,
    required this.priceChange6h,
    required this.priceChange24h,
    required this.buySellRatio,
    required this.pairAddress,
    required this.dexId,
     required this.buyCount24h,   // NEW
    required this.sellCount24h, 
  });

  final double priceUsd;
  final double liquidityUsd;
  final double volumeUsd24h;
  final double? marketCapUsd;
  final int? holderCount;

  /// How many hours since this token's first transaction on-chain.
  final double tokenAgeHours;

  final double? priceChange1h;
  final double? priceChange6h;
  final double? priceChange24h;

  /// Ratio of buy transactions to sell transactions (>1 = more buyers).
  final double buySellRatio;

  final String pairAddress;
  final String dexId;

    /// Raw 24h buy transaction count (not the ratio — the actual number).
  final int? buyCount24h;

  /// Raw 24h sell transaction count.
  final int? sellCount24h;

  @override
  toString() {
    return 'MarketData('
        'priceUsd: $priceUsd, '
        'liquidityUsd: $liquidityUsd, '
        'volumeUsd24h: $volumeUsd24h, '
        'marketCapUsd: $marketCapUsd, '
        'holderCount: $holderCount, '
        'tokenAgeHours: $tokenAgeHours, '
        'priceChange1h: $priceChange1h, '
        'priceChange6h: $priceChange6h, '
        'priceChange24h: $priceChange24h, '
        'buySellRatio: $buySellRatio, '
        'pairAddress: $pairAddress, '
        'dexId: $dexId, '
        'buyCount24h: $buyCount24h, '
        'sellCount24h: $sellCount24h'
        ')';
  }
}


/// Independent honeypot.is simulation result — separate from GoPlus's
/// SafetyData on purpose. When these two disagree, that disagreement
/// itself is meaningful and should be visible in the report rather than
/// silently merged into one "safety" verdict.
class HoneypotData {
  const HoneypotData({
    required this.isHoneypot,
    required this.riskLevel,
    required this.riskLabel,
    required this.simulationSuccess,
    required this.buyTaxPercent,
    required this.sellTaxPercent,
    required this.transferTaxPercent,
    required this.isOpenSource,
    required this.isProxy,
    required this.totalHolders,
    required this.tokenName,
    required this.tokenSymbol,
  });

  final bool isHoneypot;
  final int riskLevel;       // 0-3+ from honeypot.is's own summary
  final String riskLabel;    // 'low' | 'medium' | 'high' etc.
  final bool simulationSuccess;
  final double buyTaxPercent;
  final double sellTaxPercent;
  final double transferTaxPercent;
  final bool isOpenSource;
  final bool isProxy;
  final int? totalHolders;
  final String? tokenName;
  final String? tokenSymbol;


  @override
  String toString() {
    return 'HoneypotData('
        'isHoneypot: $isHoneypot, '
        'riskLevel: $riskLevel, '
        'riskLabel: $riskLabel, ' 
        'simulationSuccess: $simulationSuccess, '
        'buyTaxPercent: $buyTaxPercent, '
        'sellTaxPercent: $sellTaxPercent, '
        'transferTaxPercent: $transferTaxPercent, '
        'isOpenSource: $isOpenSource, '
        'isProxy: $isProxy, '
        'totalHolders: $totalHolders, '
        'tokenName: $tokenName, '
        'tokenSymbol: $tokenSymbol'
        ')';
  }
}

/// Layer 2 — Safety check results.
class SafetyData {
  const SafetyData({
    required this.isHoneypot,
    required this.isBlacklisted,
    required this.hasMintFunction,
    required this.hasProxyContract,
    required this.buyTaxPercent,
    required this.sellTaxPercent,
    required this.isContractVerified,
    required this.isClonedContract,
    required this.tokenSnifferScore,
    required this.rugCheckScore,
    required this.goplusFlags,
  });

  /// Cannot sell — instant reject.
  final bool isHoneypot;

  /// Address on known scam blacklist — instant reject.
  final bool isBlacklisted;

  /// Contract can create unlimited new tokens — high risk.
  final bool hasMintFunction;

  /// Upgradeable proxy (logic can be swapped post-launch) — high risk.
  final bool hasProxyContract;

  /// Buy tax percentage (>10% = suspicious, >30% = reject).
  final double buyTaxPercent;

  /// Sell tax percentage (>10% = suspicious, >30% = reject).
  final double sellTaxPercent;

  /// Source code verified on block explorer.
  final bool isContractVerified;

  /// Contract bytecode matches a known scam template.
  final bool isClonedContract;

  /// TokenSniffer score 0–100 (higher = safer).
  final int? tokenSnifferScore;

  /// RugCheck score 0–100 (lower = more risky for Solana).
  final int? rugCheckScore;

  /// Raw flags from GoPlus API (e.g. 'is_honeypot', 'can_take_back_ownership').
  final List<String> goplusFlags;

  @override
  String toString() {
    return 'SafetyData('
        'isHoneypot: $isHoneypot, '
        'isBlacklisted: $isBlacklisted, '
        'hasMintFunction: $hasMintFunction, '
        'hasProxyContract: $hasProxyContract, '
        'buyTaxPercent: $buyTaxPercent, '
        'sellTaxPercent: $sellTaxPercent, '
        'isContractVerified: $isContractVerified, '
        'isClonedContract: $isClonedContract, '
        'tokenSnifferScore: $tokenSnifferScore, '
        'rugCheckScore: $rugCheckScore, '
        'goplusFlags: $goplusFlags'
        ')';
  }

  bool get hasCriticalFlag =>
      isHoneypot || isBlacklisted || sellTaxPercent > 30 || isClonedContract;
}

/// Layer 3 — Liquidity lock and ownership data.
class OwnershipData {
  const OwnershipData({
    required this.isLiquidityLocked,
    required this.liquidityLockPlatform,
    required this.liquidityLockDaysRemaining,
    required this.isOwnershipRenounced,
    required this.top10HoldersPercent,
    required this.deployerHoldingPercent,
    required this.creatorAddress,
  });

  /// Is LP token locked in Unicrypt, Team.Finance, or PinkSale?
  final bool isLiquidityLocked;

  /// Which platform holds the lock (if any).
  final String? liquidityLockPlatform;

  /// Days until the lock expires (null if not locked).
  final double? liquidityLockDaysRemaining;

  /// Has the deployer renounced contract ownership?
  final bool isOwnershipRenounced;

  /// Percentage of total supply held by the top 10 wallets.
  final double top10HoldersPercent;

  /// Percentage of supply still held by the deployer wallet.
  final double deployerHoldingPercent;

  final String? creatorAddress;

  @override
  String toString() {
    return 'OwnershipData('
        'isLiquidityLocked: $isLiquidityLocked, '
        'liquidityLockPlatform: $liquidityLockPlatform, '
        'liquidityLockDaysRemaining: $liquidityLockDaysRemaining, '
        'isOwnershipRenounced: $isOwnershipRenounced, '
        'top10HoldersPercent: $top10HoldersPercent, '
        'deployerHoldingPercent: $deployerHoldingPercent, '
        'creatorAddress: $creatorAddress'
        ')';
  }
}

/// Layer 4 — Social/sentiment intelligence.
class SentimentData {
  const SentimentData({
    required this.mindshareScore,
    required this.sentimentLabel,
    required this.sentimentScore,
    required this.kolMentionCount,
    required this.isOrganicGrowth,
    required this.narrativeMatch,
    required this.socialLinks,
  });

  /// ChainGPT mindshare score (relative attention this token is getting).
  final double? mindshareScore;

  /// 'bullish' | 'bearish' | 'neutral'
  final String sentimentLabel;

  /// Sentiment score -1.0 to +1.0.
  final double sentimentScore;

  /// Number of KOL (influencer) mentions in last 24h.
  final int kolMentionCount;

  /// True if growth patterns look organic (not bot-pumped).
  final bool isOrganicGrowth;

  /// Whether the token fits a currently hot narrative (e.g. 'AI', 'RWA', 'meme').
  final String? narrativeMatch;

  /// Verified social links (Twitter, Telegram, website).
  final List<String> socialLinks;


  @override
  String toString() {
    return 'SentimentData('
        'mindshareScore: $mindshareScore, '
        'sentimentLabel: $sentimentLabel, '
        'sentimentScore: $sentimentScore, '
        'kolMentionCount: $kolMentionCount, '
        'isOrganicGrowth: $isOrganicGrowth, '
        'narrativeMatch: $narrativeMatch, '
        'socialLinks: $socialLinks' 
        ')';}

}

/// Layer 5 — On-chain forensics.
class OnChainData {
  const OnChainData({
    required this.walletClusterCount,
    required this.suspiciousClusterCount,
    required this.deployerFundingSource,
    required this.isWashTrading,
    required this.uniqueBuyersCount,
    required this.avgTransactionSizeUsd,
  });

  /// Number of distinct wallet clusters (BubbleMaps analysis).
  final int walletClusterCount;

  /// Clusters flagged as suspicious (same funding source, coordinated buys).
  final int suspiciousClusterCount;

  /// Where did the deployer's funding come from? (e.g. 'Binance', 'Tornado Cash')
  final String? deployerFundingSource;

  /// Does buy/sell pattern suggest wash trading?
  final bool isWashTrading;

  /// Unique buyer count from on-chain data.
  final int? uniqueBuyersCount;

  /// Average transaction size in USD (very small = bot activity).
  final double? avgTransactionSizeUsd;

  @override
  String toString() {
    return 'OnChainData('
        'walletClusterCount: $walletClusterCount, '
        'suspiciousClusterCount: $suspiciousClusterCount, '
        'deployerFundingSource: $deployerFundingSource, '
        'isWashTrading: $isWashTrading, '
        'uniqueBuyersCount: $uniqueBuyersCount, '
        'avgTransactionSizeUsd: $avgTransactionSizeUsd'
        ')';}
}

/// The complete intelligence report — output of the full pipeline.
class TokenIntelligenceReport {
  const TokenIntelligenceReport({
    required this.chain,
    required this.contractAddress,
    required this.tokenName,
    required this.tokenSymbol,
    required this.analysisTimestamp,
    required this.verdict,
    required this.aiScore,
    required this.aiReasoning,
    required this.flags,
    this.market,
    this.safety,
    this.ownership,
    this.sentiment,
    this.onChain,
    this.honeypot
  });

  final String chain;
  final String contractAddress;
  final String tokenName;
  final String tokenSymbol;
  final DateTime analysisTimestamp;

  // ── Verdict ───────────────────────────────────────────────────────────────
  final TokenVerdict verdict;

  /// AI composite score 0–100.
  final int aiScore;

  /// Natural language explanation the user can read (and ask the bot about).
  final String aiReasoning;

  /// All flags raised across all layers, sorted by severity.
  final List<IntelligenceFlag> flags;

  // ── Per-layer data (nullable — a layer may fail without killing the pipeline)
  final MarketData? market;
  final SafetyData? safety;
  final OwnershipData? ownership;
  final SentimentData? sentiment;
  final OnChainData? onChain;
  final HoneypotData? honeypot;  

  bool get hasCriticalFlags => flags.any((f) => f.isCritical);

  List<IntelligenceFlag> get criticalFlags =>
      flags.where((f) => f.isCritical).toList();

  List<IntelligenceFlag> get highFlags =>
      flags.where((f) => f.severity == FlagSeverity.high).toList();

  /// Compact summary for Telegram notification.
  String get telegramSummary {
    final scoreEmoji = aiScore >= 75
        ? '🟢'
        : aiScore >= 50
            ? '🟡'
            : '🔴';
    return '$scoreEmoji *$tokenSymbol* | Score: $aiScore/100\n'
        '_${aiReasoning.length > 120 ? '${aiReasoning.substring(0, 120)}...' : aiReasoning}_';
  }

  @override
  String toString() {
    return 'TokenIntelligenceReport('
        'chain: $chain, '
        'contractAddress: $contractAddress, '
        'tokenName: $tokenName, '
        'tokenSymbol: $tokenSymbol, '
        'analysisTimestamp: $analysisTimestamp, '
        'verdict: $verdict, '
        'aiScore: $aiScore, '
        'aiReasoning: $aiReasoning, '
        'flags: ${flags.map((f) => f.toString()).join(', ')}, '
        'market: ${market?.toString() ?? 'null'}, '
        'safety: ${safety?.toString() ?? 'null'}, '
        'ownership: ${ownership?.toString() ?? 'null'}, '
        'sentiment: ${sentiment?.toString() ?? 'null'}, '
        'onChain: ${onChain?.toString() ?? 'null'}, '
        'honeypot: ${honeypot?.toString() ?? 'null'}'
        ')';
  }



  // print entire report to terminal to view everything
  void printReportToTerminal() {
    void printSection(String title, Object? value, [int indent = 0]) {
      final prefix = ' ' * indent;
      if (value == null) {
        print('$prefix$title: null');
        return;
      }
      print('$prefix$title: $value');
    }

    void printObject(String title, Object? object) {
      if (object == null) {
        print('$title: null');
        return;
      }

      if (object is MarketData) {
        print('$title:');
        printSection('priceUsd', object.priceUsd, 2);
        printSection('liquidityUsd', object.liquidityUsd, 2);
        printSection('volumeUsd24h', object.volumeUsd24h, 2);
        printSection('marketCapUsd', object.marketCapUsd, 2);
        printSection('holderCount', object.holderCount, 2);
        printSection('tokenAgeHours', object.tokenAgeHours, 2);
        printSection('priceChange1h', object.priceChange1h, 2);
        printSection('priceChange6h', object.priceChange6h, 2);
        printSection('priceChange24h', object.priceChange24h, 2);
        printSection('buySellRatio', object.buySellRatio, 2);
        printSection('pairAddress', object.pairAddress, 2);
        printSection('dexId', object.dexId, 2);
        printSection('buyCount24h', object.buyCount24h, 2);
        printSection('sellCount24h', object.sellCount24h, 2);
        return;
      }

      if (object is SafetyData) {
        print('$title:');
        printSection('isHoneypot', object.isHoneypot, 2);
        printSection('isBlacklisted', object.isBlacklisted, 2);
        printSection('hasMintFunction', object.hasMintFunction, 2);
        printSection('hasProxyContract', object.hasProxyContract, 2);
        printSection('buyTaxPercent', object.buyTaxPercent, 2);
        printSection('sellTaxPercent', object.sellTaxPercent, 2);
        printSection('isContractVerified', object.isContractVerified, 2);
        printSection('isClonedContract', object.isClonedContract, 2);
        printSection('tokenSnifferScore', object.tokenSnifferScore, 2);
        printSection('rugCheckScore', object.rugCheckScore, 2);
        printSection('goplusFlags', object.goplusFlags, 2);
        return;
      }

      if (object is OwnershipData) {
        print('$title:');
        printSection('isLiquidityLocked', object.isLiquidityLocked, 2);
        printSection('liquidityLockPlatform', object.liquidityLockPlatform, 2);
        printSection('liquidityLockDaysRemaining', object.liquidityLockDaysRemaining, 2);
        printSection('isOwnershipRenounced', object.isOwnershipRenounced, 2);
        printSection('top10HoldersPercent', object.top10HoldersPercent, 2);
        printSection('deployerHoldingPercent', object.deployerHoldingPercent, 2);
        printSection('creatorAddress', object.creatorAddress, 2);
        return;
      }

      if (object is SentimentData) {
        print('$title:');
        printSection('mindshareScore', object.mindshareScore, 2);
        printSection('sentimentLabel', object.sentimentLabel, 2);
        printSection('sentimentScore', object.sentimentScore, 2);
        printSection('kolMentionCount', object.kolMentionCount, 2);
        printSection('isOrganicGrowth', object.isOrganicGrowth, 2);
        printSection('narrativeMatch', object.narrativeMatch, 2);
        printSection('socialLinks', object.socialLinks, 2);
        return;
      }

      if (object is OnChainData) {
        print('$title:');
        printSection('walletClusterCount', object.walletClusterCount, 2);
        printSection('suspiciousClusterCount', object.suspiciousClusterCount, 2);
        printSection('deployerFundingSource', object.deployerFundingSource, 2);
        printSection('isWashTrading', object.isWashTrading, 2);
        printSection('uniqueBuyersCount', object.uniqueBuyersCount, 2);
        printSection('avgTransactionSizeUsd', object.avgTransactionSizeUsd, 2);
        return;
      }

      if (object is HoneypotData) {
        print('$title:');
        printSection('isHoneypot', object.isHoneypot, 2);
        printSection('riskLevel', object.riskLevel, 2);
        printSection('riskLabel', object.riskLabel, 2);
        printSection('simulationSuccess', object.simulationSuccess, 2);
        printSection('buyTaxPercent', object.buyTaxPercent, 2);
        printSection('sellTaxPercent', object.sellTaxPercent, 2);
        printSection('transferTaxPercent', object.transferTaxPercent, 2);
        printSection('isOpenSource', object.isOpenSource, 2);
        printSection('isProxy', object.isProxy, 2);
        printSection('totalHolders', object.totalHolders, 2);
        printSection('tokenName', object.tokenName, 2);
        printSection('tokenSymbol', object.tokenSymbol, 2);
        return;
      }

      print('$title: ${object.toString()}');
    }

    print('=== Token Intelligence Report ===');
    printSection('chain', chain);
    printSection('contractAddress', contractAddress);
    printSection('tokenName', tokenName);
    printSection('tokenSymbol', tokenSymbol);
    printSection('analysisTimestamp', analysisTimestamp);
    printSection('verdict', verdict.name);
    printSection('aiScore', aiScore);
    printSection('aiReasoning', aiReasoning);
    print('flags:');
    if (flags.isEmpty) {
      print('  none');
    } else {
      for (final flag in flags) {
        print('  - [${flag.severity.name.toUpperCase()}] ${flag.source}: ${flag.message}');
      }
    }
    printObject('market', market);
    printObject('safety', safety);
    printObject('ownership', ownership);
    printObject('sentiment', sentiment);
    printObject('onChain', onChain);
    printObject('honeypot', honeypot);
    print('=== End Token Intelligence Report ===');
  }
}
