// token_intelligence_pipeline.dart
//
// THE BRAIN. This is the orchestrator that runs a token through all five
// intelligence layers and produces the final TokenIntelligenceReport.
//
// PLAIN ENGLISH — HOW THIS WORKS:
//   Think of this as a hiring panel for tokens. Each layer is one
//   interviewer with a different specialty:
//     • DexScreener        — "What do the numbers look like?"
//     • GoPlus/RugCheck/Sniffer — "Is the contract itself dangerous?"
//     • Ownership check    — "Can the deployer still mess with this?"
//     • ChainGPT           — "Is anyone legitimately excited about this?"
//     • On-chain forensics — "Are the buyers real people or bots?"
//
//   Layers 2 and 3 run FIRST and can produce an instant REJECT — if a
//   token is a honeypot, there's no point spending API calls on sentiment
//   analysis. This saves money and time (fail fast).
//
//   If a token survives the hard gates, ALL remaining layers run in
//   PARALLEL (not one after another) — this matters because DexScreener
//   shows new tokens every few seconds, so the pipeline needs to be fast.
//
//   Finally, the AI scoring engine (dartantic_ai) receives the COMPLETE
//   picture from all layers and writes the final score + reasoning.
//
// THIS IS WHERE THE "SMART" IN SMART BOT LIVES.

import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:degenbot_server/src/config/env.dart';
import 'package:degenbot_server/src/services/dex/dexscreener_service.dart';
import 'package:degenbot_server/src/services/repository/feature_flags_repository.dart';
import 'token_intelligence_report.dart';
import 'goplus_service.dart';
import 'rugcheck_service.dart';
import 'tokensniffer_service.dart';
import 'chaingpt_service.dart';
import 'onchain_forensics_service.dart';

final _log = Logger('TokenIntelligencePipeline');

/// Type alias for GoPlus's return tuple — keeps the nullable variable
/// declaration above readable.
typedef GoPlusResultType = ({SafetyData data, List<IntelligenceFlag> flags});

class TokenIntelligencePipeline {
  final DexScreenerService _dex;
  final GoPlusService _goplus;
  final RugCheckService _rugcheck;
  final TokenSnifferService _tokenSniffer;
  final ChainGPTService? _chainGpt; // null if no API key configured
  final OnChainForensicsService _onChain;
  final FeatureFlagsRepository _flags;

  TokenIntelligencePipeline({
    required DexScreenerService dexScreenerService,
    required GoPlusService goPlusService,
    required RugCheckService rugCheckService,
    required TokenSnifferService tokenSnifferService,
    ChainGPTService? chainGptService,
    required OnChainForensicsService onChainForensicsService,
    FeatureFlagsRepository? featureFlagsRepository,
  })  : _dex = dexScreenerService,
        _goplus = goPlusService,
        _rugcheck = rugCheckService,
        _tokenSniffer = tokenSnifferService,
        _chainGpt = chainGptService,
        _onChain = onChainForensicsService,
        _flags = featureFlagsRepository ?? const FeatureFlagsRepository();

  // ── MAIN ENTRY POINT ──────────────────────────────────────────────────────

