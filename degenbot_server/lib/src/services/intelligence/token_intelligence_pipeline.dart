// token_intelligence_pipeline.dart
//
// THE DATA GATHERER. This orchestrates the 5-layer intelligence pipeline
// and hands everything to the TraderRuleEngine for the final verdict.
//
// PLAIN ENGLISH — HOW THIS NOW WORKS:
//   Think of this as an investigator assembling evidence. Each layer is
//   a different evidence source:
//     • Layer 1 DexScreener        — market vitals (price, MCap, volume)
//     • Layer 2 GoPlus/RugCheck/Sniffer — is the contract itself dangerous?
//     • Layer 3 Ownership check    — LP locked? deployer still holding?
//     • Layer 4 ChainGPT           — organic social interest? KOL mentions?
//     • Layer 5 On-chain forensics — real buyers or wash trading?
//
//   Once all evidence is gathered, the TRADER'S RULE ENGINE reads it and
//   makes the decision. The LLM (Claude/Gemini/GPT) is then asked to
//   EXPLAIN that decision in plain English — not to make it.
//
// KEY CHANGE FROM THE OLD DESIGN:
//   OLD: LLM gets all data → scores 0-100 → decides buy/watch/reject
//   NEW: Rule engine decides → LLM explains WHY in the Telegram message
//
//   The old approach was a coin-analyzer bot. The new approach is a
//   trading bot that applies the trader's actual, auditable rules.
//
// TOKEN CACHE:
//   Every address that passes through here is stored in TokenCacheService.
//   If it's already there, we return the cached result immediately —
//   zero API calls, zero cost. The scanner loop relies on this heavily.

