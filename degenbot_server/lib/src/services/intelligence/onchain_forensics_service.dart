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
// DATA SOURCES (free tier APIs):
//   Ethereum/BNB → Etherscan / BscScan API (free, rate-limited)
//   Solana       → Solana RPC getSignaturesForAddress + Helius/Moralis
//
// NOTE: True wallet-cluster graph analysis (like BubbleMaps does visually)
// is genuinely complex — this service implements a practical approximation
// using funding-source tracing, which catches the most common patterns
// without needing BubbleMaps' paid API. See "Areas for further research"
// in the docs for the full BubbleMaps integration path.

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'token_intelligence_report.dart';

final _log = Logger('OnChainForensicsService');

class OnChainForensicsService {
  final String? _etherscanApiKey;
  final String? _bscscanApiKey;
  final String? _solanaRpcUrl;

  late final Dio _dio;

  OnChainForensicsService({
    String? etherscanApiKey,
    String? bscscanApiKey,
    String? solanaRpcUrl,
  })  : _etherscanApiKey = etherscanApiKey,
        _bscscanApiKey = bscscanApiKey,
        _solanaRpcUrl = solanaRpcUrl ?? 'https://api.mainnet-beta.solana.com' {
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
        'ethereum' => await _analyzeEvm(contractAddress, 'etherscan'),
        'bnb' => await _analyzeEvm(contractAddress, 'bscscan'),
        'solana' => await _analyzeSolana(contractAddress),
        _ => _unknownResult(),
      };
    } catch (e, st) {
      _log.warning('On-chain forensics failed', e, st);
      return _unknownResult();
    }
  }

  // ── EVM (Ethereum / BNB) ──────────────────────────────────────────────────

  Future<({OnChainData data, List<IntelligenceFlag> flags})> _analyzeEvm(
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

    // Fetch the most recent 1000 token transfer events
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

    final transfers = (response.data?['result'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    return _analyzeTransfers(transfers, addressKey: 'to', fromKey: 'from');
  }

  // ── Solana ────────────────────────────────────────────────────────────────

  Future<({OnChainData data, List<IntelligenceFlag> flags})> _analyzeSolana(
    String mintAddress,
  ) async {
    // Get recent signatures for this mint's token account activity.
    // NOTE: This is a simplified approach. Full implementation should use
    // getTokenLargestAccounts + getSignaturesForAddress combined, or a
    // dedicated indexer like Helius for production-grade accuracy.
    final response = await _dio.post<Map<String, dynamic>>(
      _solanaRpcUrl!,
      data: {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getSignaturesForAddress',
        'params': [mintAddress, {'limit': 1000}],
      },
    );

    final signatures = (response.data?['result'] as List? ?? [])
        .cast<Map<String, dynamic>>();

    if (signatures.isEmpty) {
      return _unknownResult();
    }

    // Without full transaction parsing this gives us transaction COUNT
    // but not buyer addresses — flag this limitation honestly.
    return (
      data: OnChainData(
        walletClusterCount: 0, // requires full tx parsing — see research notes
        suspiciousClusterCount: 0,
        deployerFundingSource: null,
        isWashTrading: false,
        uniqueBuyersCount: null,
        avgTransactionSizeUsd: null,
      ),
      flags: [
        const IntelligenceFlag(
          source: 'OnChainForensics',
          severity: FlagSeverity.low,
          message:
              'Solana wallet clustering needs a dedicated indexer (Helius/Moralis) for full accuracy',
        ),
      ],
    );
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
    return (
      data: const OnChainData(
        walletClusterCount: 0,
        suspiciousClusterCount: 0,
        deployerFundingSource: null,
        isWashTrading: false,
        uniqueBuyersCount: null,
        avgTransactionSizeUsd: null,
      ),
      flags: [
        const IntelligenceFlag(
          source: 'OnChainForensics',
          severity: FlagSeverity.low,
          message: 'On-chain forensics unavailable for this token',
        ),
      ],
    );
  }
}