  /// Run the full pipeline on a single token candidate.
  /// This is the ONLY method the scanner loop needs to call.
  Future<TokenIntelligenceReport> analyze({
    required String contractAddress,
    required String chain,
  }) async {
    _log.info('═══ Analyzing $contractAddress on $chain ═══');
    final allFlags = <IntelligenceFlag>[];

    // Load every toggle once — one Supabase query instead of seven scattered
    // checks. If a flag was flipped via /features a moment ago, this run
    // picks it up immediately.
    final enabled = await _flags.getAllFlags();

    // ── STEP 1: Market data (always needed, cheap, fast) ──────────────────
    if (!(enabled[FeatureFlag.dexScreener] ?? true)) {
      return _errorReport(
        contractAddress,
        chain,
        'DexScreener is disabled via feature flags — cannot analyze without market data',
      );
    }

    final pairs = await _dex.getTokenData(
      contractAddress: contractAddress,
      chain: chain,
    );

    if (pairs.isEmpty) {
      return _errorReport(
        contractAddress,
        chain,
        'No DexScreener data found for this token',
      );
    }

    final pair = pairs.first;
    final tokenName = pair['baseToken']?['name'] as String? ?? 'Unknown';
    final tokenSymbol = pair['baseToken']?['symbol'] as String? ?? '???';

    final market = MarketData(
      priceUsd: DexScreenerService.parsePriceUsd(pair) ?? 0,
      liquidityUsd: DexScreenerService.parseLiquidityUsd(pair) ?? 0,
      volumeUsd24h: DexScreenerService.parseVolume24h(pair) ?? 0,
      marketCapUsd: (pair['marketCap'] as num?)?.toDouble(),
      holderCount: null, // DexScreener doesn't provide this — comes from chain explorer
      tokenAgeHours: _calculateAgeHours(pair),
      priceChange1h: DexScreenerService.parsePriceChange1h(pair),
      priceChange6h: (pair['priceChange']?['h6'] as num?)?.toDouble(),
      priceChange24h: DexScreenerService.parsePriceChange24h(pair),
      buySellRatio: _calculateBuySellRatio(pair),
      pairAddress: pair['pairAddress'] as String? ?? '',
      dexId: pair['dexId'] as String? ?? 'unknown',
    );

    // ── STEP 2: HARD GATE — Safety checks (run first, can short-circuit) ──
    _log.info('Running safety checks (Layer 2)...');

    GoPlusResultType? goplusResult;
    if (enabled[FeatureFlag.goPlus] ?? true) {
      goplusResult = await _goplus.checkToken(
        contractAddress: contractAddress,
        chain: chain,
      );
      allFlags.addAll(goplusResult.flags);
    } else {
      _log.info('GoPlus disabled via feature flag — skipping');
    }

    // RugCheck only applies to Solana, and only if enabled
    int? rugCheckScore;
    OwnershipData? rugCheckOwnership;
    if (chain == 'solana' && (enabled[FeatureFlag.rugCheck] ?? true)) {
      final rugResult = await _rugcheck.checkToken(contractAddress);
      if (rugResult != null) {
        allFlags.addAll(rugResult.flags);
        rugCheckScore = rugResult.score;
        rugCheckOwnership = rugResult.ownership;
      }
    } else if (chain == 'solana') {
      _log.info('RugCheck disabled via feature flag — skipping');
    }

    // TokenSniffer for EVM chains — opt-in, paid, off by default
    int? snifferScore;
    if (enabled[FeatureFlag.tokenSniffer] ?? false) {
      final snifferResult = await _tokenSniffer.checkToken(
        contractAddress: contractAddress,
        chain: chain,
      );
      if (snifferResult != null) {
        allFlags.addAll(snifferResult.flags);
        snifferScore = snifferResult.score;
      }
    }

    final safety = SafetyData(
      isHoneypot: goplusResult?.data.isHoneypot ?? false,
      isBlacklisted: goplusResult?.data.isBlacklisted ?? false,
      hasMintFunction: goplusResult?.data.hasMintFunction ?? false,
      hasProxyContract: goplusResult?.data.hasProxyContract ?? false,
      buyTaxPercent: goplusResult?.data.buyTaxPercent ?? 0,
      sellTaxPercent: goplusResult?.data.sellTaxPercent ?? 0,
      isContractVerified: goplusResult?.data.isContractVerified ?? false,
      isClonedContract: goplusResult?.data.isClonedContract ?? false,
      tokenSnifferScore: snifferScore,
      rugCheckScore: rugCheckScore,
      goplusFlags: goplusResult?.data.goplusFlags ?? const [],
    );

    if (goplusResult == null && rugCheckScore == null) {
      allFlags.add(const IntelligenceFlag(
        source: 'Pipeline',
        severity: FlagSeverity.high,
        message:
            'Both GoPlus and RugCheck are disabled — proceeding with NO safety verification. This is risky.',
      ));
    }

    // ── HARD GATE CHECK — bail out NOW if critical flags exist ────────────
    // This saves API calls to ChainGPT/on-chain forensics for tokens that
    // are already disqualified. Fail fast, fail cheap.
    final criticalFlags = allFlags.where((f) => f.isCritical).toList();
    if (criticalFlags.isNotEmpty) {
      _log.warning(
        '${criticalFlags.length} critical flag(s) — rejecting without further analysis',
      );
      return TokenIntelligenceReport(
        chain: chain,
        contractAddress: contractAddress,
        tokenName: tokenName,
        tokenSymbol: tokenSymbol,
        analysisTimestamp: DateTime.now().toUtc(),
        verdict: TokenVerdict.reject,
        aiScore: 0,
        aiReasoning: 'Rejected at safety gate: '
            '${criticalFlags.map((f) => f.message).join('; ')}',
        flags: allFlags,
        market: market,
        safety: safety,
      );
    }

    // ── STEP 3-5: Run remaining layers IN PARALLEL ─────────────────────────
    // These don't depend on each other, so we fire all requests at once
    // instead of waiting for each one sequentially. This is the difference
    // between a 6-second analysis and a 2-second analysis.
    _log.info('Running ownership, sentiment, and on-chain layers in parallel...');

    final onChainFuture = (enabled[FeatureFlag.onChainForensics] ?? true)
        ? _onChain.analyze(contractAddress: contractAddress, chain: chain)
        : Future.value((
            data: const OnChainData(
              walletClusterCount: 0,
              suspiciousClusterCount: 0,
              deployerFundingSource: null,
              isWashTrading: false,
              uniqueBuyersCount: null,
              avgTransactionSizeUsd: null,
            ),
            flags: <IntelligenceFlag>[],
          ));

    final sentimentFuture =
        (_chainGpt != null && (enabled[FeatureFlag.chainGpt] ?? false))
            ? _chainGpt!.checkSentiment(symbol: tokenSymbol, tokenName: tokenName)
            : Future.value(null);

    final onChainResult = await onChainFuture;
    final sentimentResult = await sentimentFuture;

    allFlags.addAll(onChainResult.flags);
    if (sentimentResult != null) allFlags.addAll(sentimentResult.flags);

    final ownership = rugCheckOwnership ?? _defaultOwnership();

    // ── STEP 6: Hand everything to the AI for final scoring ───────────────
    final aiVerdict = (enabled[FeatureFlag.aiScoring] ?? true)
        ? await (() async {
            _log.info('Sending complete dossier to AI scoring engine...');
            return _runAiScoring(
              tokenName: tokenName,
              tokenSymbol: tokenSymbol,
              chain: chain,
              market: market,
              safety: safety,
              ownership: ownership,
              sentiment: sentimentResult?.data,
              onChain: onChainResult.data,
              flags: allFlags,
            );
          })()
        : (
            verdict: TokenVerdict.watch,
            score: 0,
            reasoning: 'AI scoring is disabled via feature flags — data '
                'gathered but no verdict produced. Enable ai_scoring to get a decision.',
          );

    return TokenIntelligenceReport(
      chain: chain,
      contractAddress: contractAddress,
      tokenName: tokenName,
      tokenSymbol: tokenSymbol,
      analysisTimestamp: DateTime.now().toUtc(),
      verdict: aiVerdict.verdict,
      aiScore: aiVerdict.score,
      aiReasoning: aiVerdict.reasoning,
      flags: allFlags,
      market: market,
      safety: safety,
      ownership: ownership,
      sentiment: sentimentResult?.data,
      onChain: onChainResult.data,
    );
  }

