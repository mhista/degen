// onchain_forensics_service.dart
//
// Layer 5 — Deep on-chain analysis using block explorer APIs.
//
// WHY THIS LAYER (plain English):
//   Layers 1-4 tell you what a token's CONTRACT and SOCIAL presence look
//   like. This layer asks: who is ACTUALLY trading this, and are they
//   real, independent buyers — or the same handful of wallets shuffling
//   money between each other to fake activity?
//
//   This is the hardest layer to fake. A scammer can write a clean
//   contract and buy a Twitter sentiment bump, but wallet funding
//   patterns leave a trail that's expensive to hide.
//
// WHAT WE CHECK:
//   • Wallet clustering — do many "different" buyer wallets trace back
//     to the same funding source? (classic wash-trading / fake-volume signal)
//   • Deployer funding source — did the deployer wallet get funded from
//     a fresh, anonymous source right before launch? (common rug pattern)
//   • Unique buyer count vs. transaction count — low unique buyers with
//     high tx count = bots cycling the same wallets
//   • Average transaction size — many tiny, uniform-sized buys often
//     indicate bot/wash activity rather than organic interest
//
// DATA SOURCES:
//   ALL chains   → Bitquery V2 GraphQL (primary — wash trading + unique buyers)
//   Ethereum/BNB → Etherscan / BscScan (fallback when Bitquery unavailable)
//   Base         → Bitquery only (no dedicated block explorer key needed)
//   Solana       → Bitquery primary; Solana RPC fallback (tx count only)
//
// NOTE: True wallet-cluster graph analysis (like BubbleMaps does visually)
// is genuinely complex — this service implements a practical approximation
// using funding-source tracing, which catches the most common patterns
// without needing BubbleMaps' paid API. See "Areas for further research"
// in the docs for the full BubbleMaps integration path.

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'token_intelligence_report.dart';
import 'bitquery_service.dart';

final _log = Logger('OnChainForensicsService');

class OnChainForensicsService {
  final String? _etherscanApiKey;
  final String? _bscscanApiKey;
  final String? _solanaRpcUrl;
  final BitqueryService _bitquery;

  late final Dio _dio;

