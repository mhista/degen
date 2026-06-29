// token_cache_service.dart
//
// PLAIN ENGLISH — WHAT THIS DOES:
//   Once we've analyzed a token and decided it's safe (or not), we
//   never want to run the full 5-layer pipeline on it again. That's
//   wasted API calls, wasted money, and wasted time.
//
//   This service keeps a simple in-memory set of every contract address
//   that has already been analyzed. When the scanner loop finds a token,
//   the pipeline checks here FIRST — if it's already in the cache,
//   the whole analysis is skipped.
//
// WHY IN-MEMORY (and not Supabase):
//   Speed. The scanner runs every few hours and might see hundreds of
//   tokens. Checking a HashSet in memory is nanoseconds. A Supabase
//   query is milliseconds over the network.
//
//   The tradeoff: the cache resets on server restart. This is acceptable
//   for now — on restart, tokens that were already analyzed will be
//   analyzed again once, then cached again. Not a big deal.
//
// FUTURE: when the coin_candidates table is populated, we can seed the
//   in-memory cache from Supabase on startup so restarts don't cause
//   re-analysis. The hook for that is preloadFromDatabase().
//
// ANALYST OVERRIDE:
//   The analyst (or user) can manually force a re-analysis with
//   /reanalyze <address>. This evicts the address from the cache so
//   the next encounter runs the full pipeline again.

import 'package:degenbot_server/degen_logger.dart';

/// The verdict we stored when we first analyzed this token.
/// We save this alongside the address so we can answer "what did we
/// think of this coin?" without re-running the pipeline.
class CachedTokenResult {
  const CachedTokenResult({
    required this.contractAddress,
    required this.chain,
    required this.tokenSymbol,
    required this.verdictLabel,   // 'buyCandidate' | 'watchOnly' | 'rejected' | 'abandoned'
    required this.reason,
    required this.analyzedAt,
  });

  final String contractAddress;
  final String chain;
  final String tokenSymbol;
  final String verdictLabel;
  final String reason;
  final DateTime analyzedAt;

  bool get wasRejected =>
      verdictLabel == 'rejected' || verdictLabel == 'abandoned';

  bool get wasBuyCandidate => verdictLabel == 'buyCandidate';
}

class TokenCacheService {
  // Singleton — the scanner loop and the Telegram handlers both use this.
  static final TokenCacheService instance = TokenCacheService._();
  TokenCacheService._();

  // The cache. Key = contractAddress (lowercase for case-insensitive match).
  final Map<String, CachedTokenResult> _cache = {};

  // ── PUBLIC API ────────────────────────────────────────────────────────────

  /// Returns true if this address has already been analyzed.
  bool isAnalyzed(String contractAddress) =>
      _cache.containsKey(contractAddress.toLowerCase());

  /// Returns the cached result for an address, or null if not cached.
  CachedTokenResult? get(String contractAddress) =>
      _cache[contractAddress.toLowerCase()];

  /// Record the result of a completed analysis.
  void record({
    required String contractAddress,
    required String chain,
    required String tokenSymbol,
    required String verdictLabel,
    required String reason,
  }) {
    final key = contractAddress.toLowerCase();
    _cache[key] = CachedTokenResult(
      contractAddress: contractAddress,
      chain: chain,
      tokenSymbol: tokenSymbol,
      verdictLabel: verdictLabel,
      reason: reason,
      analyzedAt: DateTime.now().toUtc(),
    );
    Log.info(
      '💾 [TokenCache] Recorded $tokenSymbol ($contractAddress) → $verdictLabel',
    );
  }

  /// Force re-analysis of an address (user command or error recovery).
  void evict(String contractAddress) {
    final key = contractAddress.toLowerCase();
    final removed = _cache.remove(key);
    if (removed != null) {
      Log.info(
        '🗑️ [TokenCache] Evicted ${removed.tokenSymbol} ($contractAddress) — will re-analyze on next encounter',
      );
    }
  }

  /// Clear the entire cache (e.g., for testing or full rescan).
  void clear() {
    final count = _cache.length;
    _cache.clear();
    Log.warning('🗑️ [TokenCache] Cache cleared — $count entries removed');
  }

  /// Stats for the /status command.
  int get size => _cache.length;

  int get rejectedCount =>
      _cache.values.where((r) => r.wasRejected).length;

  int get candidateCount =>
      _cache.values.where((r) => r.wasBuyCandidate).length;

  /// Returns all buy candidates (addresses the rule engine approved).
  List<CachedTokenResult> get buyCandidates =>
      _cache.values.where((r) => r.wasBuyCandidate).toList();

  /// Returns all watchlist tokens.
  List<CachedTokenResult> get watchlist =>
      _cache.values
          .where((r) => r.verdictLabel == 'watchOnly')
          .toList();

  // ── FUTURE: SEED FROM DATABASE ────────────────────────────────────────────
  //
  // When coin_candidates table is populated, call this on server startup
  // to avoid re-analyzing known tokens after a restart:
  //
  // Future<void> preloadFromDatabase(CoinCandidateRepository repo) async {
  //   final known = await repo.getAllAnalyzed();
  //   for (final token in known) {
  //     _cache[token.contractAddress.toLowerCase()] = CachedTokenResult(
  //       contractAddress: token.contractAddress,
  //       chain: token.chain,
  //       tokenSymbol: token.symbol,
  //       verdictLabel: token.verdictLabel,
  //       reason: token.reason,
  //       analyzedAt: token.analyzedAt,
  //     );
  //   }
  //   Log.info('💾 [TokenCache] Preloaded ${_cache.length} entries from database');
  // }
}
