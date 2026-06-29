// bitquery_service.dart
//
// Bitquery V2 GraphQL API — multi-chain on-chain forensics.
//
// SUPPORTED CHAINS:
//   Solana  → Bitquery `Solana` namespace (DEXTrades + BalanceUpdates)
//   EVM     → Bitquery `EVM` namespace (eth / bsc / base)
//             • Ethereum (eth)
//             • BNB / BSC (bsc)
//             • Base (base)
//
// WHAT IT GIVES US:
//   1. Unique buyer count — distinct wallets that actually bought.
//      High trade count + few unique buyers = bots or wash trading.
//   2. Wash-trading detection — same wallet on BOTH buy AND sell side
//      across different trades = coordinated volume faking.
//   3. Buyer/seller ratio signal — organic markets have many buyers per tx.
//
// AUTHENTICATION:
//   OAuth2 client credentials (grant_type=client_credentials).
//   Tokens expire in 24h. Refresh is automatic — callers never manage tokens.
//   Credentials read from BITQUERY_CLIENT_ID / BITQUERY_CLIENT_SECRET in .env.
//
//   Token endpoint:   https://oauth2.bitquery.io/oauth2/token
//   GraphQL endpoint: https://streaming.bitquery.io/eap
//
// POINT COST (Bitquery's usage unit):
//   Queries only run after Gate 0–1 pass (honeypot/safety checks), so we never
//   waste points on obvious scams. Estimated ~5–10 points per full analysis.
//
// FAILURE HANDLING:
//   Any failure returns null — caller falls back gracefully. Zero user-facing noise.

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:degenbot_server/src/config/env.dart';
import 'token_intelligence_report.dart';

final _log = Logger('BitqueryService');

/// Maps our internal chain name to the Bitquery EVM network identifier.
/// Solana is handled separately via the `Solana` namespace.
const _evmNetworkId = {
  'ethereum': 'eth',
  'bnb': 'bsc',
  'base': 'base',
};

class BitqueryService {
  static const _tokenUrl = 'https://oauth2.bitquery.io/oauth2/token';
  static const _graphqlUrl = 'https://streaming.bitquery.io/eap';

  final String? _clientId;
  final String? _clientSecret;

  late final Dio _dio;
  String? _accessToken;
  DateTime? _tokenExpiry;

