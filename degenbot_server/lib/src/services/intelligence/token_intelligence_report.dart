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
}
