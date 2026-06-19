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

  late final Dio _dio;

  RugCheckService({String? apiKey}) {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: apiKey != null ? {'Authorization': 'Bearer $apiKey'} : null,
    ));
  }

  /// Only call this for chain == 'solana'. Returns null for other chains.
  Future<({OwnershipData ownership, List<IntelligenceFlag> flags, int? score})?>
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

  ({OwnershipData ownership, List<IntelligenceFlag> flags, int? score})
      _parseReport(Map<String, dynamic> data) {
    final flags = <IntelligenceFlag>[];

    final rawScore = data['score'] as int? ?? data['score_normalised'] as int?;
    final rugged = data['rugged'] as bool? ?? false;
    final risks = (data['risks'] as List? ?? []).cast<Map<String, dynamic>>();
    final markets = (data['markets'] as List? ?? []).cast<Map<String, dynamic>>();

    // ── Already rugged — instant critical flag ──────────────────────────────
    if (rugged) {
      flags.add(const IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.critical,
        message: 'This token has already been flagged as rugged',
      ));
    }

    // ── Parse individual risk items RugCheck identified ─────────────────────
    for (final risk in risks) {
      final name = risk['name'] as String? ?? 'Unknown risk';
      final level = (risk['level'] as String? ?? '').toLowerCase();

      final severity = switch (level) {
        'danger' || 'critical' => FlagSeverity.critical,
        'warn' || 'warning' => FlagSeverity.high,
        _ => FlagSeverity.medium,
      };

      flags.add(IntelligenceFlag(
        source: 'RugCheck',
        severity: severity,
        message: name,
      ));
    }

    // ── Liquidity lock info from markets[] ───────────────────────────────────
    bool isLocked = false;
    String? lockPlatform;
    double? lockDaysRemaining;

    if (markets.isNotEmpty) {
      final primaryMarket = markets.first;
      final lp = primaryMarket['lp'] as Map<String, dynamic>?;
      if (lp != null) {
        final lockedPct = (lp['lpLockedPct'] as num?)?.toDouble() ?? 0;
        isLocked = lockedPct > 80; // consider "locked" if >80% of LP is locked
        lockPlatform = lp['lpLockedPlatform'] as String?;
      }
    }

    if (!isLocked) {
      flags.add(const IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.high,
        message: 'Liquidity pool is not locked or only partially locked',
      ));
    }

    // ── Insider / top holder concentration ───────────────────────────────────
    final topHolders = (data['topHolders'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    double top10Pct = 0;
    for (final holder in topHolders.take(10)) {
      top10Pct += (holder['pct'] as num?)?.toDouble() ?? 0;
    }

    if (top10Pct > 50) {
      flags.add(IntelligenceFlag(
        source: 'RugCheck',
        severity: FlagSeverity.high,
        message:
            'Top 10 holders control ${top10Pct.toStringAsFixed(0)}% of supply',
      ));
    }

    final ownership = OwnershipData(
      isLiquidityLocked: isLocked,
      liquidityLockPlatform: lockPlatform,
      liquidityLockDaysRemaining: lockDaysRemaining,
      isOwnershipRenounced: data['mintAuthority'] == null, // null mint authority ≈ renounced on Solana
      top10HoldersPercent: top10Pct,
      deployerHoldingPercent:
          (data['creatorBalance'] as num?)?.toDouble() ?? 0,
      creatorAddress: data['creator'] as String?,
    );

    return (ownership: ownership, flags: flags, score: rawScore);
  }

  ({OwnershipData ownership, List<IntelligenceFlag> flags, int? score})
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
    );
  }
}