  // ── AI SCORING (dartantic_ai) ─────────────────────────────────────────────

  Future<({TokenVerdict verdict, int score, String reasoning})> _runAiScoring({
    required String tokenName,
    required String tokenSymbol,
    required String chain,
    required MarketData market,
    required SafetyData safety,
    required OwnershipData ownership,
    SentimentData? sentiment,
    required OnChainData onChain,
    required List<IntelligenceFlag> flags,
  }) async {
     Provider provider = switch (Env.aiProvider) {
      'openai' => OpenAIProvider(apiKey: Env.openaiApiKey),
      'google' || 'gemini' => GoogleProvider(apiKey: Env.geminiApiKey),
      _ => AnthropicProvider(apiKey: Env.anthropicApiKey),
    };


  final systemPrompt =  '''
You are a crypto token risk and opportunity scorer for a degen trading bot.
You will receive a complete dossier on a token: market data, safety scan
results, ownership/liquidity data, social sentiment, and on-chain forensics.

Score the token 0-100 where:
  0-29  = REJECT (too risky or no real opportunity)
  30-59 = WATCH (passes safety but not strong enough to buy yet)
  60-100 = BUY (passes safety AND shows genuine opportunity signals)

Weight your scoring as:
  - Safety/contract risk: 40% (already pre-filtered for critical issues,
    but weigh remaining medium/high flags here)
  - Liquidity & ownership structure: 20%
  - Market momentum (volume, buy/sell ratio, price action): 20%
  - Social sentiment & narrative fit: 10%
  - On-chain buyer authenticity: 10%

Respond with ONLY valid JSON in this exact shape, no other text:
{"score": <int 0-100>, "verdict": "<buy|watch|reject>", "reasoning": "<2-3 sentence plain English explanation a non-technical person would understand>"}
''';

    final agent = Agent.forProvider(
      provider,
      
    );

    final prompt = _buildScoringPrompt(
      tokenName: tokenName,
      tokenSymbol: tokenSymbol,
      chain: chain,
      market: market,
      safety: safety,
      ownership: ownership,
      sentiment: sentiment,
      onChain: onChain,
      flags: flags,
    );

    try {
      final result = await agent.send(prompt, history: [
        ChatMessage.system( systemPrompt),
      ]);
      return _parseAiResponse(result.output ?? '');
    } catch (e) {
      _log.severe('AI scoring failed', e);
      // Conservative fallback: if AI fails, don't buy blind
      return (
        verdict: TokenVerdict.watch,
        score: 40,
        reasoning: 'AI scoring unavailable — defaulting to watch-only. '
            'Manual review recommended.',
      );
    }
  }

