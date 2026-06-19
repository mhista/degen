// intelligence_feature_flags.dart
//
// Central on/off switches for every paid or optional intelligence source.
//
// PLAIN ENGLISH:
//   Think of this as a row of light switches on a wall. Each switch
//   controls one external API. Flip it off and that layer is skipped
//   entirely — no API calls, no cost, no errors. Flip it on and it
//   rejoins the pipeline next time you restart the server.
//
//   This file reads from .env so you can toggle features WITHOUT
//   touching code — just change a value in .env and restart.
//
// WHY THIS MATTERS FOR YOUR BUDGET:
//   GoPlus, RugCheck, Etherscan/BscScan, and DexScreener are free —
//   they default ON and there's rarely a reason to turn them off.
//   TokenSniffer ($99/mo) and ChainGPT (credit-based) default OFF —
//   you opt in only once you're ready to pay for them.
//
// HOW TO TOGGLE:
//   Edit degenbot_server/.env and set any of these to true/false:
//     ENABLE_GOPLUS=true
//     ENABLE_RUGCHECK=true
//     ENABLE_TOKENSNIFFER=false
//     ENABLE_CHAINGPT=false
//     ENABLE_ONCHAIN_FORENSICS=true
//   Then restart the server. No code changes needed.
//
//   You can ALSO toggle live via Telegram using /features (see
//   feature_flags_endpoint.dart) — this writes to Supabase and is
//   checked on every pipeline run, so no restart needed for that path.

import 'package:envied/envied.dart';

part 'intelligence_feature_flags.g.dart';

@Envied(path: '.env')
abstract class IntelligenceFeatureFlags {
  // ── Layer 1: Market data ─────────────────────────────────────────────────
  // DexScreener is free and foundational — there's no reason to disable it,
  // but the flag exists for completeness / testing with mock data.
  @EnviedField(varName: 'ENABLE_DEXSCREENER', defaultValue: true)
  static final bool dexScreener = _IntelligenceFeatureFlags.dexScreener;

  // ── Layer 2: Safety checks ───────────────────────────────────────────────
  // GoPlus is free (30 calls/min) — keep this ON by default.
  @EnviedField(varName: 'ENABLE_GOPLUS', defaultValue: true)
  static final bool goPlus = _IntelligenceFeatureFlags.goPlus;

  // RugCheck is free for Solana — keep ON if you trade Solana.
  @EnviedField(varName: 'ENABLE_RUGCHECK', defaultValue: true)
  static final bool rugCheck = _IntelligenceFeatureFlags.rugCheck;

  // TokenSniffer costs $99/mo for API access — OFF by default.
  // Flip to true once you've decided the cost is worth the second opinion.
  @EnviedField(varName: 'ENABLE_TOKENSNIFFER', defaultValue: false)
  static final bool tokenSniffer = _IntelligenceFeatureFlags.tokenSniffer;

  // ── Layer 3: Ownership/liquidity ─────────────────────────────────────────
  // Currently sourced from RugCheck (Solana) — no separate flag needed yet.
  // Will get its own flag when direct Unicrypt/Team.Finance APIs are added
  // (see research_roadmap.md item #9).

  // ── Layer 4: Sentiment ────────────────────────────────────────────────────
  // ChainGPT is credit-based — OFF by default. Turn on once you've decided
  // to either pay-as-you-go or stake $CGPT for free credits.
  @EnviedField(varName: 'ENABLE_CHAINGPT', defaultValue: false)
  static final bool chainGpt = _IntelligenceFeatureFlags.chainGpt;

  // ── Layer 5: On-chain forensics ──────────────────────────────────────────
  // Etherscan/BscScan are free — keep ON.
  @EnviedField(varName: 'ENABLE_ONCHAIN_FORENSICS', defaultValue: true)
  static final bool onChainForensics =
      _IntelligenceFeatureFlags.onChainForensics;

  // ── AI scoring ────────────────────────────────────────────────────────────
  // This should basically never be off — without it there's no verdict.
  // Flag exists so you can dry-run the data-gathering layers without
  // spending any AI tokens (useful while debugging the other services).
  @EnviedField(varName: 'ENABLE_AI_SCORING', defaultValue: true)
  static final bool aiScoring = _IntelligenceFeatureFlags.aiScoring;
}
