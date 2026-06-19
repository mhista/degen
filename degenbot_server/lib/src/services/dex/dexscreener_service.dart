// dexscreener_service.dart
//
// Wraps the DexScreener public API.
//
// DexScreener API (free, no key needed):
//   https://docs.dexscreener.com/api/reference
//
// ENDPOINTS WE USE:
//   GET /latest/dex/tokens/{address}        → data for one specific token
//   GET /token-boosts/latest/v1             → recently boosted/promoted tokens
//   GET /latest/dex/search?q={query}        → search by name/symbol
//   GET /token-profiles/latest/v1           → latest listed tokens
//
// RATE LIMITS:
//   DexScreener: 300 requests/min on most endpoints.
//   We cache responses to avoid hammering the API.
//
// DATA MODEL RETURNED:
//   The raw DexScreener response is a Map<String, dynamic>.
//   We return it as-is from fetch methods and parse it in the
//   AI scoring service (Step 5). This keeps this service simple
//   and lets the scoring logic evolve independently.

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

final _log = Logger('DexScreenerService');

class DexScreenerService {
  static const _baseUrl = 'https://api.dexscreener.com';
  static const _cacheTimeout = Duration(seconds: 30);

  // Simple in-memory cache: url → (data, timestamp)
  final Map<String, (List<Map<String, dynamic>>, DateTime)> _cache = {};

  late final Dio _dio;

   DexScreenerService() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ));
  }

  // ── PUBLIC METHODS ────────────────────────────────────────────────────────

  /// Fetch data for a specific token by contract address.
  /// Returns a list of pairs (a token can trade on multiple DEXes).
  Future<List<Map<String, dynamic>>> getTokenData({
    required String contractAddress,
    required String chain,
  }) async {
    final url = '/latest/dex/tokens/$contractAddress';
    return _cachedGet(url, chain: chain);
  }

  /// Fetch recently boosted/trending tokens from DexScreener.
  /// These are tokens that have been actively promoted — often high volume.
  Future<List<Map<String, dynamic>>> getTrendingCoins({
    required String chain,
    int limit = 20,
  }) async {
    _log.fine('Fetching trending coins for $chain');
    final url = '/token-boosts/latest/v1';
    final all = await _cachedGet(url);

    // Filter by chain and cap at limit
    final filtered = all
        .where((coin) =>
            (coin['chainId'] as String?)?.toLowerCase() ==
            _chainToId(chain))
        .take(limit)
        .toList();

    // For each boosted token, fetch full pair data
    final enriched = <Map<String, dynamic>>[];
    for (final boosted in filtered.take(10)) {
      // Cap at 10 to avoid too many requests
      final address = boosted['tokenAddress'] as String?;
      if (address == null) continue;
      try {
        final pairs = await getTokenData(
          contractAddress: address,
          chain: chain,
        );
        if (pairs.isNotEmpty) enriched.add(pairs.first);
      } catch (_) {
        // Skip tokens that fail to load
      }
    }

    return enriched;
  }

  /// Search DexScreener for tokens by name or symbol.
  Future<List<Map<String, dynamic>>> searchTokens({
    required String query,
    String? chain,
  }) async {
    _log.fine('Searching DexScreener: "$query"');
    final url = '/latest/dex/search?q=${Uri.encodeComponent(query)}';

    try {
      final response = await _dio.get<Map<String, dynamic>>(url);
      final pairs = (response.data?['pairs'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      if (chain != null) {
        return pairs
            .where((p) =>
                (p['chainId'] as String?)?.toLowerCase() == _chainToId(chain))
            .toList();
      }
      return pairs;
    } catch (e) {
      _log.warning('DexScreener search failed: $e');
      return [];
    }
  }

  /// Fetch the latest token profiles (newly listed tokens).
  /// Useful for sniping new launches.
  Future<List<Map<String, dynamic>>> getLatestTokenProfiles({
    required String chain,
  }) async {
    _log.fine('Fetching latest token profiles for $chain');
    final url = '/token-profiles/latest/v1';
    final all = await _cachedGet(url);
    return all
        .where((t) =>
            (t['chainId'] as String?)?.toLowerCase() == _chainToId(chain))
        .toList();
  }

  // ── PARSING HELPERS ───────────────────────────────────────────────────────

  /// Extract a numeric price from a DexScreener pair object.
  /// Returns null if not available.
  static double? parsePriceUsd(Map<String, dynamic> pair) {
    final raw = pair['priceUsd'] as String?;
    return raw != null ? double.tryParse(raw) : null;
  }

  /// Extract liquidity in USD.
  static double? parseLiquidityUsd(Map<String, dynamic> pair) {
    final liquidity = pair['liquidity'] as Map<String, dynamic>?;
    return (liquidity?['usd'] as num?)?.toDouble();
  }

  /// Extract 24h volume in USD.
  static double? parseVolume24h(Map<String, dynamic> pair) {
    final volume = pair['volume'] as Map<String, dynamic>?;
    return (volume?['h24'] as num?)?.toDouble();
  }

  /// Extract 24h price change percentage.
  static double? parsePriceChange24h(Map<String, dynamic> pair) {
    final changes = pair['priceChange'] as Map<String, dynamic>?;
    return (changes?['h24'] as num?)?.toDouble();
  }

  /// Extract 1h price change percentage.
  static double? parsePriceChange1h(Map<String, dynamic> pair) {
    final changes = pair['priceChange'] as Map<String, dynamic>?;
    return (changes?['h1'] as num?)?.toDouble();
  }

  // ── PRIVATE HELPERS ───────────────────────────────────────────────────────

  /// Cached GET — returns cached result if still fresh.
  Future<List<Map<String, dynamic>>> _cachedGet(
    String url, {
    String? chain,
  }) async {
    final cacheKey = '$url|$chain';
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.$2) < _cacheTimeout) {
      _log.fine('Cache hit: $cacheKey');
      return cached.$1;
    }

    _log.fine('GET $url');
    try {
      final response = await _dio.get<dynamic>(url);
      final data = response.data;

      List<Map<String, dynamic>> result;
      if (data is List) {
        result = data.cast<Map<String, dynamic>>();
      } else if (data is Map) {
        // DexScreener wraps pair results in {"pairs": [...]}
        result = ((data['pairs'] as List?) ?? []).cast<Map<String, dynamic>>();
      } else {
        result = [];
      }

      _cache[cacheKey] = (result, DateTime.now());
      return result;
    } on DioException catch (e) {
      _log.warning('DexScreener request failed [$url]: ${e.message}');
      return [];
    }
  }

  /// Map our chain name to DexScreener's chainId format.
  String _chainToId(String chain) => switch (chain) {
        'bnb' => 'bsc',  // DexScreener uses 'bsc' for BNB Chain
        _ => chain,      // 'solana', 'ethereum' match directly
      };
}
