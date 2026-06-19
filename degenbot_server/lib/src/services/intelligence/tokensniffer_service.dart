// tokensniffer_service.dart
//
// Wraps the TokenSniffer API — used as the "second opinion" scanner.
//
// WHY A SECOND SCANNER (plain English):
//   No single scanner catches everything. Scammers study the popular
//   tools and design contracts specifically to slip past them.
//    Run two scanners: if either flags honeypot behavior, extreme
//   sell tax, or owner-only god-mode, stop. 
//   TokenSniffer's database has tracked tens of millions of tokens and
//   flagged millions as scams — if a contract is a near-clone of a
//   known rug, TokenSniffer is often the one that catches it because
//   it specifically checks for code similarity to known scam templates.
//
// API NOTE:
//   The free web UI requires a CAPTCHA (not usable for automation).
//   The Sniffer Pack Pro API ($99/month, 500 scans/day) is the path for
//   a production trading bot. Budget for this once you're past prototyping —
//   in Step 1 we treat it as optional and skip gracefully if no key is set.
//
// EVM ONLY: TokenSniffer covers Ethereum, BNB, and other EVM chains.
// Not used for Solana (RugCheck covers that).

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'token_intelligence_report.dart';

final _log = Logger('TokenSnifferService');

class TokenSnifferService {
  static const _baseUrl = 'https://tokensniffer.com/api/v2';

  final String? _apiKey;
  late final Dio _dio;

  TokenSnifferService({String? apiKey}) : _apiKey = apiKey {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }

  /// Returns null if no API key is configured (graceful skip).
  Future<({int? score, List<IntelligenceFlag> flags})?> checkToken({
    required String contractAddress,
    required String chain,
  }) async {
    if (_apiKey == null) {
      _log.fine('TokenSniffer skipped — no API key configured');
      return null;
    }

    final chainId = _chainToId(chain);
    if (chainId == null) {
      _log.fine('TokenSniffer does not support chain: $chain');
      return null;
    }

    _log.info('TokenSniffer check: $contractAddress on $chain');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/tokens/$chainId/$contractAddress',
        queryParameters: {'apikey': _apiKey},
      );

      final data = response.data;
      if (data == null) return (score: null, flags: <IntelligenceFlag>[]);

      return _parseResponse(data);
    } on DioException catch (e) {
      _log.warning('TokenSniffer API error: ${e.message}');
      return (score: null, flags: <IntelligenceFlag>[
        const IntelligenceFlag(
          source: 'TokenSniffer',
          severity: FlagSeverity.low,
          message: 'TokenSniffer check failed — proceeding with other sources',
        ),
      ]);
    }
  }

  ({int? score, List<IntelligenceFlag> flags}) _parseResponse(
    Map<String, dynamic> data,
  ) {
    final flags = <IntelligenceFlag>[];
    final score = data['score'] as int?;
    final isScam = data['is_scam'] as bool? ?? false;
    final tests = (data['tests'] as Map<String, dynamic>?) ?? {};

    if (isScam) {
      flags.add(const IntelligenceFlag(
        source: 'TokenSniffer',
        severity: FlagSeverity.critical,
        message: 'Flagged as scam in TokenSniffer database',
      ));
    }

    if (score != null && score < 50) {
      flags.add(IntelligenceFlag(
        source: 'TokenSniffer',
        severity: FlagSeverity.high,
        message: 'Low trust score: $score/100',
      ));
    }

    // Specific test failures
    if (tests['is_contract_verified'] == false) {
      flags.add(const IntelligenceFlag(
        source: 'TokenSniffer',
        severity: FlagSeverity.medium,
        message: 'Contract source code not verified',
      ));
    }

    if (tests['has_similar_scam_contracts'] == true) {
      flags.add(const IntelligenceFlag(
        source: 'TokenSniffer',
        severity: FlagSeverity.critical,
        message: 'Contract bytecode matches known scam templates',
      ));
    }

    return (score: score, flags: flags);
  }

  String? _chainToId(String chain) => switch (chain) {
        'ethereum' => 'eth',
        'bnb' => 'bsc',
        _ => null, // Solana not supported by TokenSniffer
      };
}
