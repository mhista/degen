// goplus_service.dart
//
// Wraps the GoPlus Security Token Security API.
//
// WHAT GOPLUS CHECKS (plain English):
//   GoPlus is used by Binance, MetaMask, and Trust Wallet to check tokens
//   before users interact with them. It runs a battery of checks on the
//   smart contract itself — not just the token's market data.
//
// KEY CHECKS:
//   • is_honeypot         — Can you actually sell? (yes = trap)
//   • can_take_back_ownership — Can the deployer re-take control after renouncing?
//   • is_blacklisted      — Is the contract on known scam lists?
//   • is_mintable         — Can the deployer mint unlimited new tokens?
//   • is_proxy            — Is this an upgradeable proxy (can change behaviour)?
//   • buy_tax / sell_tax  — What % is taken on each trade?
//   • is_open_source      — Is the contract code verified on-chain?
//   • holder_count        — How many unique holders?
//
// API: FREE, no key required for basic use.
//   Base URL: https://api.gopluslabs.io/api/v1/token_security/{chainId}
//   Chain IDs: 1=Ethereum, 56=BNB, 501=Solana
//
// DOCS: https://docs.gopluslabs.io/reference/api-overview

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'token_intelligence_report.dart';

final _log = Logger('GoPlusService');

class GoPlusService {
  static const _baseUrl = 'https://api.gopluslabs.io/api/v1';

  // Chain ID mapping: our names → GoPlus chain IDs
  static const _chainIds = {
    'ethereum': '1',
    'bnb': '56',
    'solana': '501',
  };

  late final Dio _dio;

  GoPlusService() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }

  // ── PUBLIC ────────────────────────────────────────────────────────────────

  /// Run a full safety check on a token contract.
  /// Returns a [SafetyData] object and a list of flags raised.
  Future<({SafetyData data, List<IntelligenceFlag> flags})> checkToken({
    required String contractAddress,
    required String chain,
  }) async {
    final chainId = _chainIds[chain];
    if (chainId == null) {
      throw ArgumentError('Unsupported chain for GoPlus: $chain');
    }

    _log.info('GoPlus check: $contractAddress on $chain');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/token_security/$chainId',
        queryParameters: {'contract_addresses': contractAddress.toLowerCase()},
      );

      final result = response.data?['result'] as Map<String, dynamic>?;
      if (result == null || result.isEmpty) {
        _log.warning('GoPlus returned empty result for $contractAddress');
        return _unknownResult();
      }

      // GoPlus returns a map keyed by lowercased contract address
      final tokenData =
          result[contractAddress.toLowerCase()] as Map<String, dynamic>?
              ?? result.values.first as Map<String, dynamic>;

      return _parseTokenData(tokenData, chain);
    } on DioException catch (e) {
      _log.warning('GoPlus API error: ${e.message}');
      return _unknownResult();
    }
  }

  // ── PARSING ───────────────────────────────────────────────────────────────

  ({SafetyData data, List<IntelligenceFlag> flags}) _parseTokenData(
    Map<String, dynamic> d,
    String chain,
  ) {
    final flags = <IntelligenceFlag>[];

    // Helper: GoPlus returns "0" or "1" as strings for booleans
    bool b(String key) => d[key]?.toString() == '1';
    double pct(String key) =>
        double.tryParse(d[key]?.toString() ?? '0') ?? 0.0;

    final isHoneypot = b('is_honeypot');
    final isBlacklisted = b('is_blacklisted');
    final hasMint = b('is_mintable');
    final hasProxy = b('is_proxy');
    final buyTax = pct('buy_tax') * 100; // GoPlus returns 0–1
    final sellTax = pct('sell_tax') * 100;
    final isVerified = b('is_open_source');
    final isCloned = b('is_airdrop_scam') || b('is_honeypot_like_token');

    // ── Critical flags ─────────────────────────────────────────────────────
    if (isHoneypot) {
      flags.add(const IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.critical,
        message: 'Honeypot detected — cannot sell this token',
      ));
    }

    if (isBlacklisted) {
      flags.add(const IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.critical,
        message: 'Contract address on known scam blacklist',
      ));
    }

    if (sellTax > 30) {
      flags.add(IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.critical,
        message: 'Sell tax ${sellTax.toStringAsFixed(0)}% — effectively a honeypot',
      ));
    }

    if (isCloned) {
      flags.add(const IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.critical,
        message: 'Contract matches known scam/airdrop template',
      ));
    }

    // ── High flags ─────────────────────────────────────────────────────────
    if (hasMint) {
      flags.add(const IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.high,
        message: 'Contract has mint function — deployer can inflate supply',
      ));
    }

    if (hasProxy) {
      flags.add(const IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.high,
        message: 'Upgradeable proxy — contract logic can change after launch',
      ));
    }

    if (b('can_take_back_ownership')) {
      flags.add(const IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.high,
        message: 'Deployer can reclaim ownership even after renouncing',
      ));
    }

    if (sellTax > 10 && sellTax <= 30) {
      flags.add(IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.high,
        message: 'High sell tax: ${sellTax.toStringAsFixed(0)}%',
      ));
    }

    // ── Medium flags ───────────────────────────────────────────────────────
    if (!isVerified) {
      flags.add(const IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.medium,
        message: 'Contract source not verified on block explorer',
      ));
    }

    if (buyTax > 10) {
      flags.add(IntelligenceFlag(
        source: 'GoPlus',
        severity: FlagSeverity.medium,
        message: 'High buy tax: ${buyTax.toStringAsFixed(0)}%',
      ));
    }

    // Collect all raw GoPlus flag keys that are "1" (true)
    final goplusRawFlags = d.entries
        .where((e) => e.value?.toString() == '1')
        .map((e) => e.key)
        .toList();

    final safetyData = SafetyData(
      isHoneypot: isHoneypot,
      isBlacklisted: isBlacklisted,
      hasMintFunction: hasMint,
      hasProxyContract: hasProxy,
      buyTaxPercent: buyTax,
      sellTaxPercent: sellTax,
      isContractVerified: isVerified,
      isClonedContract: isCloned,
      tokenSnifferScore: null, // set by TokenSniffer service
      rugCheckScore: null,     // set by RugCheck service
      goplusFlags: goplusRawFlags,
    );

    return (data: safetyData, flags: flags);
  }

  /// Fallback when API is unreachable — marks safety as unknown.
  ({SafetyData data, List<IntelligenceFlag> flags}) _unknownResult() {
    return (
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
      flags: [
        const IntelligenceFlag(
          source: 'GoPlus',
          severity: FlagSeverity.medium,
          message: 'GoPlus API unavailable — safety check incomplete',
        ),
      ],
    );
  }
}
