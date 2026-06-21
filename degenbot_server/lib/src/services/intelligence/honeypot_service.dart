// honeypot_service.dart
//
// Wraps api.honeypot.is — direct honeypot simulation + holder data for
// Ethereum, BSC, and Base. This is an INDEPENDENT cross-check alongside
// GoPlus — a token has to pass two different simulation engines, not one,
// before it's trusted. GoPlus and honeypot.is occasionally disagree, and
// when they do, that disagreement itself is a signal worth surfacing.
//
// CHAIN COVERAGE: Ethereum (1), BSC (56), Base (8453) only. Solana is
// RugCheck's job — never call this service for chain == 'solana'.
//
// THE 5-CALL PATTERN (matches honeypot.is's own recommended flow):
//   1. GetPairs            — find all trading pairs for this token
//   2. TokenInfo            — name/symbol/decimals/supply
//   3. TopHolders           — holder list + totalSupply (gives us holderCount)
//   4. IsHoneypot           — the actual buy/sell simulation (needs a pair address)
//   5. GetContractVerification — proxy/source verification flag
//
// CACHING: results cached in Supabase for 30s by default — a token pasted
// twice in quick succession (e.g. by two users, or one user re-checking)
// reuses the cached result instead of hammering honeypot.is five times
// per analysis. Toggleable: when caching is OFF, every call goes straight
// to the API with no DB round-trip at all (useful for debugging staleness).

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'dart:convert';
import '../repository/supabase_client.dart';
import 'token_intelligence_report.dart';

final _log = Logger('HoneypotService');

class HoneypotService {
  static const _baseUrl = 'https://api.honeypot.is';
  static const _cacheTtlSeconds = 30;

  /// Master on/off switch for the 30s Supabase cache. When false, every
  /// call bypasses the DB entirely and goes direct to the API — no
  /// caching, no staleness, but more API calls.
  final bool useCache;

  late final Dio _dio;

  HoneypotService({this.useCache = true}) {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }

  static const _chainIds = {
    'ethereum': 1,
    'bnb': 56,
    'base': 8453,
  };

