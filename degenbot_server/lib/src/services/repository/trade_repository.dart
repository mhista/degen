// trade_repository.dart
//
// All database read/write operations for Trade records.
// Also handles the RiskProfile table since risk decisions are
// inherently trade-count-aware.

import 'package:logging/logging.dart';
import 'package:degenbot_server/src/generated/protocol.dart';
import 'package:degenbot_server/src/services/dto/trade_dto.dart';
import 'supabase_client.dart';

final _log = Logger('TradeRepository');
const _dto = TradeDto();

class TradeRepository {
  const TradeRepository();

  // ── TRADES ────────────────────────────────────────────────────────────────

  /// Create a new trade record (status: 'open').
  Future<Trade> createTrade(Trade trade) async {
    _log.info('Creating trade userId=${trade.userId} symbol=${trade.symbol}');
    final row = _dto.toRow(trade, includeId: false);
    row['created_at'] = DateTime.now().toUtc().toIso8601String();

    final response = await supabase
        .from('trades')
        .insert(row)
        .select()
        .single();

    return _dto.fromRow(response);
  }

  /// Close a trade — sets sell price, PnL, ROI, and status.
  Future<Trade> closeTrade({
    required int tradeId,
    required double sellPriceUsd,
    required String sellTxHash,
    required String closeReason, // 'take_profit' | 'stop_loss' | 'manual'
    required double realizedPnlUsd,
    required double roiPercent,
  }) async {
    _log.info('Closing trade id=$tradeId reason=$closeReason');
    final now = DateTime.now().toUtc().toIso8601String();

    final response = await supabase
        .from('trades')
        .update({
          'sell_price_usd': sellPriceUsd,
          'sell_tx_hash': sellTxHash,
          'sold_at': now,
          'close_reason': closeReason,
          'realized_pnl_usd': realizedPnlUsd,
          'roi_percent': roiPercent,
          'status': 'closed',
          'updated_at': now,
        })
        .eq('id', tradeId)
        .select()
        .single();

    return _dto.fromRow(response);
  }

  /// Get all open trades for a user (for the price monitor to watch).
  Future<List<Trade>> getOpenTrades(int userId) async {
    final response = await supabase
        .from('trades')
        .select()
        .eq('user_id', userId)
        .eq('status', 'open')
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => _dto.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Get all open trades across ALL users (for the global price monitor loop).
  Future<List<Trade>> getAllOpenTrades() async {
    final response = await supabase
        .from('trades')
        .select()
        .eq('status', 'open')
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => _dto.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Trade history for a user (last N trades, closed only).
  Future<List<Trade>> getTradeHistory(int userId, {int limit = 20}) async {
    final response = await supabase
        .from('trades')
        .select()
        .eq('user_id', userId)
        .eq('status', 'closed')
        .order('sold_at', ascending: false)
        .limit(limit);

    return (response as List)
        .map((row) => _dto.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Count trades executed today for a user (for daily limit enforcement).
  Future<int> countTradesToday(int userId) async {
    final todayStart = DateTime.now().toUtc().copyWith(
          hour: 0,
          minute: 0,
          second: 0,
          millisecond: 0,
          microsecond: 0,
        );

    final response = await supabase
        .from('trades')
        .select('id') // only fetch id column for count
        .eq('user_id', userId)
        .gte('created_at', todayStart.toIso8601String());

    return (response as List).length;
  }

  // ── RISK PROFILES ─────────────────────────────────────────────────────────

  /// Get or create a default risk profile for a user.
  Future<RiskProfile> getRiskProfile(int userId) async {
    final response = await supabase
        .from('risk_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response != null) {
      return _riskProfileFromRow(response);
    }

    // Create a default profile for new users
    return _createDefaultRiskProfile(userId);
  }

  Future<RiskProfile> _createDefaultRiskProfile(int userId) async {
    _log.info('Creating default risk profile for userId=$userId');
    final now = DateTime.now().toUtc();
    final row = {
      'user_id': userId,
      'max_trade_percent': 5.0,    // risk max 5% of balance per trade
      'daily_trade_limit': 10,     // max 10 trades per day on free tier
      'trades_today': 0,
      'default_take_profit_percent': 50.0, // sell at +50%
      'default_stop_loss_percent': 20.0,   // cut loss at -20%
      'last_reset_date': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    final response = await supabase
        .from('risk_profiles')
        .insert(row)
        .select()
        .single();

    return _riskProfileFromRow(response);
  }

  Future<RiskProfile> updateRiskProfile(RiskProfile profile) async {
    final response = await supabase
        .from('risk_profiles')
        .update({
          'max_trade_percent': profile.maxTradePercent,
          'daily_trade_limit': profile.dailyTradeLimit,
          'trades_today': profile.tradesToday,
          'default_take_profit_percent': profile.defaultTakeProfitPercent,
          'default_stop_loss_percent': profile.defaultStopLossPercent,
          'last_reset_date': profile.lastResetDate.toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', profile.userId)
        .select()
        .single();

    return _riskProfileFromRow(response);
  }

  // ── PRIVATE HELPERS ───────────────────────────────────────────────────────

  RiskProfile _riskProfileFromRow(Map<String, dynamic> row) {
    return RiskProfile(
      id: row['id'] as int?,
      userId: row['user_id'] as int,
      maxTradePercent: (row['max_trade_percent'] as num).toDouble(),
      dailyTradeLimit: row['daily_trade_limit'] as int,
      tradesToday: row['trades_today'] as int,
      defaultTakeProfitPercent:
          (row['default_take_profit_percent'] as num).toDouble(),
      defaultStopLossPercent:
          (row['default_stop_loss_percent'] as num).toDouble(),
      lastResetDate: DateTime.parse(row['last_reset_date'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