  String _buildScoringPrompt({
    required String tokenName,
    required String tokenSymbol,
    required String chain,
    required MarketData market,
    required SafetyData safety,
    required OwnershipData ownership,
    SentimentData? sentiment,
    required OnChainData onChain,
    required List<IntelligenceFlag> flags,
  }) {
    final flagSummary = flags.isEmpty
        ? 'No flags raised.'
        : flags.map((f) => '- $f').join('\n');

    return '''
TOKEN: $tokenName ($tokenSymbol) on $chain

MARKET DATA:
- Price: \$${market.priceUsd}
- Liquidity: \$${market.liquidityUsd.toStringAsFixed(0)}
- 24h Volume: \$${market.volumeUsd24h.toStringAsFixed(0)}
- Market Cap: ${market.marketCapUsd != null ? '\$${market.marketCapUsd!.toStringAsFixed(0)}' : 'unknown'}
- Token Age: ${market.tokenAgeHours.toStringAsFixed(1)} hours
- Price change 1h/6h/24h: ${market.priceChange1h ?? '?'}% / ${market.priceChange6h ?? '?'}% / ${market.priceChange24h ?? '?'}%
- Buy/Sell ratio: ${market.buySellRatio.toStringAsFixed(2)}

SAFETY (already passed hard gate — no critical issues):
- Buy/Sell tax: ${safety.buyTaxPercent}% / ${safety.sellTaxPercent}%
- Contract verified: ${safety.isContractVerified}
- TokenSniffer score: ${safety.tokenSnifferScore ?? 'N/A'}
- RugCheck score: ${safety.rugCheckScore ?? 'N/A'}

OWNERSHIP & LIQUIDITY:
- Liquidity locked: ${ownership.isLiquidityLocked} ${ownership.liquidityLockPlatform != null ? '(${ownership.liquidityLockPlatform})' : ''}
- Ownership renounced: ${ownership.isOwnershipRenounced}
- Top 10 holders: ${ownership.top10HoldersPercent.toStringAsFixed(1)}%
- Deployer holding: ${ownership.deployerHoldingPercent.toStringAsFixed(1)}%

SENTIMENT: ${sentiment != null ? '''
- Mindshare score: ${sentiment.mindshareScore ?? 'N/A'}
- Sentiment: ${sentiment.sentimentLabel} (${sentiment.sentimentScore})
- KOL mentions (24h): ${sentiment.kolMentionCount}
- Organic growth: ${sentiment.isOrganicGrowth}
- Narrative: ${sentiment.narrativeMatch ?? 'none identified'}
''' : 'No sentiment data available (likely too new for social tracking)'}

ON-CHAIN FORENSICS:
- Unique buyers: ${onChain.uniqueBuyersCount ?? 'unknown'}
- Wash trading detected: ${onChain.isWashTrading}
- Wallet clusters: ${onChain.walletClusterCount}

ALL FLAGS RAISED:
$flagSummary

Provide your score, verdict, and reasoning as JSON.
''';
  }