  /// Returns null if this chain isn't covered by honeypot.is, or if every
  /// call in the chain fails (e.g. token genuinely doesn't exist there).
  Future<({HoneypotData data, List<IntelligenceFlag> flags})?> checkToken({
    required String contractAddress,
    required String chain,
  }) async {
    final chainId = _chainIds[chain];
    if (chainId == null) {
      _log.fine('honeypot.is does not cover chain: $chain');
      return null;
    }

    final cacheKey = 'honeypot:$chain:${contractAddress.toLowerCase()}';

    if (useCache) {
      final cached = await _readCache(cacheKey);
      if (cached != null) {
        _log.info('Cache hit: $cacheKey');
        return _fromCachedJson(cached);
      }
    }

    _log.info('honeypot.is full check: $contractAddress on $chain (chainID=$chainId)');

    try {
      // ── STEP 1: GetPairs — find the pair with the most liquidity ───────
      final pairsResponse = await _dio.get<List<dynamic>>(
        '/v1/GetPairs',
        queryParameters: {'address': contractAddress, 'chainID': chainId},
      );
      final pairs = (pairsResponse.data ?? []).cast<Map<String, dynamic>>();

      if (pairs.isEmpty) {
        _log.warning('No pairs found for $contractAddress on $chain — token may be too new or delisted');
        return _unknownResult();
      }

      // Pick the most liquid pair — that's the one real traders actually use.
      pairs.sort((a, b) => ((b['Liquidity'] as num?) ?? 0)
          .compareTo((a['Liquidity'] as num?) ?? 0));
      final bestPair = pairs.first;
      final pairAddress = (bestPair['Pair'] as Map<String, dynamic>)['Address'] as String;

      // ── STEP 2: TokenInfo ────────────────────────────────────────────────
      final tokenInfoResponse = await _dio.get<Map<String, dynamic>>(
        '/v1/TokenInfo',
        queryParameters: {'address': contractAddress, 'chainID': chainId},
      );
      final tokenInfo = tokenInfoResponse.data ?? {};

      // ── STEP 3: TopHolders ───────────────────────────────────────────────
      Map<String, dynamic>? topHoldersData;
      try {
        final topHoldersResponse = await _dio.get<Map<String, dynamic>>(
          '/v1/TopHolders',
          queryParameters: {'address': contractAddress, 'chainID': chainId},
        );
        topHoldersData = topHoldersResponse.data;
      } catch (e) {
        _log.warning('TopHolders failed for $contractAddress — continuing without it: $e');
      }

      // ── STEP 4: IsHoneypot (v2 — richer simulation data) ────────────────
      final honeypotResponse = await _dio.get<Map<String, dynamic>>(
        '/v2/IsHoneypot',
        queryParameters: {
          'address': contractAddress,
          'pair': pairAddress,
          'chainID': chainId,
        },
      );
      final honeypotData = honeypotResponse.data;

      if (honeypotData == null) {
        _log.warning('IsHoneypot returned no data for $contractAddress');
        return _unknownResult();
      }

      // Detect honeypot.is's internal-error sentinel — the doc notes a
      // {"code":500,"error":"internal error"} response means this address
      // doesn't actually exist on this chain (used for chain detection).
      if (honeypotData['code'] == 500) {
        _log.info('honeypot.is internal error for $contractAddress on $chain — likely wrong chain');
        return null;
      }

      // ── STEP 5: GetContractVerification ─────────────────────────────────
      Map<String, dynamic>? verificationData;
      try {
        final verificationResponse = await _dio.get<Map<String, dynamic>>(
          '/v1/GetContractVerification',
          queryParameters: {
            'address': contractAddress,
            'pair': pairAddress,
            'chainID': chainId,
          },
        );
        verificationData = verificationResponse.data;
      } catch (e) {
        _log.warning('GetContractVerification failed — continuing without it: $e');
      }

      final result = _parseFullCheck(
        tokenInfo: tokenInfo,
        topHolders: topHoldersData,
        honeypot: honeypotData,
        verification: verificationData,
        pairs: pairs,
      );

      if (useCache) {
        await _writeCache(cacheKey, result);
      }

      return result;
    } on DioException catch (e) {
      _log.warning('honeypot.is API error for $contractAddress: ${e.message}');
      return _unknownResult();
    }
  }

  // ── PARSING ─────────────────────────────────────────────────────────────

