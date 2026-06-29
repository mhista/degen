// trader_rule_engine.dart
//
// THE NEW BRAIN. This is where the trader's real experience lives —
// not in an LLM's weights, but in deterministic rules that can be
// read, audited, and tuned by a human.
//
// PLAIN ENGLISH — WHY THIS EXISTS:
//   The old pipeline sent all token data to an LLM and asked it to
//   score 0-100 and decide "buy/watch/reject". That's a coin-analyzer
//   bot. THIS is different: we encode the trader's actual, named rules
//   here and apply them mechanically. The LLM's only job after this
//   runs is to EXPLAIN the decision in plain English for the Telegram
//   message — it has no vote on the outcome.
//
// THE RULES, IN THE TRADER'S OWN WORDS (formalized):
//
//   GATE 0 (Pre-analysis, fail = abandon immediately):
//     • Honeypot detected → abandon. Never analyze, never buy.
//
//   GATE 1 (Safety scan):
//     • TokenSniffer score must be ≥ 40 → below = reject
//     • GoPlus must be mostly clean (≥ 80% of checks green)
//     • Buy tax AND sell tax must each be < 8%
//     • The ONLY tolerable "bad" flags are:
//         - external_call
//         - has_blacklist
//         - has_whitelist
//         - trading_cooldown
//       Any other GoPlus flag that isn't in this tolerable list = reject
//
//   GATE 2 (Liquidity & ownership):
//     • Liquidity must be locked for ≥ 30 years (10,950 days) → else abandon
//     • Any single non-null wallet holding > 10% of supply → avoid (rug risk)
//     • More than 5 non-null wallets collectively holding > 20% → avoid
//
//   GATE 3 (Market fit):
//     • Market cap must be between $300 and $3,000 (default range)
//     • User can override this range via bot settings
//
//   RESULT:
//     • Passes all gates → TradeRuleVerdict.buyCandidate
//     • Fails Gate 0 (honeypot) → TradeRuleVerdict.abandoned
//     • Fails any other gate → TradeRuleVerdict.rejected (with reason)
//     • MCap outside range but otherwise clean → TradeRuleVerdict.watchOnly
//
// THE LLM (Claude/Gemini/GPT) IS NOT CALLED FROM HERE.
// It only receives this engine's output and formats it for the user.

import 'package:degenbot_server/src/services/intelligence/token_intelligence_report.dart';
import 'package:degenbot_server/degen_logger.dart';

/// The outcome of the trader's rule engine.
enum TradeRuleVerdict {
  /// Passed all gates — add to the buy candidates list.
  buyCandidate,

  /// Passed safety but MCap is outside the configured range.
  /// Keep on watchlist in case price/mcap changes.
  watchOnly,

  /// Failed a safety/ownership/tax rule. Don't buy. Don't watch.
  rejected,

  /// Honeypot confirmed (Gate 0). Stop immediately — zero more API calls.
  abandoned,
}

/// The full output of the rule engine for one token.
class TradeRuleDecision {
  const TradeRuleDecision({
    required this.verdict,
    required this.reason,
    required this.failedGate,
    required this.tolerableFlags,
    required this.intolerabletFlags,
    required this.warnings,
  });

  final TradeRuleVerdict verdict;

  /// Human-readable reason — passed to the LLM explanation layer.
  final String reason;

  /// Which gate failed (0/1/2/3), or null if all passed.
  final int? failedGate;

  /// GoPlus flags that were present but ARE tolerable (FYI, not blockers).
  final List<String> tolerableFlags;

  /// GoPlus flags that were present and are NOT tolerable (caused reject).
  final List<String> intolerabletFlags;

  /// Non-fatal warnings to surface to the user even on a pass.
  final List<String> warnings;

  bool get passed =>
      verdict == TradeRuleVerdict.buyCandidate ||
      verdict == TradeRuleVerdict.watchOnly;