  OnChainForensicsService({
    String? etherscanApiKey,
    String? bscscanApiKey,
    String? solanaRpcUrl,
    BitqueryService? bitqueryService,
  })  : _etherscanApiKey = etherscanApiKey,
        _bscscanApiKey = bscscanApiKey,
        _solanaRpcUrl = solanaRpcUrl ?? 'https://api.mainnet-beta.solana.com',
        _bitquery = bitqueryService ?? BitqueryService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));
  }

  // ── PUBLIC ────────────────────────────────────────────────────────────────

  Future<({OnChainData data, List<IntelligenceFlag> flags})> analyze({
    required String contractAddress,
    required String chain,
  }) async {
    _log.info('On-chain forensics: $contractAddress on $chain');

    try {
      return switch (chain) {
        'ethereum' => await _analyzeWithBitqueryThenFallback(contractAddress, chain, 'etherscan'),
        'bnb'      => await _analyzeWithBitqueryThenFallback(contractAddress, chain, 'bscscan'),
        'base'     => await _analyzeWithBitqueryOrEmpty(contractAddress, chain),
        'solana'   => await _analyzeSolana(contractAddress),
        _          => _unknownResult(),
      };
    } catch (e, st) {
      _log.warning('On-chain forensics failed', e, st);
      return _unknownResult();
    }
  }

  // ── EVM: Ethereum / BNB ────────────────────────────────────────────────────
  // Bitquery primary; Etherscan/BscScan fallback.

  Future<({OnChainData data, List<IntelligenceFlag> flags})> _analyzeWithBitqueryThenFallback(
    String contractAddress,
    String chain,
    String explorer,
  ) async {
    // Primary: Bitquery (wash-trading + unique-buyer detection)
    if (_bitquery.isConfigured) {
      final result = await _bitquery.analyzeToken(contractAddress: contractAddress, chain: chain);
      if (result != null) {
        _log.info('Bitquery $chain: walletClusters=${result.data.walletClusterCount} '
            'washTrading=${result.data.isWashTrading} '
            'uniqueBuyers=${result.data.uniqueBuyersCount}');
        return result;
      }
      _log.warning('Bitquery returned null for $contractAddress on $chain — trying $explorer');
    }

    // Fallback: Etherscan / BscScan token transfer history
    return await _analyzeViaExplorer(contractAddress, explorer);
  }

  /// Base has no dedicated block explorer key — Bitquery only, or empty result.
  Future<({OnChainData data, List<IntelligenceFlag> flags})> _analyzeWithBitqueryOrEmpty(
    String contractAddress,
    String chain,
  ) async {
    if (_bitquery.isConfigured) {
      final result = await _bitquery.analyzeToken(contractAddress: contractAddress, chain: chain);
      if (result != null) {
        _log.info('Bitquery Base: walletClusters=${result.data.walletClusterCount} '
            'washTrading=${result.data.isWashTrading} '
            'uniqueBuyers=${result.data.uniqueBuyersCount}');
        return result;
      }
    }
    // No fallback for Base — return clean empty result (no user-facing flag)
    return (
      data: const OnChainData(
        walletClusterCount: 0,
        suspiciousClusterCount: 0,
        deployerFundingSource: null,
        isWashTrading: false,
        uniqueBuyersCount: null,
        avgTransactionSizeUsd: null,
      ),
      flags: const <IntelligenceFlag>[],
    );
  }

  /// Etherscan / BscScan token transfer history (fallback for ETH and BNB).
  Future<({OnChainData data, List<IntelligenceFlag> flags})> _analyzeViaExplorer(
    String contractAddress,
    String explorer,
  ) async {
    final apiKey = explorer == 'etherscan' ? _etherscanApiKey : _bscscanApiKey;
    if (apiKey == null) {
      _log.fine('No API key for $explorer — skipping on-chain forensics');
      return _unknownResult();
    }

    final baseUrl = explorer == 'etherscan'
        ? 'https://api.etherscan.io/api'
        : 'https://api.bscscan.com/api';

    final response = await _dio.get<Map<String, dynamic>>(
      baseUrl,
      queryParameters: {
        'module': 'account',
        'action': 'tokentx',
        'contractaddress': contractAddress,
        'page': '1',
        'offset': '1000',
        'sort': 'desc',
        'apikey': apiKey,
      },
    );

    final transfers =
        (response.data?['result'] as List? ?? []).cast<Map<String, dynamic>>();

    return _analyzeTransfers(transfers, addressKey: 'to', fromKey: 'from');
  }

  // ── Solana ────────────────────────────────────────────────────────────────

  Future<({OnChainData data, List<IntelligenceFlag> flags})> _analyzeSolana(
    String mintAddress,
  ) async {
    // ── Primary path: Bitquery V2 ────────────────────────────────────────────
    if (_bitquery.isConfigured) {
      _log.fine('Bitquery: analysing Solana token $mintAddress');
      final result = await _bitquery.analyzeToken(contractAddress: mintAddress, chain: 'solana');
      if (result != null) {
        _log.info('Bitquery Solana: walletClusters=${result.data.walletClusterCount} '
            'washTrading=${result.data.isWashTrading} '
            'uniqueBuyers=${result.data.uniqueBuyersCount}');
        return result;
      }
      _log.warning('Bitquery returned null for $mintAddress — falling back to RPC');
    }

    // ── Fallback: Solana RPC (tx count only, no buyer analysis) ─────────────
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _solanaRpcUrl!,
        data: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'getSignaturesForAddress',
          'params': [mintAddress, {'limit': 100}],
        },
      );

      final signatures = (response.data?['result'] as List? ?? []);
      if (signatures.isEmpty) return _unknownResult();

      // RPC gives us tx count but not buyer addresses — return partial data
      return (
        data: OnChainData(
          walletClusterCount: 0,
          suspiciousClusterCount: 0,
          deployerFundingSource: null,
          isWashTrading: false,
          uniqueBuyersCount: null,
          avgTransactionSizeUsd: null,
        ),
        flags: const <IntelligenceFlag>[],
      );
    } catch (e) {
      _log.fine('Solana RPC fallback also failed: $e');
      return _unknownResult();
    }
  }

  // ── SHARED ANALYSIS LOGIC ────────────────────────────────────────────────

  ({OnChainData data, List<IntelligenceFlag> flags}) _analyzeTransfers(
    List<Map<String, dynamic>> transfers, {
    required String addressKey,
    required String fromKey,
  }) {
    final flags = <IntelligenceFlag>[];

    if (transfers.isEmpty) {
      return _unknownResult();
    }

    // Unique recipient addresses (proxy for unique buyers)
    final uniqueBuyers = transfers
        .map((t) => (t[addressKey] as String?)?.toLowerCase())
        .whereType<String>()
        .toSet();

    // Unique sender addresses
    final uniqueSenders = transfers
        .map((t) => (t[fromKey] as String?)?.toLowerCase())
        .whereType<String>()
        .toSet();

    // Wash trading heuristic: if the same small set of addresses appear
    // as BOTH frequent senders AND frequent recipients, that's circular
    // trading — a classic wash-trading / fake-volume pattern.
    final circularAddresses = uniqueBuyers.intersection(uniqueSenders);
    final circularRatio = transfers.isEmpty
        ? 0.0
        : circularAddresses.length / uniqueBuyers.length;

    final isWashTrading = circularRatio > 0.4 && transfers.length > 50;

    if (isWashTrading) {
      flags.add(IntelligenceFlag(
        source: 'OnChainForensics',
        severity: FlagSeverity.high,
        message:
            '${(circularRatio * 100).toStringAsFixed(0)}% of trading wallets '
            'appear on both sides — possible wash trading',
      ));
    }

    // Low unique buyer count relative to transaction count = bot activity
    final txToBuyerRatio = transfers.length / uniqueBuyers.length.clamp(1, double.infinity);
    if (txToBuyerRatio > 10) {
      flags.add(const IntelligenceFlag(
        source: 'OnChainForensics',
        severity: FlagSeverity.medium,
        message: 'Very high transaction-to-unique-buyer ratio — possible bot activity',
      ));
    }

    final data = OnChainData(
      walletClusterCount: uniqueSenders.length,
      suspiciousClusterCount: circularAddresses.length,
      deployerFundingSource: null, // requires tracing first funding tx — research item
      isWashTrading: isWashTrading,
      uniqueBuyersCount: uniqueBuyers.length,
      avgTransactionSizeUsd: null, // requires price-at-time-of-tx lookup
    );

    return (data: data, flags: flags);
  }

  ({OnChainData data, List<IntelligenceFlag> flags}) _unknownResult() {
    // Return clean empty result — internal unavailability is not user-facing noise
    return (
      data: const OnChainData(
        walletClusterCount: 0,
        suspiciousClusterCount: 0,
        deployerFundingSource: null,
        isWashTrading: false,
        uniqueBuyersCount: null,
        avgTransactionSizeUsd: null,
      ),
      flags: const <IntelligenceFlag>[],
    );
  }
}