  ({HoneypotData data, List<IntelligenceFlag> flags}) _parseFullCheck({
    required Map<String, dynamic> tokenInfo,
    required Map<String, dynamic>? topHolders,
    required Map<String, dynamic> honeypot,
    required Map<String, dynamic>? verification,
    required List<Map<String, dynamic>> pairs,
  }) {
    final flags = <IntelligenceFlag>[];

    final isHoneypot = (honeypot['honeypotResult'] as Map<String, dynamic>?)?['isHoneypot'] as bool? ?? false;
    final summary = honeypot['summary'] as Map<String, dynamic>?;
    final riskLevel = summary?['riskLevel'] as int? ?? 0;
    final riskLabel = summary?['risk'] as String? ?? 'unknown';
    final simulationSuccess = honeypot['simulationSuccess'] as bool? ?? false;
    final simResult = honeypot['simulationResult'] as Map<String, dynamic>?;
    final buyTax = (simResult?['buyTax'] as num?)?.toDouble() ?? 0;
    final sellTax = (simResult?['sellTax'] as num?)?.toDouble() ?? 0;
    final transferTax = (simResult?['transferTax'] as num?)?.toDouble() ?? 0;

    final contractCode = honeypot['contractCode'] as Map<String, dynamic>?;
    final isOpenSource = contractCode?['openSource'] as bool? ?? false;
    final isProxy = contractCode?['isProxy'] as bool? ?? false;
    final hasProxyCalls = contractCode?['hasProxyCalls'] as bool? ??
        verification?['HasProxyCalls'] as bool? ?? false;

    final totalHolders = (honeypot['token'] as Map<String, dynamic>?)?['totalHolders'] as int?
        ?? int.tryParse((topHolders?['holders'] as List?)?.length.toString() ?? '');

    // ── CRITICAL: simulation says honeypot ──────────────────────────────
    if (isHoneypot) {
      flags.add(const IntelligenceFlag(
        source: 'Honeypot.is',
        severity: FlagSeverity.critical,
        message: 'Simulated sell FAILED — this token cannot be sold (confirmed honeypot)',
      ));
    }

    if (!simulationSuccess) {
      flags.add(const IntelligenceFlag(
        source: 'Honeypot.is',
        severity: FlagSeverity.high,
        message: 'Buy/sell simulation could not complete — proceed with extreme caution',
      ));
    }

    // ── Risk level from honeypot.is's own summary ───────────────────────
    if (riskLevel >= 3) {
      flags.add(IntelligenceFlag(
        source: 'Honeypot',
        severity: FlagSeverity.critical,
        message: 'honeypot risk summary: $riskLabel (level $riskLevel)',
      ));
    } else if (riskLevel == 2) {
      flags.add(IntelligenceFlag(
        source: 'Honeypot',
        severity: FlagSeverity.high,
        message: 'honeypot risk summary: $riskLabel (level $riskLevel)',
      ));
    }

    // ── Tax flags ─────────────────────────────────────────────────────────
    if (sellTax > 30) {
      flags.add(IntelligenceFlag(
        source: 'Honeypot',
        severity: FlagSeverity.critical,
        message: 'Simulated sell tax ${sellTax.toStringAsFixed(1)}% — effectively unsellable',
      ));
    } else if (sellTax > 10) {
      flags.add(IntelligenceFlag(
        source: 'Honeypot',
        severity: FlagSeverity.high,
        message: 'High simulated sell tax: ${sellTax.toStringAsFixed(1)}%',
      ));
    }

    if (transferTax > 0) {
      flags.add(IntelligenceFlag(
        source: 'Honeypot',
        severity: FlagSeverity.medium,
        message: 'Transfer tax detected: ${transferTax.toStringAsFixed(1)}% — wallet-to-wallet transfers are taxed too',
      ));
    }

    // ── Proxy / unverified source ────────────────────────────────────────
    if (isProxy || hasProxyCalls) {
      flags.add(const IntelligenceFlag(
        source: 'Honeypot',
        severity: FlagSeverity.high,
        message: 'Contract uses proxy calls — logic can be swapped post-launch',
      ));
    }

    if (!isOpenSource) {
      flags.add(const IntelligenceFlag(
        source: 'Honeypot',
        severity: FlagSeverity.medium,
        message: 'Contract source not verified/open on honeypot.is',
      ));
    }

    // ── Holder tax distribution sanity check ────────────────────────────
    // If a meaningful slice of REAL simulated holders pay a much higher
    // tax than the headline sellTax, that's a sign of a tiered/targeted
    // tax structure (e.g. bots get nuked, insiders don't).
    final holderAnalysis = honeypot['holderAnalysis'] as Map<String, dynamic>?;
    final highTaxWallets = int.tryParse(holderAnalysis?['highTaxWallets']?.toString() ?? '0') ?? 0;
    if (highTaxWallets > 0) {
      flags.add(IntelligenceFlag(
        source: 'Honeypot',
        severity: FlagSeverity.medium,
        message: '$highTaxWallets simulated holder wallet(s) hit an unusually high tax — possible targeted tax logic',
      ));
    }

    final data = HoneypotData(
      isHoneypot: isHoneypot,
      riskLevel: riskLevel,
      riskLabel: riskLabel,
      simulationSuccess: simulationSuccess,
      buyTaxPercent: buyTax,
      sellTaxPercent: sellTax,
      transferTaxPercent: transferTax,
      isOpenSource: isOpenSource,
      isProxy: isProxy || hasProxyCalls,
      totalHolders: totalHolders,
      tokenName: tokenInfo['Name'] as String?,
      tokenSymbol: tokenInfo['Symbol'] as String?,
    );

    return (data: data, flags: flags);
  }

