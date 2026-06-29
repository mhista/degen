// goplus_service.dart
//
// Wraps the GoPlus Security Token Security API.
//
// AUTHENTICATION (V3 authenticated endpoint):
//   GoPlus requires HMAC-SHA256 signing for registered API keys.
//   Every request includes three query params:
//     app_key  = your API key
//     time     = current Unix timestamp (seconds)
//     sign     = HMAC-SHA256(app_secret, time_string)
//
//   Set GOPLUS_API_KEY and GOPLUS_API_SECRET in .env.
//   Without them the service falls back to the unauthenticated endpoint
//   (tighter rate limits, sometimes empty for Solana).
//
// FAILURE HANDLING:
//   If GoPlus is unavailable or returns no data, the service returns an
//   empty SafetyData with NO flags. Internal failures are invisible to
//   the user and logged server-side only. Users should never see
//   "GoPlus unavailable" — it's meaningless noise to them.
//
// Chain IDs: 1=Ethereum, 56=BNB, 501=Solana

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:degenbot_server/src/config/env.dart';
import 'token_intelligence_report.dart';

final _log = Logger('GoPlusService');

class GoPlusService {
  static const _baseUrl = 'https://api.gopluslabs.io/api/v1';

  static const _chainIds = {
    'ethereum': '1',
    'bnb': '56',
    'solana': '501',
  };

  late final Dio _dio;
  final String? _apiKey;
  final String? _apiSecret;

  GoPlusService({String? apiKey, String? apiSecret})
      : _apiKey = apiKey ?? (Env.goPlusApiKey.isNotEmpty ? Env.goPlusApiKey : null),
        _apiSecret = apiSecret ?? (Env.goPlusApiSecret.isNotEmpty ? Env.goPlusApiSecret : null) {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _log.info(
      _apiKey != null
          ? 'GoPlus initialised with authenticated API key'
          : 'GoPlus running unauthenticated (set GOPLUS_API_KEY for higher rate limits)',
    );
  }

  // ── PUBLIC ────────────────────────────────────────────────────────────────

  Future<({SafetyData data, List<IntelligenceFlag> flags})> checkToken({
    required String contractAddress,
    required String chain,
  }) async {
    final chainId = _chainIds[chain];
    if (chainId == null) {
      _log.warning('GoPlus: unsupported chain $chain — skipping');
      return _emptyResult();
    }

    _log.info('GoPlus check: $contractAddress on $chain');

    try {
      final params = <String, dynamic>{
        'contract_addresses': contractAddress.toLowerCase(),
      };

      // Add HMAC auth params when API key is configured
      if (_apiKey != null && _apiSecret != null) {
        final timeStr = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
        params['app_key'] = _apiKey;
        params['time'] = timeStr;
        params['sign'] = _hmacSign(_apiSecret!, timeStr);
      }

      final response = await _dio.get<Map<String, dynamic>>(
        '/token_security/$chainId',
        queryParameters: params,
      );

      final result = response.data?['result'] as Map<String, dynamic>?;
      if (result == null || result.isEmpty) {
        // Common for very new tokens or Solana tokens not yet indexed — not an error
        _log.fine('GoPlus: no data for $contractAddress — token may be too new');
        return _emptyResult();
      }

      final tokenData =
          result[contractAddress.toLowerCase()] as Map<String, dynamic>?
          ?? result.values.first as Map<String, dynamic>;

      return _parseTokenData(tokenData, chain);
    } on DioException catch (e) {
      // Log internally, never surface to user
      _log.warning('GoPlus API error (${e.response?.statusCode ?? "network"}): ${e.message}');
      return _emptyResult();
    } catch (e) {
      _log.warning('GoPlus unexpected error: $e');
      return _emptyResult();
    }
  }

  // ── HMAC-SHA256 SIGNING ───────────────────────────────────────────────────

  String _hmacSign(String secret, String message) {
    final key = utf8.encode(secret);
    final msg = utf8.encode(message);
    final hmac = Hmac(sha256, key);
    return hmac.convert(msg).toString();
  }

  // ── PARSING ───────────────────────────────────────────────────────────────

  ({SafetyData data, List<IntelligenceFlag> flags}) _parseTokenData(
    Map<String, dynamic> d,
    String chain,
  ) {
    final flags = <IntelligenceFlag>[];

    bool b(String key) => d[key]?.toString() == '1';
    double pct(String key) => double.tryParse(d[key]?.toString() ?? '0') ?? 0.0;

    final isHoneypot  = b('is_honeypot');
    final isBlacklisted = b('is_blacklisted');
    final hasMint     = b('is_mintable');
    final hasProxy    = b('is_proxy');
    final buyTax      = pct('buy_tax') * 100;   // GoPlus returns 0–1 decimals
    final sellTax     = pct('sell_tax') * 100;
    final isVerified  = b('is_open_source');
    final isCloned    = b('is_airdrop_scam') || b('is_honeypot_like_token');

    // Critical
    if (isHoneypot) flags.add(const IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.critical,
      message: 'Honeypot — you cannot sell this token',
    ));
    if (isBlacklisted) flags.add(const IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.critical,
      message: 'Contract on known scam blacklist',
    ));
    if (sellTax > 30) flags.add(IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.critical,
      message: 'Sell tax ${sellTax.toStringAsFixed(0)}% — effectively a honeypot',
    ));
    if (isCloned) flags.add(const IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.critical,
      message: 'Contract matches known scam/airdrop template',
    ));

    // High
    if (hasMint) flags.add(const IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.high,
      message: 'Mint function present — deployer can inflate supply',
    ));
    if (hasProxy) flags.add(const IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.high,
      message: 'Upgradeable proxy — contract logic can change after launch',
    ));
    if (b('can_take_back_ownership')) flags.add(const IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.high,
      message: 'Deployer can reclaim ownership after renouncing',
    ));
    if (sellTax > 10 && sellTax <= 30) flags.add(IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.high,
      message: 'High sell tax: ${sellTax.toStringAsFixed(0)}%',
    ));

    // Medium
    if (!isVerified) flags.add(const IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.medium,
      message: 'Contract source not verified on block explorer',
    ));
    if (buyTax > 10) flags.add(IntelligenceFlag(
      source: 'GoPlus', severity: FlagSeverity.medium,
      message: 'High buy tax: ${buyTax.toStringAsFixed(0)}%',
    ));

    final goplusRawFlags = d.entries
        .where((e) => e.value?.toString() == '1')
        .map((e) => e.key)
        .toList();

    return (
      data: SafetyData(
        isHoneypot: isHoneypot,
        isBlacklisted: isBlacklisted,
        hasMintFunction: hasMint,
        hasProxyContract: hasProxy,
        buyTaxPercent: buyTax,
        sellTaxPercent: sellTax,
        isContractVerified: isVerified,
        isClonedContract: isCloned,
        tokenSnifferScore: null,
        rugCheckScore: null,
        goplusFlags: goplusRawFlags,
      ),
      flags: flags,
    );
  }

  /// Empty/neutral result — no user-facing flags.
  /// Used when API is unreachable, returns no data, or chain is unsupported.
  ({SafetyData data, List<IntelligenceFlag> flags}) _emptyResult() => (
    data: const SafetyData(
      isHoneypot: false,
      isBlacklisted: false,
      hasMintFunction: false,
      hasProxyContract: false,
      buyTaxPercent: 0,
      sellTaxPercent: 0,
      isContractVerified: false,
      isClonedContract: false,
      tokenSnifferScore: null,
      rugCheckScore: null,
      goplusFlags: [],
    ),
    flags: [],
  );
}