  BitqueryService({String? clientId, String? clientSecret})
      : _clientId = clientId ?? (Env.bitqueryClientId.isNotEmpty ? Env.bitqueryClientId : null),
        _clientSecret =
            clientSecret ?? (Env.bitqueryClientSecret.isNotEmpty ? Env.bitqueryClientSecret : null) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _log.info(
      _clientId != null
          ? 'Bitquery initialised (client credentials flow)'
          : 'Bitquery not configured — set BITQUERY_CLIENT_ID/SECRET in .env',
    );
  }

  bool get isConfigured => _clientId != null && _clientSecret != null;

  // ── PUBLIC API ─────────────────────────────────────────────────────────────

  /// Analyse a token for wallet clustering and wash-trading signals.
  /// [chain] must be one of: 'solana', 'ethereum', 'bnb', 'base'.
  /// Returns null when Bitquery is unavailable or not configured.
  Future<({OnChainData data, List<IntelligenceFlag> flags})?> analyzeToken({
    required String contractAddress,
    required String chain,
  }) async {
    if (!isConfigured) return null;

    try {
      final token = await _getAccessToken();
      if (token == null) return null;

      if (chain == 'solana') {
        return await _analyzeSolana(contractAddress, token);
      }

      final networkId = _evmNetworkId[chain];
      if (networkId == null) {
        _log.fine('Bitquery: unsupported chain "$chain"');
        return null;
      }

      return await _analyzeEvm(contractAddress, networkId, chain, token);
    } catch (e, st) {
      _log.warning('Bitquery analysis failed for $contractAddress on $chain: $e', e, st);
      return null;
    }
  }

  // ── OAUTH2 ─────────────────────────────────────────────────────────────────

  Future<String?> _getAccessToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(seconds: 60)))) {
      return _accessToken;
    }

    _log.fine('Bitquery: refreshing OAuth2 access token');
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _tokenUrl,
        data: {
          'grant_type': 'client_credentials',
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'scope': 'api',
        },
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );

      final data = response.data;
      if (data == null) return null;

      _accessToken = data['access_token'] as String?;
      final expiresIn = data['expires_in'] as int? ?? 86400;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
      _log.info('Bitquery token acquired, expires in ${expiresIn}s');
      return _accessToken;
    } on DioException catch (e) {
      _log.warning('Bitquery token request failed: ${e.response?.statusCode} ${e.message}');
      return null;
    }
  }

  // ── SOLANA ─────────────────────────────────────────────────────────────────

  Future<({OnChainData data, List<IntelligenceFlag> flags})?> _analyzeSolana(
    String mintAddress,
    String token,
  ) async {
    // Run trades + holders in parallel — saves a round trip
    final results = await Future.wait([
      _querySolanaTrades(mintAddress, token),
      _querySolanaHolders(mintAddress, token),
    ]);

    final trades = results[0] as _TradesResult?;
    final holders = results[1] as _HoldersResult?;

    _log.info('Bitquery Solana: trades=${trades?.totalTrades} '
        'uniqueBuyers=${trades?.uniqueBuyers} '
        'washWallets=${trades?.washTradingWalletCount}');

    return _buildResult(trades, holders);
  }

  Future<_TradesResult?> _querySolanaTrades(String mintAddress, String token) async {
    const query = r'''
query SolanaTrades($mint: String!) {
  Solana {
    DEXTrades(
      where: {
        Trade: { Buy: { Currency: { MintAddress: { is: $mint } } } }
        Transaction: { Result: { Success: true } }
      }
      limit: { count: 200 }
      orderBy: { descending: Block_Time }
    ) {
      Trade {
        Buy  { Account { Address } Amount AmountInUSD }
        Sell { Account { Address } }
      }
    }
  }
}
''';

    try {
      final response = await _gql(query, {'mint': mintAddress}, token);
      final rawTrades =
          (response?['data']?['Solana']?['DEXTrades'] as List? ?? []).cast<Map<String, dynamic>>();
      return _parseTrades(rawTrades,
          buyAddrPath: ['Trade', 'Buy', 'Account', 'Address'],
          sellAddrPath: ['Trade', 'Sell', 'Account', 'Address'],
          amountPath: ['Trade', 'Buy', 'AmountInUSD']);
    } on DioException catch (e) {
      _log.fine('Bitquery Solana trades failed: ${e.response?.statusCode}');
      return null;
    }
  }

  Future<_HoldersResult?> _querySolanaHolders(String mintAddress, String token) async {
    const query = r'''
query SolanaHolders($mint: String!) {
  Solana {
    BalanceUpdates(
      where: { BalanceUpdate: { Currency: { MintAddress: { is: $mint } } } }
      orderBy: { descendingByField: "BalanceUpdate_Amount" }
      limit: { count: 20 }
    ) {
      BalanceUpdate { Account { Address } Amount AmountInUSD }
    }
  }
}
''';

    try {
      final response = await _gql(query, {'mint': mintAddress}, token);
      final updates =
          (response?['data']?['Solana']?['BalanceUpdates'] as List? ?? []).cast<Map<String, dynamic>>();
      return _parseHolders(updates, amountPath: ['BalanceUpdate', 'AmountInUSD']);
    } on DioException catch (e) {
      _log.fine('Bitquery Solana holders failed: ${e.response?.statusCode}');
      return null;
    }
  }

  // ── EVM (Ethereum / BNB / Base) ────────────────────────────────────────────

  Future<({OnChainData data, List<IntelligenceFlag> flags})?> _analyzeEvm(
    String contractAddress,
    String networkId,
    String chainLabel,
    String token,
  ) async {
    final trades = await _queryEvmTrades(contractAddress, networkId, token);

    _log.info('Bitquery $chainLabel: trades=${trades?.totalTrades} '
        'uniqueBuyers=${trades?.uniqueBuyers} '
        'washWallets=${trades?.washTradingWalletCount}');

    return _buildResult(trades, null);
  }

  Future<_TradesResult?> _queryEvmTrades(
    String contractAddress,
    String networkId,
    String token,
  ) async {
    // EVM namespace uses Buyer/Seller (not nested Account.Address like Solana)
    const query = r'''
query EvmTrades($token: String!, $network: evm_network!) {
  EVM(network: $network) {
    DEXTrades(
      where: {
        Trade: { Buy: { Currency: { SmartContract: { is: $token } } } }
        Transaction: { Status: { Success: true } }
      }
      limit: { count: 200 }
      orderBy: { descending: Block_Time }
    ) {
      Trade {
        Buy  { Buyer  Amount AmountInUSD Currency { Symbol } }
        Sell { Seller }
        Dex  { ProtocolName }
      }
    }
  }
}
''';

    try {
      final response = await _gql(query, {'token': contractAddress, 'network': networkId}, token);
      final rawTrades =
          (response?['data']?['EVM']?['DEXTrades'] as List? ?? []).cast<Map<String, dynamic>>();

      if (rawTrades.isEmpty) return null;

      final buyerAddresses = <String>{};
      final sellerAddresses = <String>{};
      double totalVolume = 0;

      for (final t in rawTrades) {
        final trade = t['Trade'] as Map<String, dynamic>? ?? {};
        final buyAddr = trade['Buy']?['Buyer'] as String?;
        final sellAddr = trade['Sell']?['Seller'] as String?;
        final amountUsd = _toDouble(trade['Buy']?['AmountInUSD']);
        if (buyAddr != null) buyerAddresses.add(buyAddr.toLowerCase());
        if (sellAddr != null) sellerAddresses.add(sellAddr.toLowerCase());
        totalVolume += amountUsd;
      }

      final washWallets = buyerAddresses.intersection(sellerAddresses);

      return _TradesResult(
        totalTrades: rawTrades.length,
        uniqueBuyers: buyerAddresses.length,
        uniqueSellers: sellerAddresses.length,
        washTradingWalletCount: washWallets.length,
        totalVolumeUsd: totalVolume,
        avgTradeUsd: rawTrades.isEmpty ? 0 : totalVolume / rawTrades.length,
      );
    } on DioException catch (e) {
      _log.fine('Bitquery EVM trades failed: ${e.response?.statusCode} ${e.message}');
      return null;
    }
  }

  // ── SHARED HELPERS ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _gql(
    String query,
    Map<String, dynamic> variables,
    String token,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      _graphqlUrl,
      data: jsonEncode({'query': query, 'variables': variables}),
      options: Options(headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }),
    );
    return response.data;
  }

  _TradesResult? _parseTrades(
    List<Map<String, dynamic>> rawTrades, {
    required List<String> buyAddrPath,
    required List<String> sellAddrPath,
    required List<String> amountPath,
  }) {
    if (rawTrades.isEmpty) return null;

    final buyerAddresses = <String>{};
    final sellerAddresses = <String>{};
    double totalVolume = 0;

    for (final t in rawTrades) {
      final buyAddr = _dig(t, buyAddrPath) as String?;
      final sellAddr = _dig(t, sellAddrPath) as String?;
      final amountUsd = _toDouble(_dig(t, amountPath));
      if (buyAddr != null) buyerAddresses.add(buyAddr);
      if (sellAddr != null) sellerAddresses.add(sellAddr);
      totalVolume += amountUsd;
    }

    final washWallets = buyerAddresses.intersection(sellerAddresses);

    return _TradesResult(
      totalTrades: rawTrades.length,
      uniqueBuyers: buyerAddresses.length,
      uniqueSellers: sellerAddresses.length,
      washTradingWalletCount: washWallets.length,
      totalVolumeUsd: totalVolume,
      avgTradeUsd: rawTrades.isEmpty ? 0 : totalVolume / rawTrades.length,
    );
  }

  _HoldersResult? _parseHolders(
    List<Map<String, dynamic>> updates, {
    required List<String> amountPath,
  }) {
    if (updates.isEmpty) return null;
    double total = 0;
    final amounts = <double>[];
    for (final u in updates) {
      final v = _toDouble(_dig(u, amountPath));
      total += v;
      amounts.add(v);
    }
    return _HoldersResult(holderCount: updates.length, totalHeldUsd: total, holderAmountsUsd: amounts);
  }

  /// Walk a nested map along [path], returning null if any key is missing.
  dynamic _dig(Map<String, dynamic> map, List<String> path) {
    dynamic current = map;
    for (final key in path) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Safely coerce a value from Bitquery to double.
  /// Bitquery sometimes returns numeric fields as JSON strings — handle both.
  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  // ── RESULT BUILDER ─────────────────────────────────────────────────────────

  ({OnChainData data, List<IntelligenceFlag> flags}) _buildResult(
    _TradesResult? trades,
    _HoldersResult? holders,
  ) {
    final flags = <IntelligenceFlag>[];
    int clusterCount = 0;
    int suspiciousCount = 0;
    bool isWashTrading = false;

    if (trades != null && trades.totalTrades > 0) {
      // Few unique buyers behind many trades = bots
      final buyerRatio = trades.uniqueBuyers / trades.totalTrades;
      if (trades.totalTrades >= 20 && buyerRatio < 0.1) {
        isWashTrading = true;
        flags.add(IntelligenceFlag(
          source: 'Bitquery',
          severity: FlagSeverity.high,
          message:
              'Only ${trades.uniqueBuyers} unique buyers behind ${trades.totalTrades} trades '
              '(${(buyerRatio * 100).toStringAsFixed(0)}% ratio) — likely bot/wash activity',
        ));
      }

      // Same wallets on both sides = coordinated wash trading
      if (trades.washTradingWalletCount > 3) {
        isWashTrading = true;
        suspiciousCount = trades.washTradingWalletCount;
        flags.add(IntelligenceFlag(
          source: 'Bitquery',
          severity: FlagSeverity.high,
          message:
              '${trades.washTradingWalletCount} wallets appear on BOTH sides of trades — '
              'coordinated wash trading pattern',
        ));
      }

      clusterCount = trades.washTradingWalletCount;
    }

    return (
      data: OnChainData(
        walletClusterCount: clusterCount,
        suspiciousClusterCount: suspiciousCount,
        deployerFundingSource: null,
        isWashTrading: isWashTrading,
        uniqueBuyersCount: trades?.uniqueBuyers,
        avgTransactionSizeUsd: trades?.avgTradeUsd,
      ),
      flags: flags,
    );
  }
}

// ── INTERNAL DATA CLASSES ──────────────────────────────────────────────────

class _TradesResult {
  final int totalTrades;
  final int uniqueBuyers;
  final int uniqueSellers;
  final int washTradingWalletCount;
  final double totalVolumeUsd;
  final double avgTradeUsd;

  const _TradesResult({
    required this.totalTrades,
    required this.uniqueBuyers,
    required this.uniqueSellers,
    required this.washTradingWalletCount,
    required this.totalVolumeUsd,
    required this.avgTradeUsd,
  });
}

class _HoldersResult {
  final int holderCount;
  final double totalHeldUsd;
  final List<double> holderAmountsUsd;

  const _HoldersResult({
    required this.holderCount,
    required this.totalHeldUsd,
    required this.holderAmountsUsd,
  });
}
