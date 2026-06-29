// rugcheck_service.dart
//
// Wraps the RugCheck.xyz API — the leading Solana-specific token safety tool.
//
// WHY A SEPARATE SOLANA SERVICE (plain English):
//   GoPlus covers Solana, but RugCheck specializes in it and catches
//   Solana-specific patterns GoPlus misses — especially "insider" wallets
//   (wallets that got tokens before public launch) and LP structure
//   quirks unique to Raydium/Orca pools.
//
//   Think of GoPlus as a general doctor and RugCheck as a Solana specialist.
//   We run both and combine their opinions — this is the "second scanner"
//   principle: never trust a single source for a go/no-go decision.
//
// KEY CHECKS:
//   • score          — RugCheck's own 0-100+ risk score (lower = safer in their scale,
//                       we normalize this — see _normalizeScore)
//   • rugged         — Has this token already been rugged according to RugCheck's DB?
//   • risks[]        — List of specific risk objects with name + description + level
//   • markets[]      — LP pool data — locked %, lock provider, lock duration
//   • insiderNetworks — Wallets connected to the deployer that hold supply
//
// API: Free tier available, some endpoints need an API key for higher rate limits.
//   Base URL: https://api.rugcheck.xyz/v1
//   Docs: https://api.rugcheck.xyz/swagger/index.html
//
// NOTE: RugCheck is Solana-only. For Ethereum/BNB we rely on GoPlus + TokenSniffer.

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'token_intelligence_report.dart';

final _log = Logger('RugCheckService');

class RugCheckService {
  static const _baseUrl = 'https://api.rugcheck.xyz/v1';
final String? _apiKey;
  late final Dio _dio;  

 RugCheckService({String? apiKey}) : _apiKey = apiKey {
  _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: _apiKey != null && _apiKey.isNotEmpty
        ? {'X-API-KEY': _apiKey}
        : null,
  ));
}

// ADD field:

  /// Only call this for chain == 'solana'. Returns null for other chains.
  Future<({OwnershipData ownership, List<IntelligenceFlag> flags, int? score, int? holderCount})?>
      checkToken(String mintAddress) async {
    _log.info('RugCheck analysis: $mintAddress');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/tokens/$mintAddress/report',
      );

      final data = response.data;
      if (data == null) return _unknownResult();

      return _parseReport(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _log.info('RugCheck has no data for $mintAddress (too new?)');
      } else {
        _log.warning('RugCheck API error: ${e.message}');
      }
      return _unknownResult();
    }
  }

  // ── PARSING ───────────────────────────────────────────────────────────────
  // rugcheck_service.dart — FULL REPLACEMENT of _parseReport and supporting methods.