  // ── CACHE (Supabase, 30s TTL) ─────────────────────────────────────────

  Future<Map<String, dynamic>?> _readCache(String key) async {
    try {
      final row = await supabase
          .from('honeypot_cache')
          .select()
          .eq('cache_key', key)
          .maybeSingle();

      if (row == null) return null;

      final cachedAt = DateTime.parse(row['cached_at'] as String);
      final age = DateTime.now().toUtc().difference(cachedAt).inSeconds;
      if (age > _cacheTtlSeconds) {
        _log.fine('Cache stale ($age s old) for $key — ignoring');
        return null;
      }

      return jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    } catch (e) {
      _log.warning('honeypot cache read failed for $key: $e');
      return null;
    }
  }

  Future<void> _writeCache(
    String key,
    ({HoneypotData data, List<IntelligenceFlag> flags}) result,
  ) async {
    try {
      await supabase.from('honeypot_cache').upsert({
        'cache_key': key,
        'payload': jsonEncode(_toCacheJson(result)),
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'cache_key');
    } catch (e) {
      _log.warning('honeypot cache write failed for $key: $e');
      // Don't rethrow — a failed cache write shouldn't fail the analysis.
    }
  }

  Map<String, dynamic> _toCacheJson(
    ({HoneypotData data, List<IntelligenceFlag> flags}) result,
  ) {
    return {
      'isHoneypot': result.data.isHoneypot,
      'riskLevel': result.data.riskLevel,
      'riskLabel': result.data.riskLabel,
      'simulationSuccess': result.data.simulationSuccess,
      'buyTaxPercent': result.data.buyTaxPercent,
      'sellTaxPercent': result.data.sellTaxPercent,
      'transferTaxPercent': result.data.transferTaxPercent,
      'isOpenSource': result.data.isOpenSource,
      'isProxy': result.data.isProxy,
      'totalHolders': result.data.totalHolders,
      'tokenName': result.data.tokenName,
      'tokenSymbol': result.data.tokenSymbol,
      'flags': result.flags.map((f) => {
        'source': f.source,
        'severity': f.severity.name,
        'message': f.message,
      }).toList(),
    };
  }

  ({HoneypotData data, List<IntelligenceFlag> flags}) _fromCachedJson(Map<String, dynamic> json) {
    final data = HoneypotData(
      isHoneypot: json['isHoneypot'] as bool,
      riskLevel: json['riskLevel'] as int,
      riskLabel: json['riskLabel'] as String,
      simulationSuccess: json['simulationSuccess'] as bool,
      buyTaxPercent: (json['buyTaxPercent'] as num).toDouble(),
      sellTaxPercent: (json['sellTaxPercent'] as num).toDouble(),
      transferTaxPercent: (json['transferTaxPercent'] as num).toDouble(),
      isOpenSource: json['isOpenSource'] as bool,
      isProxy: json['isProxy'] as bool,
      totalHolders: json['totalHolders'] as int?,
      tokenName: json['tokenName'] as String?,
      tokenSymbol: json['tokenSymbol'] as String?,
    );
    final flags = (json['flags'] as List).map((f) => IntelligenceFlag(
      source: f['source'] as String,
      severity: FlagSeverity.values.byName(f['severity'] as String),
      message: f['message'] as String,
    )).toList();
    return (data: data, flags: flags);
  }

  ({HoneypotData data, List<IntelligenceFlag> flags}) _unknownResult() {
    return (
      data: const HoneypotData(
        isHoneypot: false,
        riskLevel: 0,
        riskLabel: 'unknown',
        simulationSuccess: false,
        buyTaxPercent: 0,
        sellTaxPercent: 0,
        transferTaxPercent: 0,
        isOpenSource: false,
        isProxy: false,
        totalHolders: null,
        tokenName: null,
        tokenSymbol: null,
      ),
      flags: [
        const IntelligenceFlag(
          source: 'Honeypot.is',
          severity: FlagSeverity.medium,
          message: 'honeypot.is check unavailable — relying on other safety sources',
        ),
      ],
    );
  }
}