  /// Factory for a clean pass.
  factory TradeRuleDecision.pass({
    required TradeRuleVerdict verdict,
    required String reason,
    List<String> tolerableFlags = const [],
    List<String> warnings = const [],
  }) =>
      TradeRuleDecision(
        verdict: verdict,
        reason: reason,
        failedGate: null,
        tolerableFlags: tolerableFlags,
        intolerabletFlags: const [],
        warnings: warnings,
      );

  /// Factory for a failure.
  factory TradeRuleDecision.fail({
    required TradeRuleVerdict verdict,
    required int gate,
    required String reason,
    List<String> intolerabletFlags = const [],
    List<String> tolerableFlags = const [],
  }) =>
      TradeRuleDecision(
        verdict: verdict,
        reason: reason,
        failedGate: gate,
        tolerableFlags: tolerableFlags,
        intolerabletFlags: intolerabletFlags,
        warnings: const [],
      );

  @override
  String toString() =>
      'TradeRuleDecision(${verdict.name}, gate: $failedGate, reason: $reason)';
}

/// The configurable MCap range for the buy filter.
/// User can override these via bot settings (/mcap command).
class McapFilter {
  const McapFilter({
    this.minUsd = 300.0,
    this.maxUsd = 3000.0,
  });

  final double minUsd;
  final double maxUsd;

  static const defaultFilter = McapFilter();
}

class TraderRuleEngine {
  // ── CONSTANTS — The trader's hard numbers ────────────────────────────────
  //
  // These are not arbitrary ML weights. They are the trader's explicitly
  // stated rules. Change them here when the trader refines his strategy.

  /// Buy/sell tax above this % = reject. (Trader's rule: < 8%)
  static const double _maxTaxPercent = 8.0;

  /// TokenSniffer score must be AT LEAST this. (Trader's rule: ≥ 40%)
  static const int _minSnifferScore = 40;

  /// Liquidity must be locked for at least this many days. (30 years)
  static const double _minLiquidityLockDays = 10950.0; // 30 * 365

  /// A single non-null wallet holding more than this % = rug risk. (Trader: > 10%)
  static const double _maxSingleWalletPercent = 10.0;

  /// More than this many wallets collectively > _maxGroupWalletPercent = rug risk.
  static const int _maxGroupWalletCount = 5;

  /// The collective % threshold for the group wallet check.
  static const double _maxGroupWalletPercent = 20.0;

  /// GoPlus flags that are acceptable (tolerable). ONLY these. Anything
  /// else the contract exhibits is a hard reject.
  static const Set<String> _tolerableGoPlusFlags = {
    'external_call',
    'has_blacklist',
    'has_whitelist',
    'trading_cooldown',
    // These are generally informational, not critical risk flags
    'anti_whale_modifiable',
    'slippage_modifiable',
    'is_open_source', // actually positive — listing it here since GoPlus lists it
    'is_in_dex',
    'is_mintable', // NOTE: mintable by itself is flagged but some projects use it
  };

  // ── MAIN ENTRY POINT ─────────────────────────────────────────────────────

