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
import 'package:degenbot_server/degen_logger.dart';
// ADD this import at the top of token_intelligence_pipeline.dart:
import 'package:degenbot_server/src/bot/utils/chain_detector.dart'; // adjust path to match where you place it
import 'honeypot_service.dart'; //  a separate service for honeypot checks

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
  final HoneypotService _honeypot;

  TokenIntelligencePipeline({
    required DexScreenerService dexScreenerService,
    required GoPlusService goPlusService,
    required RugCheckService rugCheckService,
    required TokenSnifferService tokenSnifferService,
    required HoneypotService honeypotService,
    ChainGPTService? chainGptService,
    required OnChainForensicsService onChainForensicsService,
    FeatureFlagsRepository? featureFlagsRepository,
  }) : _dex = dexScreenerService,
       _goplus = goPlusService,
       _rugcheck = rugCheckService,
       _tokenSniffer = tokenSnifferService,
       _chainGpt = chainGptService,
       _onChain = onChainForensicsService,
       _honeypot = honeypotService,
       _flags = featureFlagsRepository ?? const FeatureFlagsRepository();

  // ── MAIN ENTRY POINT ──────────────────────────────────────────────────────

  // ── CHAIN-FREE ENTRY POINT (Service A: Analyze) ─────────────────────────
  // The user pastes ANY address, anytime, no command, no chain choice.
  // DexScreener tells us the REAL chain — no more guessing. Chains we have
  // deep support for (solana/ethereum/bnb/base) get the full 5-layer
  // pipeline. Everything else gets a clearly-labeled "lite" report built
  // from DexScreener data alone, until deeper support is built for it.

  static const _deepSupportChains = {'solana', 'ethereum', 'bnb', 'base'};

  Future<TokenIntelligenceReport> analyzeAuto({
    required String contractAddress,
  }) async {
    // Cheap first-pass filter — reject obvious non-addresses with zero API calls.
    if (ChainDetector.detect(contractAddress) == null) {
      Log.warning('❌ Unrecognized address format: $contractAddress');
      return _errorReport(
        contractAddress,
        'unknown',
        'This doesn\'t look like a valid contract address. '
            'Double-check you copied the full address.',
      );
    }

    Log.info('🔗 Resolving chain for $contractAddress via DexScreener...');
    final rawChainId = await _dex.resolveChain(contractAddress);

    if (rawChainId == null) {
      Log.warning(
        '❌ DexScreener has no data for $contractAddress on any chain',
      );
      return _errorReport(
        contractAddress,
        'unknown',
        'No market data found for this address on any chain. It may be '
            'too new (not yet indexed), or the address may be incorrect.',
      );
    }

    final chain = DexScreenerService.normalizeChainId(rawChainId);
    Log.info('   Resolved to: $chain');

    if (_deepSupportChains.contains(chain)) {
      return analyze(contractAddress: contractAddress, chain: chain);
    }

    // ── LITE MODE: DexScreener-only report for chains we don't have
    // GoPlus/RugCheck/Honeypot.is coverage for yet (Pulsechain, Arbitrum,
    // Polygon, etc.) — clearly labeled so the user knows safety checks
    // were skipped, not silently omitted. ───────────────────────────────
    Log.info('   $chain is not a deep-support chain — running LITE analysis');
    return _analyzeLite(contractAddress: contractAddress, chain: chain);
  }

  /// DexScreener-only analysis for chains outside deep support. No
  /// honeypot simulation, no liquidity-lock check, no insider-network
  /// data — just market vitals, clearly flagged as a reduced-confidence
  /// report so nobody mistakes this for a full safety clearance.
  Future<TokenIntelligenceReport> _analyzeLite({
    required String contractAddress,
    required String chain,
  }) async {
    final pairs = await _dex.getTokenData(
      contractAddress: contractAddress,
      chain: chain,
    );

    if (pairs.isEmpty) {
      return _errorReport(
        contractAddress,
        chain,
        'No DexScreener data found for this token on $chain.',
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
      holderCount: null, // not available without a chain-specific explorer
      tokenAgeHours: _calculateAgeHours(pair),
      priceChange1h: DexScreenerService.parsePriceChange1h(pair),
      priceChange6h: (pair['priceChange']?['h6'] as num?)?.toDouble(),
      priceChange24h: DexScreenerService.parsePriceChange24h(pair),
      buySellRatio: _calculateBuySellRatio(pair),
      buyCount24h: _txnCount(pair, 'buys'), // NEW
      sellCount24h: _txnCount(pair, 'sells'),
      pairAddress: pair['pairAddress'] as String? ?? '',
      dexId: pair['dexId'] as String? ?? 'unknown',
    );

    Log.warning(
      '⚠️ LITE MODE for $chain — no safety/ownership/sentiment/forensics data available',
    );

    return TokenIntelligenceReport(
      chain: chain,
      contractAddress: contractAddress,
      tokenName: tokenName,
      tokenSymbol: tokenSymbol,
      analysisTimestamp: DateTime.now().toUtc(),
      verdict: TokenVerdict.watch, // never auto-buy/reject on lite data alone
      aiScore: 0,
      aiReasoning:
          'LITE ANALYSIS: $chain is not yet a fully-supported chain. '
          'Only DexScreener market data is shown below — no honeypot, '
          'liquidity-lock, or insider-network checks were run. Treat this '
          'as informational only, not a safety clearance.',
      flags: [
        IntelligenceFlag(
          source: 'Pipeline',
          severity: FlagSeverity.medium,
          message:
              '$chain has no deep safety coverage yet — verdict is informational only',
        ),
      ],
      market: market,
    );
  }

  /// Run the full pipeline on a single token candidate.
  /// This is the ONLY method the scanner loop needs to call.
  Future<TokenIntelligenceReport> analyze({
    required String contractAddress,
    required String chain,
  }) async {
    Log.info(
      '🔍 Starting full pipeline analysis for token: $contractAddress on chain: $chain',
    );
    final allFlags = <IntelligenceFlag>[];

    // Load every toggle once — one Supabase query instead of seven scattered
    // checks. If a flag was flipped via /features a moment ago, this run
    // picks it up immediately.
    final enabled = await _flags.getAllFlags();

    // ── STEP 1: Market data (always needed, cheap, fast) ──────────────────
    if (!(enabled[FeatureFlag.dexScreener] ?? true)) {
      Log.warning(
        '   DexScreener is disabled via feature flags — aborting analysis',
      );
      return _errorReport(
        contractAddress,
        chain,
        'DexScreener is disabled via feature flags — cannot analyze without market data',
      );
    }

    Log.info('📊 Fetching market data from DexScreener...');
    final pairs = await _dex.getTokenData(
      contractAddress: contractAddress,
      chain: chain,
    );

    if (pairs.isEmpty) {
      Log.warning('   No DexScreener pairs found for $contractAddress');
      return _errorReport(
        contractAddress,
        chain,
        'No DexScreener data found for this token',
      );
    }

    final pair = pairs.first;
    final tokenName = pair['baseToken']?['name'] as String? ?? 'Unknown';
    final tokenSymbol = pair['baseToken']?['symbol'] as String? ?? '???';

    int? resolvedHolderCount; // filled in as Layer 2/3 sources run

    // Log.success('   Market data loaded: $tokenName ($tokenSymbol) | Price: \$${market.priceUsd} | Liquidity: \$${market.liquidityUsd}');

    // ── STEP 2: HARD GATE — Safety checks (run first, can short-circuit) ──
    Log.info('🛡️ Running contract safety checks (Layer 2)...');

    GoPlusResultType? goplusResult;
    if (enabled[FeatureFlag.goPlus] ?? true) {
      Log.debug('   Checking GoPlus Security API...');
      goplusResult = await _goplus.checkToken(
        contractAddress: contractAddress,
        chain: chain,
      );
      allFlags.addAll(goplusResult.flags);
      Log.info(
        '   GoPlus: found ${goplusResult.flags.length} flag(s). isHoneypot: ${goplusResult.data.isHoneypot}',
      );
    } else {
      Log.info('   GoPlus disabled via feature flag — skipping safety scan');
    }

    // Honeypot.is — independent simulation cross-check for EVM chains.
    // Runs alongside GoPlus, not instead of it. When they disagree, that
    // disagreement is itself surfaced as a flag (see below).
    HoneypotData? honeypotData;
    if (chain != 'solana' && (enabled[FeatureFlag.honeypotIs] ?? true)) {
      Log.debug('   Checking honeypot.is...');
      final honeypotResult = await _honeypot.checkToken(
        contractAddress: contractAddress,
        chain: chain,
      );
      if (honeypotResult != null) {
        allFlags.addAll(honeypotResult.flags);
        honeypotData = honeypotResult.data;
        Log.info(
          '   Honeypot.is: isHoneypot=${honeypotData.isHoneypot} | risk=${honeypotData.riskLabel}',
        );

        // ── Cross-check disagreement: GoPlus says safe, honeypot.is says
        // otherwise (or vice versa). Don't silently pick a winner — flag it.
        if (goplusResult != null &&
            goplusResult.data.isHoneypot != honeypotData.isHoneypot) {
          allFlags.add(
            IntelligenceFlag(
              source: 'Pipeline',
              severity: FlagSeverity.critical,
              message:
                  'GoPlus and honeypot DISAGREE on honeypot status '
                  '(GoPlus: ${goplusResult.data.isHoneypot}, honeypot: ${honeypotData.isHoneypot}) '
                  '— treating as critical until manually verified',
            ),
          );
        }
      }
    } else if (chain != 'solana') {
      Log.info('honeypot disabled via feature flag — skipping');
    }

    resolvedHolderCount ??= honeypotData?.totalHolders;

    // RugCheck only applies to Solana, and only if enabled
    int? rugCheckScore;
    OwnershipData? rugCheckOwnership;
    if (chain == 'solana' && (enabled[FeatureFlag.rugCheck] ?? true)) {
      Log.debug('   Checking Solana RugCheck API...');
      final rugResult = await _rugcheck.checkToken(contractAddress);
      if (rugResult != null) {
        allFlags.addAll(rugResult.flags);
        rugCheckScore = rugResult.score;
        rugCheckOwnership = rugResult.ownership;
        resolvedHolderCount ??= rugResult.holderCount;
        Log.info(
          '   RugCheck: score: $rugCheckScore | found ${rugResult.flags.length} flag(s)',
        );
      }
    } else if (chain == 'solana') {
      Log.info('   RugCheck disabled via feature flag — skipping safety scan');
    }

    final market = MarketData(
      priceUsd: DexScreenerService.parsePriceUsd(pair) ?? 0,
      liquidityUsd: DexScreenerService.parseLiquidityUsd(pair) ?? 0,
      volumeUsd24h: DexScreenerService.parseVolume24h(pair) ?? 0,
      marketCapUsd: (pair['marketCap'] as num?)?.toDouble(),
      holderCount:
          null, // DexScreener doesn't provide this — comes from chain explorer
      tokenAgeHours: _calculateAgeHours(pair),
      priceChange1h: DexScreenerService.parsePriceChange1h(pair),
      priceChange6h: (pair['priceChange']?['h6'] as num?)?.toDouble(),
      priceChange24h: DexScreenerService.parsePriceChange24h(pair),
      buyCount24h: _txnCount(pair, 'buys'), // NEW
      sellCount24h: _txnCount(pair, 'sells'),
      buySellRatio: _calculateBuySellRatio(pair),
      pairAddress: pair['pairAddress'] as String? ?? '',
      dexId: pair['dexId'] as String? ?? 'unknown',
    );

    // TokenSniffer for EVM chains — opt-in, paid, off by default
    int? snifferScore;
    if (enabled[FeatureFlag.tokenSniffer] ?? false) {
      Log.debug('   Checking TokenSniffer API...');
      final snifferResult = await _tokenSniffer.checkToken(
        contractAddress: contractAddress,
        chain: chain,
      );
      if (snifferResult != null) {
        allFlags.addAll(snifferResult.flags);
        snifferScore = snifferResult.score;
        Log.info(
          '   TokenSniffer: score: $snifferScore | found ${snifferResult.flags.length} flag(s)',
        );
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
      Log.warning(
        '⚠️ Both GoPlus and RugCheck are disabled — proceeding with NO safety verification. This is highly risky!',
      );
      allFlags.add(
        const IntelligenceFlag(
          source: 'Pipeline',
          severity: FlagSeverity.high,
          message:
              'Both GoPlus and RugCheck are disabled — proceeding with NO safety verification. This is risky.',
        ),
      );
    }

    // ── HARD GATE CHECK — bail out NOW if critical flags exist ────────────
    // This saves API calls to ChainGPT/on-chain forensics for tokens that
    // are already disqualified. Fail fast, fail cheap.
    // REPLACE the critical-flags reject block in analyze() — building on
    // the version from my last message, now calling _explainRejection
    // before constructing the report:

    final criticalFlags = allFlags.where((f) => f.isCritical).toList();
    if (criticalFlags.isNotEmpty) {
      Log.warning(
        '❌ [Safety Gate] ${criticalFlags.length} critical flag(s) found! Rejecting token immediately to save API costs.',
      );
      for (final f in criticalFlags) {
        Log.warning('   Critical Flag: [${f.source}] ${f.message}');
      }

      final bySource = <String, List<IntelligenceFlag>>{};
      for (final f in criticalFlags) {
        bySource.putIfAbsent(f.source, () => []).add(f);
      }
      final sourceSummaries = bySource.entries
          .take(3)
          .map(
            (e) =>
                '${e.key} (${e.value.length} critical issue${e.value.length > 1 ? 's' : ''})',
          )
          .join(', ');

      final fallbackReasoning =
          'Rejected at the safety gate before deeper '
          'analysis ran. Critical issues flagged by: $sourceSummaries. See '
          'the flags list below for full details.';

      // Only spend the AI call if this feature is enabled — reuses the
      // existing aiScoring flag so a single toggle controls all AI spend,
      // hard-gate explanations included.
      final reasoning = (enabled[FeatureFlag.aiScoring] ?? true)
          ? await _explainRejection(
              tokenName: tokenName,
              tokenSymbol: tokenSymbol,
              criticalFlags: criticalFlags,
              fallbackReasoning: fallbackReasoning,
            )
          : fallbackReasoning;

      Log.success('🏆 Rejection explained for $tokenSymbol');

      return TokenIntelligenceReport(
        chain: chain,
        contractAddress: contractAddress,
        tokenName: tokenName,
        tokenSymbol: tokenSymbol,
        analysisTimestamp: DateTime.now().toUtc(),
        verdict: TokenVerdict.reject,
        aiScore: 0,
        aiReasoning: reasoning,
        flags: allFlags,
        market: market,
        safety: safety,
      );
    }
    Log.success('   Safety gate passed with zero critical flags');

    // ── STEP 3-5: Run remaining layers IN PARALLEL ─────────────────────────
    // These don't depend on each other, so we fire all requests at once
    // instead of waiting for each one sequentially. This is the difference
    // between a 6-second analysis and a 2-second analysis.
    Log.info(
      '⚡ Running ownership, sentiment, and on-chain layers in parallel...',
    );

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
    if (sentimentResult != null) {
      allFlags.addAll(sentimentResult.flags);
      Log.info(
        '   ChainGPT sentiment: ${sentimentResult.data.sentimentLabel} | KOL mentions: ${sentimentResult.data.kolMentionCount}',
      );
    }
    Log.info(
      '   OnChain forensics: washTrading: ${onChainResult.data.isWashTrading} | clusters: ${onChainResult.data.walletClusterCount}',
    );

    final ownership = rugCheckOwnership ?? _defaultOwnership();

    // ── STEP 6: Hand everything to the AI for final scoring ───────────────
    final aiVerdict = (enabled[FeatureFlag.aiScoring] ?? true)
        ? await (() async {
            Log.info(
              '🧠 Sending complete token dossier to AI scoring engine...',
            );
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
            reasoning:
                'AI scoring is disabled via feature flags — data '
                'gathered but no verdict produced. Enable ai_scoring to get a decision.',
          );

    Log.success(
      '🏆 Analysis complete for $tokenSymbol! Verdict: ${aiVerdict.verdict.name.toUpperCase()} | Score: ${aiVerdict.score}',
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
      honeypot: honeypotData,
    );
  }

  // ── AI SCORING (dartantic_ai) ─────────────────────────────────────────────
  /// Lightweight, cheap AI call that ONLY explains an already-decided
  /// rejection in plain English. It cannot change the verdict — the
  /// reject has already happened by the time this runs. If this call
  /// fails for any reason, the caller falls back to the mechanical
  /// flag-summary string — the user always gets SOME explanation.
  Future<String> _explainRejection({
    required String tokenName,
    required String tokenSymbol,
    required List<IntelligenceFlag> criticalFlags,
    required String fallbackReasoning,
  }) async {
    try {
      Provider provider = switch (Env.aiProvider) {
        'openai' => OpenAIProvider(apiKey: Env.openaiApiKey),
        'google' || 'gemini' => GoogleProvider(apiKey: Env.geminiApiKey),
        _ => AnthropicProvider(apiKey: Env.anthropicApiKey),
      };

      final agent = Agent.forProvider(provider);

      final flagList = criticalFlags
          .map((f) => '- [${f.source}] ${f.message}')
          .join('\n');

      final prompt =
          '''
A token called $tokenName ($tokenSymbol) was automatically REJECTED by a
crypto safety scanner before any deeper analysis ran. Your ONLY job is to
explain WHY it was rejected, in plain English, to a non-technical crypto
trader reading this in a Telegram bot. 2-3 sentences maximum.

Do NOT score it. Do NOT suggest it might be safe. Do NOT hedge or soften
the rejection — it has already been rejected and that decision is final.
Just explain what these flags mean in practical terms (what could go
wrong for someone who buys this).

Flags that caused the rejection:
$flagList

Respond with ONLY the plain-English explanation, no preamble, no JSON.
''';

      final result = await agent
          .send(prompt)
          .timeout(const Duration(seconds: 8));
      final explanation = result.output?.trim();

      if (explanation == null || explanation.isEmpty) {
        Log.warning(
          'Rejection-explainer returned empty output — using fallback',
        );
        return fallbackReasoning;
      }

      return explanation;
    } catch (e, st) {
      // Never let this block or alter the reject — just log and fall back.
      Log.warning(
        'Rejection-explainer AI call failed — using fallback reasoning: $e',
      );
      return fallbackReasoning;
    }
  }

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

    final systemPrompt = '''
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
      final result = await agent.send(
        prompt,
        history: [
          ChatMessage.system(systemPrompt),
        ],
      );
      return _parseAiResponse(result.output ?? '');
    } catch (e, st) {
      Log.error('❌ AI scoring agent request failed', error: e, stackTrace: st);
      // Conservative fallback: if AI fails, don't buy blind
      return (
        verdict: TokenVerdict.watch,
        score: 40,
        reasoning:
            'AI scoring unavailable — defaulting to watch-only. '
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
      Log.warning('Failed to parse AI response: $raw', data: e);
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

  int _txnCount(Map<String, dynamic> pair, String key) {
    final txns = pair['txns']?['h24'] as Map<String, dynamic>?;
    return (txns?[key] as num?)?.toInt() ?? 0;
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