// Keep the class declaration, constructor (above), and checkToken() signature
// the same — only _parseReport, _unknownResult, and the return type's flag
// generation change.

  ({OwnershipData ownership, List<IntelligenceFlag> flags, int? score, int? holderCount})
      _parseReport(Map<String, dynamic> data) {
    final flags = <IntelligenceFlag>[];

    // ── Score: track BOTH raw and normalized — normalized (0-100, higher
    // = riskier) is what we display; raw is occasionally useful for
    // debugging since it has no ceiling.
    final rawScore = data['score'] as int?;
    final normalizedScore = data['score_normalised'] as int?;
    final risks = (data['risks'] as List? ?? []).cast<Map<String, dynamic>>();
    final markets = (data['markets'] as List? ?? []).cast<Map<String, dynamic>>();
    final topHolders = (data['topHolders'] as List? ?? []).cast<Map<String, dynamic>>();
    final insiderNetworks = (data['insiderNetworks'] as List? ?? []).cast<Map<String, dynamic>>();
    final creatorTokens = data['creatorTokens'] as List?;
    final verification = data['verification'] as Map<String, dynamic>?;
    final tokenMeta = data['tokenMeta'] as Map<String, dynamic>?;
    final events = (data['events'] as List? ?? []).cast<Map<String, dynamic>>();

    // ── Normalized risk score banding (per RugCheck's own scale) ───────────
    if (normalizedScore != null) {
      if (normalizedScore >= 70) {
        flags.add(IntelligenceFlag(
          source: 'RugCheck',
          severity: FlagSeverity.critical,
          message: 'RugCheck risk score: $normalizedScore/100 — high risk',
        ));
      } else if (normalizedScore >= 40) {
        flags.add(IntelligenceFlag(
          source: 'RugCheck',
          severity: FlagSeverity.high,
          message: 'RugCheck risk score: $normalizedScore/100 — moderate risk',
        ));
      }
    }

    // ── Individual risk items (existing logic, kept) ───────────────────────
    for (final risk in risks) {
      final name = risk['name'] as String? ?? 'Unknown risk';
      final level = (risk['level'] as String? ?? '').toLowerCase();
      final severity = switch (level) {
        'danger' || 'critical' => FlagSeverity.critical,
        'warn' || 'warning' => FlagSeverity.high,
        _ => FlagSeverity.medium,
      };
      flags.add(IntelligenceFlag(source: 'RugCheck', severity: severity, message: name));
    }

    // ── NEW: Mutable metadata warning (you flagged this from the TTF Bot
    // screenshots — "Mutable Metadata" is a real RugCheck/Solana concept) ──
    final isMutable = tokenMeta?['mutable'] as bool? ?? false;
    if (isMutable) {
      flags.add(const IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.medium,
        message: 'Token metadata is mutable — name/symbol/image can be changed post-launch',
      ));
    }

    // ── NEW: Mint/freeze authority (Solana-specific rug vectors) ──────────
    final mintAuthority = data['mintAuthority'];
    final freezeAuthority = data['freezeAuthority'];
    if (mintAuthority != null) {
      flags.add(const IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.critical,
        message: 'Mint authority is NOT null — deployer can mint unlimited new supply at will',
      ));
    }
    if (freezeAuthority != null) {
      flags.add(const IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.critical,
        message: 'Freeze authority is NOT null — deployer can freeze any holder\'s tokens, including yours',
      ));
    }

    // ── NEW: Insider networks — wallet clustering, the single richest
    // signal in this whole report. graphInsidersDetected + insiderNetworks
    // tells you if "different" buyers are actually the same actor. ─────────
    final graphInsidersDetected = data['graphInsidersDetected'] as int? ?? 0;

    if (insiderNetworks.isNotEmpty) {
      final totalAccounts = insiderNetworks.fold<int>(
          0, (sum, n) => sum + (n['size'] as int? ?? 0));
      final largestNetwork = insiderNetworks.reduce((a, b) =>
          (a['size'] as int? ?? 0) > (b['size'] as int? ?? 0) ? a : b);
      final largestSize = largestNetwork['size'] as int? ?? 0;
      final tradeCount = insiderNetworks.where((n) => n['type'] == 'trade').length;
      final transferCount = insiderNetworks.length - tradeCount;

      final parts = <String>[];
      if (transferCount > 0) parts.add('$transferCount fake-holder network(s)');
      if (tradeCount > 0) parts.add('$tradeCount wash-trading network(s)');

      flags.add(IntelligenceFlag(
        source: 'RugCheck',
        severity: largestSize > 50 ? FlagSeverity.critical : FlagSeverity.high,
        message: '${parts.join(' and ')} detected — $totalAccounts total accounts '
            'across all networks controlled by insiders (largest: $largestSize accounts)',
      ));
    } else if (graphInsidersDetected > 0) {
      flags.add(IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.high,
        message: '$graphInsidersDetected insider account(s) detected on-chain',
      ));
    }

    // ── NEW: Creator's track record — has this deployer rugged before? ────
    if (creatorTokens != null && creatorTokens.isNotEmpty) {
      flags.add(IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.high,
        message: 'Deployer has created ${creatorTokens.length} other token(s) — check their history before trusting this one',
      ));
    }

    // ── NEW: Mint/freeze authority history — even if currently null, a
    // PAST mint event means supply was inflated at some point. ────────────
    final hadMintEvent = events.any((e) =>
        (e['type'] as String?)?.toLowerCase().contains('mint') ?? false);
    if (hadMintEvent) {
      flags.add(const IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.medium,
        message: 'Supply has been minted/changed at least once since launch',
      ));
    }

    // ── Liquidity lock — now reading per-market lock %, not just the
    // first market, and surfacing the ACTUAL number instead of a binary ───
    bool isLocked = false;
    double? bestLockedPct;
    String? lockPlatform;

    for (final market in markets) {
      final lp = market['lp'] as Map<String, dynamic>?;
      final lockedPct = (lp?['lpLockedPct'] as num?)?.toDouble();
      if (lockedPct != null && (bestLockedPct == null || lockedPct > bestLockedPct)) {
        bestLockedPct = lockedPct;
      }
    }
    isLocked = (bestLockedPct ?? 0) > 80;

    if (!isLocked) {
      flags.add(IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.high,
        message: bestLockedPct != null
            ? 'Only ${bestLockedPct.toStringAsFixed(0)}% of LP is locked'
            : 'Liquidity pool is not locked or only partially locked',
      ));
    }

    // ── Top holder concentration (existing logic, kept) ────────────────────
    double top10Pct = 0;
    for (final holder in topHolders.take(10)) {
      top10Pct += (holder['pct'] as num?)?.toDouble() ?? 0;
    }
    if (top10Pct > 50) {
      flags.add(IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.high,
        message: 'Top 10 holders control ${top10Pct.toStringAsFixed(0)}% of supply',
      ));
    }

    // ── NEW: insider flag per-holder — RugCheck flags individual top
    // holders as `insider: true/false` directly in the topHolders array ────
    final insiderHolderCount = topHolders.where((h) => h['insider'] == true).length;
    if (insiderHolderCount > 0) {
      flags.add(IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.high,
        message: '$insiderHolderCount of the top holders are flagged as insiders by RugCheck',
      ));
    }

    // ── NEW: Jupiter verification status (Solana-specific trust signal) ───
    final jupVerified = verification?['jup_verified'] as bool? ?? false;
    if (!jupVerified) {
      flags.add(const IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.low,
        message: 'Not verified on Jupiter\'s token list',
      ));
    }

    // ── Deployer holding % ────────────────────────────────────────────────
    // BUG FIX: data['creatorBalance'] is a RAW token count, NOT a percentage.
    // Using it directly produced values like 7,364,533,083% which failed Gate 2.
    // Fix: look up the creator address in topHolders (which already has `pct`
    // as a real 0–100 percentage). If not in the list they hold < top-N
    // threshold → effectively 0% (safe).
    final creatorAddr = data['creator'] as String?;
    double deployerPct = 0;
    if (creatorAddr != null) {
      final creatorHolder = topHolders.firstWhere(
        (h) => (h['address'] as String?)?.toLowerCase() == creatorAddr.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );
      deployerPct = (creatorHolder['pct'] as num?)?.toDouble() ?? 0;
    }

    final ownership = OwnershipData(
      isLiquidityLocked: isLocked,
      liquidityLockPlatform: lockPlatform,
      liquidityLockDaysRemaining: null,
      isOwnershipRenounced: mintAuthority == null && freezeAuthority == null,
      top10HoldersPercent: top10Pct,
      deployerHoldingPercent: deployerPct,
      creatorAddress: creatorAddr,
    );

    final totalHolders = (markets.isNotEmpty
        ? markets.first['totalHolders'] as int?
        : null);

    return (ownership: ownership, flags: flags, score: normalizedScore ?? rawScore, holderCount: totalHolders);
  }
  ({OwnershipData ownership, List<IntelligenceFlag> flags, int? score, int? holderCount})
      _unknownResult() {
    return (
      ownership: const OwnershipData(
        isLiquidityLocked: false,
        liquidityLockPlatform: null,
        liquidityLockDaysRemaining: null,
        isOwnershipRenounced: false,
        top10HoldersPercent: 0,
        deployerHoldingPercent: 0,
        creatorAddress: null,
      ),
      flags: [
        const IntelligenceFlag(
          source: 'RugCheck',
          severity: FlagSeverity.medium,
          message: 'RugCheck data unavailable — likely a brand new token',
        ),
      ],
      score: null,
      holderCount: null,
    );
  }
}