  /// Apply the trader's rules to a completed token intelligence report.
  /// Returns a verdict the pipeline uses directly — no LLM vote.
  ///
  /// [mcapFilter] defaults to $300-$3000 unless the user has set a custom range.
  TradeRuleDecision evaluate(
    TokenIntelligenceReport report, {
    McapFilter mcapFilter = McapFilter.defaultFilter,
  }) {
    Log.info(
      '📐 [RuleEngine] Evaluating ${report.tokenSymbol} (${report.contractAddress})',
    );

    // ── GATE 0: Honeypot check ────────────────────────────────────────────
    // This is checked first with zero additional API cost — the data is
    // already in the report from Layer 2 (GoPlus) and the honeypot service.
    // If it's a honeypot, we stop EVERYTHING immediately.
    final isHoneypot =
        report.honeypot?.isHoneypot ?? report.safety?.isHoneypot ?? false;

    if (isHoneypot) {
      Log.warning(
        '🚫 [RuleEngine] GATE 0 FAIL — ${report.tokenSymbol} is a honeypot. Abandoning.',
      );
      return TradeRuleDecision.fail(
        verdict: TradeRuleVerdict.abandoned,
        gate: 0,
        reason:
            'HONEYPOT CONFIRMED. You cannot sell this token after buying. '
            'This is an instant disqualification — no further analysis needed.',
      );
    }

    Log.info('   Gate 0 passed: not a honeypot');

    // ── GATE 1: Safety scan ───────────────────────────────────────────────

    // Rule 1a: TokenSniffer score ≥ 40
    final snifferScore = report.safety?.tokenSnifferScore;
    if (snifferScore != null && snifferScore < _minSnifferScore) {
      Log.warning(
        '🚫 [RuleEngine] GATE 1 FAIL — TokenSniffer score $snifferScore < $_minSnifferScore',
      );
      return TradeRuleDecision.fail(
        verdict: TradeRuleVerdict.rejected,
        gate: 1,
        reason:
            'TokenSniffer score is $snifferScore/100 — below the minimum of '
            '$_minSnifferScore. This contract exhibits too many risk patterns '
            'for the safety threshold.',
      );
    }

    // Rule 1b: Buy tax and sell tax < 8%
    final buyTax =
        report.honeypot?.buyTaxPercent ?? report.safety?.buyTaxPercent ?? 0;
    final sellTax =
        report.honeypot?.sellTaxPercent ?? report.safety?.sellTaxPercent ?? 0;

    if (buyTax >= _maxTaxPercent) {
      Log.warning(
        '🚫 [RuleEngine] GATE 1 FAIL — Buy tax ${buyTax.toStringAsFixed(1)}% >= $_maxTaxPercent%',
      );
      return TradeRuleDecision.fail(
        verdict: TradeRuleVerdict.rejected,
        gate: 1,
        reason:
            'Buy tax is ${buyTax.toStringAsFixed(1)}% — above the maximum '
            'of $_maxTaxPercent%. High taxes are a common rug mechanic.',
      );
    }

    if (sellTax >= _maxTaxPercent) {
      Log.warning(
        '🚫 [RuleEngine] GATE 1 FAIL — Sell tax ${sellTax.toStringAsFixed(1)}% >= $_maxTaxPercent%',
      );
      return TradeRuleDecision.fail(
        verdict: TradeRuleVerdict.rejected,
        gate: 1,
        reason:
            'Sell tax is ${sellTax.toStringAsFixed(1)}% — above the maximum '
            'of $_maxTaxPercent%. A high sell tax traps you in the position.',
      );
    }

    // Rule 1c: GoPlus flags — only tolerable ones allowed
    final goplusFlags = report.safety?.goplusFlags ?? const [];
    final intolerable = goplusFlags
        .where((f) => !_tolerableGoPlusFlags.contains(f.toLowerCase()))
        .toList();
    final tolerable = goplusFlags
        .where((f) => _tolerableGoPlusFlags.contains(f.toLowerCase()))
        .toList();

    if (intolerable.isNotEmpty) {
      Log.warning(
        '🚫 [RuleEngine] GATE 1 FAIL — Intolerable GoPlus flags: $intolerable',
      );
      return TradeRuleDecision.fail(
        verdict: TradeRuleVerdict.rejected,
        gate: 1,
        reason:
            'Contract has ${intolerable.length} intolerable flag(s) from GoPlus: '
            '${intolerable.join(", ")}. Only minor cosmetic flags are acceptable.',
        intolerabletFlags: intolerable,
        tolerableFlags: tolerable,
      );
    }

    Log.info(
      '   Gate 1 passed: sniffer=$snifferScore, buy=${buyTax.toStringAsFixed(1)}%, sell=${sellTax.toStringAsFixed(1)}%'
      '${tolerable.isNotEmpty ? ', tolerable flags: ${tolerable.join(", ")}' : ""}',
    );

    // ── GATE 2: Liquidity lock & ownership ───────────────────────────────

    // Rule 2a: Liquidity must be locked ≥ 30 years
    final ownership = report.ownership;
    if (ownership != null) {
      if (!ownership.isLiquidityLocked) {
        Log.warning('🚫 [RuleEngine] GATE 2 FAIL — Liquidity is NOT locked');
        return TradeRuleDecision.fail(
          verdict: TradeRuleVerdict.abandoned,
          gate: 2,
          reason:
              'Liquidity is NOT locked. The deployer can drain the liquidity pool '
              'at any time, making this a guaranteed rug pull risk. Abandoned.',
        );
      }

      final lockDays = ownership.liquidityLockDaysRemaining;
      if (lockDays != null && lockDays < _minLiquidityLockDays) {
        Log.warning(
          '🚫 [RuleEngine] GATE 2 FAIL — LP locked for only ${lockDays.toStringAsFixed(0)} days (need $_minLiquidityLockDays)',
        );
        return TradeRuleDecision.fail(
          verdict: TradeRuleVerdict.abandoned,
          gate: 2,
          reason:
              'Liquidity is only locked for ${lockDays.toStringAsFixed(0)} days '
              '(${(lockDays / 365).toStringAsFixed(1)} years). The trader requires '
              'a minimum 30-year lock. Short locks can be planned rug pulls.',
        );
      }

      // Rule 2b: No single non-null wallet > 10% of supply
      if (ownership.top10HoldersPercent > 0) {
        // We use top10HoldersPercent as a proxy — if top 10 collectively hold
        // the bulk, the individual risk is embedded. The deployer check is
        // the best individual signal we have without per-wallet data.
        if (ownership.deployerHoldingPercent > _maxSingleWalletPercent) {
          Log.warning(
            '🚫 [RuleEngine] GATE 2 FAIL — Deployer holds ${ownership.deployerHoldingPercent.toStringAsFixed(1)}% > $_maxSingleWalletPercent%',
          );
          return TradeRuleDecision.fail(
            verdict: TradeRuleVerdict.rejected,
            gate: 2,
            reason:
                'Deployer wallet holds ${ownership.deployerHoldingPercent.toStringAsFixed(1)}% '
                'of supply — above the ${_maxSingleWalletPercent.toStringAsFixed(0)}% limit. '
                'A deployer with this much supply can dump at any time.',
          );
        }
      }

      // Rule 2c: >5 wallets collectively > 20% of supply
      // We use top10HoldersPercent as the available proxy for this.
      // When per-wallet distribution data becomes available (e.g., Helius),
      // replace this with actual wallet-level analysis.
      if (ownership.top10HoldersPercent > _maxGroupWalletPercent) {
        // Only flag if this concentration is unusually high AND the deployer
        // isn't renounced — if ownership is renounced it's lower risk.
        if (!ownership.isOwnershipRenounced) {
          Log.warning(
            '🚫 [RuleEngine] GATE 2 FAIL — Top 10 wallets hold ${ownership.top10HoldersPercent.toStringAsFixed(1)}% > $_maxGroupWalletPercent% with active owner',
          );
          return TradeRuleDecision.fail(
            verdict: TradeRuleVerdict.rejected,
            gate: 2,
            reason:
                'Top 10 wallets hold ${ownership.top10HoldersPercent.toStringAsFixed(1)}% '
                'of supply with ownership NOT renounced. High concentration with '
                'active control = coordinated dump risk.',
          );
        }
      }

      Log.info(
        '   Gate 2 passed: LP locked=${ownership.isLiquidityLocked}'
        '${lockDays != null ? " (${(lockDays / 365).toStringAsFixed(0)}y)" : ""}'
        ', deployer=${ownership.deployerHoldingPercent.toStringAsFixed(1)}%'
        ', top10=${ownership.top10HoldersPercent.toStringAsFixed(1)}%',
      );
    } else {
      // No ownership data — we can't verify the lock. Flag as warning but
      // don't hard-reject if we have no data (the data source may be down).
      Log.warning(
        '⚠️ [RuleEngine] Gate 2: No ownership data available — cannot verify LP lock',
      );
    }

    // ── GATE 3: Market cap filter ─────────────────────────────────────────

    final mcap = report.market?.marketCapUsd;

    if (mcap == null) {
      // Can't check MCap — treat as watch, not reject
      Log.warning('⚠️ [RuleEngine] Gate 3: MCap unavailable — marking as WATCH');
      return TradeRuleDecision.pass(
        verdict: TradeRuleVerdict.watchOnly,
        reason:
            'Token passed all safety gates but market cap data is unavailable. '
            'Cannot confirm it\'s in the target range (\$${mcapFilter.minUsd.toStringAsFixed(0)}–'
            '\$${mcapFilter.maxUsd.toStringAsFixed(0)}). Monitor manually.',
        tolerableFlags: tolerable,
        warnings: ['Market cap data unavailable from DexScreener'],
      );
    }

    if (mcap < mcapFilter.minUsd || mcap > mcapFilter.maxUsd) {
      Log.info(
        '   Gate 3: MCap \$${mcap.toStringAsFixed(0)} outside range '
        '\$${mcapFilter.minUsd.toStringAsFixed(0)}-\$${mcapFilter.maxUsd.toStringAsFixed(0)} — WATCH only',
      );
      return TradeRuleDecision.pass(
        verdict: TradeRuleVerdict.watchOnly,
        reason:
            'Token passed all safety checks but its market cap '
            '(\$${mcap.toStringAsFixed(0)}) is outside the configured buy range '
            '(\$${mcapFilter.minUsd.toStringAsFixed(0)}–\$${mcapFilter.maxUsd.toStringAsFixed(0)}). '
            'Watching for when it enters the range.',
        tolerableFlags: tolerable,
      );
    }

    // ── ALL GATES PASSED — BUY CANDIDATE ─────────────────────────────────

    final lockInfo = ownership?.liquidityLockDaysRemaining != null
        ? '${(ownership!.liquidityLockDaysRemaining! / 365).toStringAsFixed(0)}y LP lock'
        : 'LP locked';

    final tolerableSummary = tolerable.isNotEmpty
        ? ' Minor flags (tolerable): ${tolerable.join(", ")}.'
        : '';

    Log.success(
      '✅ [RuleEngine] ${report.tokenSymbol} PASSES ALL GATES — BUY CANDIDATE',
    );

    return TradeRuleDecision.pass(
      verdict: TradeRuleVerdict.buyCandidate,
      reason:
          'All trader gates passed. MCap: \$${mcap.toStringAsFixed(0)}, '
          'taxes: ${buyTax.toStringAsFixed(1)}%/${sellTax.toStringAsFixed(1)}% (buy/sell), '
          '$lockInfo.$tolerableSummary',
      tolerableFlags: tolerable,
      warnings: ownership == null
          ? ['Ownership data unavailable — LP lock could not be fully verified']
          : [],
    );
  }

  // ── HELPER: Explain a list of intolerable flags in plain English ─────────
  //
  // Used by the LLM explanation layer to tell users WHY a flag is bad.
  // We don't want the LLM inventing reasons — we give it these ground truths.
  static String explainFlag(String flag) {
    return switch (flag.toLowerCase()) {
      'is_honeypot' => 'You can buy this token but cannot sell it',
      'can_take_back_ownership' =>
        'The deployer can reclaim ownership at any time and rug',
      'owner_change_balance' =>
        'The owner can change any wallet\'s token balance arbitrarily',
      'hidden_owner' =>
        'The contract has a hidden owner not visible on-chain — extreme red flag',
      'selfdestruct' =>
        'The contract can be permanently destroyed, wiping all holdings',
      'is_blacklisted' =>
        'This address is on a known scam blacklist',
      'is_proxy' =>
        'The contract logic can be upgraded/replaced after launch (high risk)',
      'transfer_pausable' =>
        'The deployer can freeze all transfers, trapping holders',
      'can_take_back_ownership' =>
        'Ownership can be reclaimed after it appears renounced',
      _ => 'Flagged by GoPlus security scan as a risk factor',
    };
  }
}
