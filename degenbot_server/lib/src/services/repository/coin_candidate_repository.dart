// coin_candidate_repository.dart
//
// All database read/write operations for CoinCandidate records.
//
// PLAIN ENGLISH — WHY THIS EXISTS:
//   When the auto-scanner finds a buy (or watch) candidate, we save it
//   to the coin_candidates table. This lets us:
//     - Skip tokens we've already processed (no re-analysis)
//     - Show the user a history of what the scanner found (/history)
//     - Track conversion: pending → bought → closed
//
// TABLE: coin_candidates (see docs/migrations/001_initial_schema.sql)
//
// DEDUPLICATION:
//   The table has a unique constraint on (contract_address, chain).
//   We use UPSERT (on_conflict: update) so re-scanning the same token
//   refreshes the data rather than failing with a duplicate key error.

import 'package:logging/logging.dart';
import 'package:degenbot_server/src/generated/protocol.dart';
import 'package:degenbot_server/src/services/dto/coin_candidate_dto.dart';
import 'supabase_client.dart';

final _log = Logger('CoinCandidateRepository');
const _dto = CoinCandidateDto();

class CoinCandidateRepository {
  const CoinCandidateRepository();

  // ── WRITE ─────────────────────────────────────────────────────────────────

  /// Insert or update a coin candidate.
  /// The unique constraint is on (contract_address, chain), so re-scanning
  /// the same token refreshes the price/score data rather than inserting a
  /// duplicate row.
  Future<CoinCandidate> upsert(CoinCandidate candidate) async {
    _log.info(
      'Upserting candidate ${candidate.symbol} (${candidate.contractAddress}) '
      'chain=${candidate.chain} status=${candidate.status}',
    );
    final row = _dto.toRow(candidate, includeId: false);
    row['scanned_at'] = DateTime.now().toUtc().toIso8601String();

    final response = await supabase
        .from('coin_candidates')
        .upsert(row, onConflict: 'contract_address,chain')
        .select()
        .single();

    return _dto.fromRow(response);
  }

  /// Mark a candidate as bought (called when a trade is opened for it).
  Future<void> markAsBought(int id) async {
    _log.info('Marking coin_candidate id=$id as bought');
    await supabase
        .from('coin_candidates')
        .update({'status': 'bought'})
        .eq('id', id);
  }

  /// Mark a candidate as rejected (e.g. user dismissed it).
  Future<void> markAsRejected(int id) async {
    await supabase
        .from('coin_candidates')
        .update({'status': 'rejected'})
        .eq('id', id);
  }

  // ── READ ──────────────────────────────────────────────────────────────────

  /// Check if a token has already been saved (regardless of status).
  /// Used to avoid re-notifying about a token the scanner already flagged.
  Future<CoinCandidate?> findByAddress(
    String contractAddress,
    String chain,
  ) async {
    _log.fine('findByAddress $contractAddress chain=$chain');
    final response = await supabase
        .from('coin_candidates')
        .select()
        .eq('contract_address', contractAddress)
        .eq('chain', chain)
        .maybeSingle();

    if (response == null) return null;
    return _dto.fromRow(response);
  }

  /// Get buy candidates (status='pending' means flagged by scanner but not
  /// yet acted on). Optionally filter by chain.
  Future<List<CoinCandidate>> getPendingBuyCandidates({
    String? chain,
    int limit = 20,
  }) async {
    _log.fine('getPendingBuyCandidates chain=$chain limit=$limit');

    var query = supabase
        .from('coin_candidates')
        .select()
        .eq('status', 'pending');

    if (chain != null) {
      query = query.eq('chain', chain);
    }

    final response = await query
        .order('ai_score', ascending: false)
        .limit(limit);

    return (response as List)
        .map((row) => _dto.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Recent scan history — all statuses, newest first.
  Future<List<CoinCandidate>> getRecentScans({
    String? chain,
    int limit = 50,
  }) async {
    var query = supabase
        .from('coin_candidates')
        .select();

    if (chain != null) {
      query = query.eq('chain', chain);
    }

    final response = await query
        .order('scanned_at', ascending: false)
        .limit(limit);

    return (response as List)
        .map((row) => _dto.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Count how many tokens were scanned today.
  Future<int> countScannedToday() async {
    final todayStart = DateTime.now().toUtc().copyWith(
      hour: 0,
      minute: 0,
      second: 0,
      millisecond: 0,
      microsecond: 0,
    );

    final response = await supabase
        .from('coin_candidates')
        .select('id')
        .gte('scanned_at', todayStart.toIso8601String());

    return (response as List).length;
  }
}