import 'dart:convert';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:degenbot_server/src/config/env.dart';
import 'package:degenbot_server/src/services/dex/dexscreener_service.dart';
import 'package:degenbot_server/src/services/repository/feature_flags_repository.dart';
import 'package:degenbot_server/src/services/trading/trader_rule_engine.dart';
import 'package:degenbot_server/src/services/trading/token_cache_service.dart';
import 'token_intelligence_report.dart';
import 'goplus_service.dart';
import 'rugcheck_service.dart';
import 'tokensniffer_service.dart';
import 'chaingpt_service.dart';
import 'onchain_forensics_service.dart';
import 'package:degenbot_server/degen_logger.dart';
import 'package:degenbot_server/src/bot/utils/chain_detector.dart';
import 'honeypot_service.dart';

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

  final TraderRuleEngine _ruleEngine = TraderRuleEngine();
  McapFilter _mcapFilter = McapFilter.defaultFilter;

  /// Current MCap filter (readable by command handlers for display).
  McapFilter get mcapFilter => _mcapFilter;

  /// Update the MCap filter (called when user changes /mcap settings).
  void setMcapFilter(McapFilter filter) {
    _mcapFilter = filter;
    Log.info(
      '📐 [Pipeline] MCap filter updated: \$${filter.minUsd.toStringAsFixed(0)}–\$${filter.maxUsd.toStringAsFixed(0)}',
    );
  }

  /// Run the full pipeline on a single token candidate.
  /// This is the ONLY method the scanner loop needs to call.
  Future<TokenIntelligenceReport> analyze({
    required String contractAddress,
    required String chain,
  }) async {
    // ── CACHE CHECK — skip if we've already analyzed this address ─────────
    // This is the first thing we do. If it's cached, we return immediately
    // with zero API calls — the scanner loop sees hundreds of tokens and
    // we never want to re-analyze one we've already processed.
    final cached = TokenCacheService.instance.get(contractAddress);
    if (cached != null) {
      Log.info(
        '💾 [Pipeline] Cache hit for $contractAddress (${cached.tokenSymbol}) '
        '— verdict: ${cached.verdictLabel}. Skipping re-analysis.',
      );
      return _cachedReport(cached);
    }

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

    // ── STEP 6: Apply the trader's rules — THE DECISION ──────────────────
    // The rule engine reads the assembled report data and applies the
    // trader's exact, hardcoded rules to produce a verdict.
    // The LLM has NO role in this decision — it only explains it afterward.
    Log.info('📐 Applying trader rule engine...');

    // Build a partial report for the rule engine to evaluate.
    final partialReport = TokenIntelligenceReport(
      chain: chain,
      contractAddress: contractAddress,
      tokenName: tokenName,
      tokenSymbol: tokenSymbol,
      analysisTimestamp: DateTime.now().toUtc(),
      verdict: TokenVerdict.watch, // placeholder — rule engine sets the real one
      aiScore: 0,
      aiReasoning: '',
      flags: allFlags,
      market: market,
      safety: safety,
      ownership: ownership,
      sentiment: sentimentResult?.data,
      onChain: onChainResult.data,
      honeypot: honeypotData,
    );

    final ruleDecision = _ruleEngine.evaluate(
      partialReport,
      mcapFilter: _mcapFilter,
    );

    // Map rule engine verdict to the report's TokenVerdict enum.
    final finalVerdict = switch (ruleDecision.verdict) {
      TradeRuleVerdict.buyCandidate => TokenVerdict.buy,
      TradeRuleVerdict.watchOnly => TokenVerdict.watch,
      TradeRuleVerdict.rejected => TokenVerdict.reject,
      TradeRuleVerdict.abandoned => TokenVerdict.reject,
    };

    // ── STEP 7: LLM explains the decision (optional, can be disabled) ─────
    // This is purely for readability in the Telegram message. It takes the
    // rule engine's verdict + reason and writes it in plain English.
    // If the LLM call fails or is disabled, the rule engine's reason string
    // is used directly — the verdict is NEVER changed by this step.
    String explanation = ruleDecision.reason;

    if (enabled[FeatureFlag.aiScoring] ?? true) {
      Log.info('🤖 Asking LLM to explain the rule engine\'s decision...');
      explanation = await _explainRuleDecision(
        tokenName: tokenName,
        tokenSymbol: tokenSymbol,
        ruleDecision: ruleDecision,
        market: market,
        fallback: ruleDecision.reason,
      );
    }

    // ── Cache the result so we never re-analyze this address ──────────────
    TokenCacheService.instance.record(
      contractAddress: contractAddress,
      chain: chain,
      tokenSymbol: tokenSymbol,
      verdictLabel: ruleDecision.verdict.name,
      reason: ruleDecision.reason,
    );

    Log.success(
      '🏆 Analysis complete for $tokenSymbol! '
      'Rule verdict: ${ruleDecision.verdict.name.toUpperCase()} | '
      '${ruleDecision.failedGate != null ? "Failed gate ${ruleDecision.failedGate}" : "All gates passed"}',
    );

    return TokenIntelligenceReport(
      chain: chain,
      contractAddress: contractAddress,
      tokenName: tokenName,
      tokenSymbol: tokenSymbol,
      analysisTimestamp: DateTime.now().toUtc(),
      verdict: finalVerdict,
      aiScore: 0, // No longer using a 0-100 score — rule engine is binary
      aiReasoning: explanation,
      flags: allFlags,
      market: market,
      safety: safety,
      ownership: ownership,
      sentiment: sentimentResult?.data,
      onChain: onChainResult.data,
      honeypot: honeypotData,
    );
  }

  // ── AI EXPLANATION LAYER (dartantic_ai) ──────────────────────────────────
  //
  // The LLM's ONLY job: translate the rule engine's decision into
  // plain English for the Telegram message. It has NO vote on the outcome.
  //
  // This replaces the old _runAiScoring — which let the LLM decide.
  // The new design: rules decide, LLM explains.

  /// Ask the LLM to explain the rule engine's verdict in plain English.
  /// Falls back to [fallback] if the LLM call fails or is slow.
  Future<String> _explainRuleDecision({
    required String tokenName,
    required String tokenSymbol,
    required TradeRuleDecision ruleDecision,
    required MarketData? market,
    required String fallback,
  }) async {
    try {
      Provider provider = switch (Env.aiProvider) {
        'openai' => OpenAIProvider(apiKey: Env.openaiApiKey),
        'google' || 'gemini' => GoogleProvider(apiKey: Env.geminiApiKey),
        _ => AnthropicProvider(apiKey: Env.anthropicApiKey),
      };

      final agent = Agent.forProvider(provider);

      final verdictLabel = switch (ruleDecision.verdict) {
        TradeRuleVerdict.buyCandidate => 'APPROVED AS BUY CANDIDATE',
        TradeRuleVerdict.watchOnly => 'ADDED TO WATCHLIST (not buying yet)',
        TradeRuleVerdict.rejected => 'REJECTED',
        TradeRuleVerdict.abandoned => 'ABANDONED (critical risk)',
      };

      final mcapStr = market?.marketCapUsd != null
          ? 'Market cap: \$${market!.marketCapUsd!.toStringAsFixed(0)}'
          : '';
      final tolerableStr = ruleDecision.tolerableFlags.isNotEmpty
          ? 'Note: these minor flags were present but are considered tolerable: '
              '${ruleDecision.tolerableFlags.join(", ")}.'
          : '';

      final prompt =
          '''
A crypto trading bot has evaluated $tokenName ($tokenSymbol) using the trader's
exact rules and reached this verdict: $verdictLabel.

Rule engine reason: ${ruleDecision.reason}
$mcapStr
$tolerableStr

Your job: Explain this verdict in 2-3 sentences of plain English that a
non-technical crypto trader would understand in a Telegram message.

If APPROVED: briefly explain why it passed (what looked good, what minor flags
exist). Be encouraging but honest.

If REJECTED or ABANDONED: explain clearly why — what the specific risk is, what
could go wrong if someone bought this. Don't soften it.

If WATCHLIST: explain it's safe but MCap is outside the target range, and what
to wait for.

Do NOT repeat the token name/symbol (it's shown in the header).
Do NOT use markdown headers.
Respond with ONLY the plain-English explanation, 2-3 sentences max.
''';

      final result = await agent.send(prompt).timeout(const Duration(seconds: 8));
      final text = result.output?.trim();
      if (text == null || text.isEmpty) return fallback;
      return text;
    } catch (e) {
      Log.warning('LLM explanation failed — using rule engine reason: $e');
      return fallback;
    }
  }

  /// Legacy: Lightweight, cheap AI call that ONLY explains an already-decided
  /// rejection in plain English. Kept for backward compatibility with the
  /// hard-gate rejection path.
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

  // ── CACHE REPORT HELPER ───────────────────────────────────────────────────

  /// Build a minimal TokenIntelligenceReport from a cache hit.
  /// We don't have all the layer data anymore — just what we stored.
  TokenIntelligenceReport _cachedReport(CachedTokenResult cached) {
    final verdict = switch (cached.verdictLabel) {
      'buyCandidate' => TokenVerdict.buy,
      'watchOnly' => TokenVerdict.watch,
      'rejected' || 'abandoned' => TokenVerdict.reject,
      _ => TokenVerdict.watch,
    };

    return TokenIntelligenceReport(
      chain: cached.chain,
      contractAddress: cached.contractAddress,
      tokenName: cached.tokenSymbol, // we only cached the symbol
      tokenSymbol: cached.tokenSymbol,
      analysisTimestamp: cached.analyzedAt,
      verdict: verdict,
      aiScore: 0,
      aiReasoning:
          '(Cached result from ${_timeAgo(cached.analyzedAt)}) ${cached.reason}',
      flags: const [],
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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
