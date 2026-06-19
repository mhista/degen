// trade_endpoint.dart
//
// Serverpod endpoint for trade-related operations.
//
// Exposed to:
//   • Telegram bot (internal calls)
//   • Flutter app (via generated client over HTTP — later)
//
// IMPORTANT: No actual blockchain execution happens here.
//   This endpoint is purely data — read/write trade records.
//   Blockchain execution lives in services/chain/
//   The bot orchestrates: endpoint → chain service → endpoint (record result)

import 'package:serverpod/serverpod.dart';
import 'package:degenbot_server/src/generated/protocol.dart';
import 'package:degenbot_server/src/services/repository/trade_repository.dart';
import 'package:degenbot_server/src/services/repository/user_repository.dart';

class TradeEndpoint extends Endpoint {
  final _trades = const TradeRepository();
  final _users = const UserRepository();

  // ── HISTORY ───────────────────────────────────────────────────────────────

  /// Last N closed trades for a user — shown in /history command.
  Future<List<Trade>> getHistory(
    Session session,
    int telegramId, {
    int limit = 10,
  }) async {
    final user = await _users.findByTelegramId(telegramId);
    if (user == null) throw Exception('User not found');
    return _trades.getTradeHistory(user.id!, limit: limit);
  }

  /// Open positions — shown in /positions command.
  Future<List<Trade>> getOpenPositions(
    Session session,
    int telegramId,
  ) async {
    final user = await _users.findByTelegramId(telegramId);
    if (user == null) throw Exception('User not found');
    return _trades.getOpenTrades(user.id!);
  }

  // ── RISK PROFILE ──────────────────────────────────────────────────────────

  /// Get the user's current risk settings — shown in /risk command.
  Future<RiskProfile> getRiskProfile(
    Session session,
    int telegramId,
  ) async {
    final user = await _users.findByTelegramId(telegramId);
    if (user == null) throw Exception('User not found');
    return _trades.getRiskProfile(user.id!);
  }

  /// Update a single risk setting.
  /// field: 'max_trade_percent' | 'daily_trade_limit' |
  ///        'take_profit_percent' | 'stop_loss_percent'
  Future<RiskProfile> updateRiskSetting(
    Session session,
    int telegramId,
    String field,
    double value,
  ) async {
    final user = await _users.findByTelegramId(telegramId);
    if (user == null) throw Exception('User not found');

    final profile = await _trades.getRiskProfile(user.id!);

    // Build updated profile — only change the requested field
    final updated = switch (field) {
      'max_trade_percent' => RiskProfile(
          id: profile.id,
          userId: profile.userId,
          maxTradePercent: value.clamp(1, 100),
          dailyTradeLimit: profile.dailyTradeLimit,
          tradesToday: profile.tradesToday,
          defaultTakeProfitPercent: profile.defaultTakeProfitPercent,
          defaultStopLossPercent: profile.defaultStopLossPercent,
          lastResetDate: profile.lastResetDate,
          updatedAt: DateTime.now().toUtc(),
        ),
      'daily_trade_limit' => RiskProfile(
          id: profile.id,
          userId: profile.userId,
          maxTradePercent: profile.maxTradePercent,
          dailyTradeLimit: value.toInt().clamp(1, 100),
          tradesToday: profile.tradesToday,
          defaultTakeProfitPercent: profile.defaultTakeProfitPercent,
          defaultStopLossPercent: profile.defaultStopLossPercent,
          lastResetDate: profile.lastResetDate,
          updatedAt: DateTime.now().toUtc(),
        ),
      'take_profit_percent' => RiskProfile(
          id: profile.id,
          userId: profile.userId,
          maxTradePercent: profile.maxTradePercent,
          dailyTradeLimit: profile.dailyTradeLimit,
          tradesToday: profile.tradesToday,
          defaultTakeProfitPercent: value.clamp(1, 1000),
          defaultStopLossPercent: profile.defaultStopLossPercent,
          lastResetDate: profile.lastResetDate,
          updatedAt: DateTime.now().toUtc(),
        ),
      'stop_loss_percent' => RiskProfile(
          id: profile.id,
          userId: profile.userId,
          maxTradePercent: profile.maxTradePercent,
          dailyTradeLimit: profile.dailyTradeLimit,
          tradesToday: profile.tradesToday,
          defaultTakeProfitPercent: profile.defaultTakeProfitPercent,
          defaultStopLossPercent: value.clamp(1, 99),
          lastResetDate: profile.lastResetDate,
          updatedAt: DateTime.now().toUtc(),
        ),
      _ => throw ArgumentError('Unknown risk field: $field'),
    };

    return _trades.updateRiskProfile(updated);
  }

  // ── SUMMARY STATS ─────────────────────────────────────────────────────────

  /// ROI summary — total PnL, win rate, best/worst trade.
  /// Used by /stats command.
  Future<Map<String, dynamic>> getSummaryStats(
    Session session,
    int telegramId,
  ) async {
    final user = await _users.findByTelegramId(telegramId);
    if (user == null) throw Exception('User not found');

    final history = await _trades.getTradeHistory(user.id!, limit: 100);

    if (history.isEmpty) {
      return {
        'total_trades': 0,
        'total_pnl_usd': 0.0,
        'win_rate_percent': 0.0,
        'best_roi_percent': 0.0,
        'worst_roi_percent': 0.0,
      };
    }

    final wins = history.where((t) => (t.realizedPnlUsd ?? 0) > 0).toList();
    final totalPnl = history.fold<double>(
      0,
      (sum, t) => sum + (t.realizedPnlUsd ?? 0),
    );
    final rois = history
        .map((t) => t.roiPercent ?? 0)
        .where((r) => r != 0)
        .toList();

    return {
      'total_trades': history.length,
      'total_pnl_usd': totalPnl,
      'win_rate_percent':
          history.isEmpty ? 0 : (wins.length / history.length) * 100,
      'best_roi_percent': rois.isEmpty ? 0 : rois.reduce((a, b) => a > b ? a : b),
      'worst_roi_percent': rois.isEmpty ? 0 : rois.reduce((a, b) => a < b ? a : b),
    };
  }
}