  ({TokenVerdict verdict, int score, String reasoning}) _parseAiResponse(
    String raw,
  ) {
    try {
      // Strip markdown code fences if the model added them despite instructions
      final cleaned = raw.replaceAll(RegExp(r'```json|```'), '').trim();
      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      final score = (json['score'] as num).toInt().clamp(0, 100);
      final verdictStr = (json['verdict'] as String).toLowerCase();
      final reasoning = json['reasoning'] as String;

      final verdict = switch (verdictStr) {
        'buy' => TokenVerdict.buy,
        'reject' => TokenVerdict.reject,
        _ => TokenVerdict.watch,
      };

      return (verdict: verdict, score: score, reasoning: reasoning);
    } catch (e) {
      _log.warning('Failed to parse AI response: $raw', e);
      return (
        verdict: TokenVerdict.watch,
        score: 40,
        reasoning: 'Could not parse AI scoring response — defaulting to watch.',
      );
    }
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  double _calculateAgeHours(Map<String, dynamic> pair) {
    final createdAt = pair['pairCreatedAt'] as int?;
    if (createdAt == null) return 999; // assume old if unknown
    final created = DateTime.fromMillisecondsSinceEpoch(createdAt);
    return DateTime.now().difference(created).inMinutes / 60.0;
  }

  double _calculateBuySellRatio(Map<String, dynamic> pair) {
    final txns = pair['txns']?['h24'] as Map<String, dynamic>?;
    final buys = (txns?['buys'] as num?)?.toDouble() ?? 1;
    final sells = (txns?['sells'] as num?)?.toDouble() ?? 1;
    return buys / (sells == 0 ? 1 : sells);
  }

  OwnershipData _defaultOwnership() => const OwnershipData(
        isLiquidityLocked: false,
        liquidityLockPlatform: null,
        liquidityLockDaysRemaining: null,
        isOwnershipRenounced: false,
        top10HoldersPercent: 0,
        deployerHoldingPercent: 0,
        creatorAddress: null,
      );

  TokenIntelligenceReport _errorReport(
    String contractAddress,
    String chain,
    String reason,
  ) {
    return TokenIntelligenceReport(
      chain: chain,
      contractAddress: contractAddress,
      tokenName: 'Unknown',
      tokenSymbol: '???',
      analysisTimestamp: DateTime.now().toUtc(),
      verdict: TokenVerdict.error,
      aiScore: 0,
      aiReasoning: reason,
      flags: [
        IntelligenceFlag(
          source: 'Pipeline',
          severity: FlagSeverity.medium,
          message: reason,
        ),
      ],
    );
  }
}
