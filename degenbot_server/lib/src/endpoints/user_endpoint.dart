// user_endpoint.dart
//
// Serverpod endpoint for user-related operations.
//
// These methods are exposed to:
//   • The Telegram bot (calls them internally, same process)
//   • The Flutter app (calls them via generated client over HTTP)
//
// SESSION NOTE:
//   In Serverpod Mini, Session carries request context.
//   We don't use Serverpod auth here — authentication is via Telegram
//   (the bot verifies the Telegram user before calling these methods).
//   The Flutter app will use a JWT issued after Telegram auth.

import 'package:serverpod/serverpod.dart';
import 'package:degenbot_server/src/generated/protocol.dart';
import 'package:degenbot_server/src/services/repository/user_repository.dart';
import 'package:degenbot_server/src/services/repository/trade_repository.dart';

class UserEndpoint extends Endpoint {
  final _users = const UserRepository();
  final _trades = const TradeRepository();

  // ── REGISTRATION ──────────────────────────────────────────────────────────

  /// Called when a Telegram user sends /start for the first time.
  /// Creates the user if they don't exist, returns the user record.
  Future<User> registerOrGet(
    Session session,
    int telegramId,
    String? telegramUsername,
  ) async {
    // Try to find existing user first
    final existing = await _users.findByTelegramId(telegramId);
    if (existing != null) return existing;

    // Create new user with sensible defaults
    final now = DateTime.now().toUtc();
    final newUser = User(
      telegramId: telegramId,
      telegramUsername: telegramUsername,
      activeChain: 'solana',
      walletAddress: null,
      subscriptionTier: 'free',
      isBotActive: false,
      createdAt: now,
      updatedAt: now,
    );

    final created = await _users.create(newUser);

    // Initialise their risk profile with defaults
    await _trades.getRiskProfile(created.id!);

    return created;
  }

  // ── BOT CONTROLS ──────────────────────────────────────────────────────────

  /// Toggle the trading bot on/off for a user.
  Future<bool> setBotActive(
    Session session,
    int telegramId,
    bool active,
  ) async {
    final user = await _users.findByTelegramId(telegramId);
    if (user == null) return false;

    // Safety check: can't start bot without a wallet
    if (active && (user.walletAddress == null || user.walletAddress!.isEmpty)) {
      throw Exception('Set a wallet address before activating the bot.');
    }

    await _users.setBotActive(user.id!, active: active);
    return true;
  }

  // ── WALLET ────────────────────────────────────────────────────────────────

  /// Save the user's public wallet address for the active chain.
  /// NOTE: we NEVER store private keys — only public addresses.
  Future<User> setWalletAddress(
    Session session,
    int telegramId,
    String address,
  ) async {
    final user = await _users.findByTelegramId(telegramId);
    if (user == null) throw Exception('User not found');

    final updated = User(
      id: user.id,
      telegramId: user.telegramId,
      telegramUsername: user.telegramUsername,
      activeChain: user.activeChain,
      walletAddress: address,
      subscriptionTier: user.subscriptionTier,
      isBotActive: user.isBotActive,
      createdAt: user.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );

    return _users.update(updated);
  }

  /// Switch the active blockchain chain.
  Future<User> setActiveChain(
    Session session,
    int telegramId,
    String chain, // 'solana' | 'ethereum' | 'bnb'
  ) async {
    const validChains = ['solana', 'ethereum', 'bnb'];
    if (!validChains.contains(chain)) {
      throw ArgumentError('Invalid chain: $chain. Must be one of $validChains');
    }

    final user = await _users.findByTelegramId(telegramId);
    if (user == null) throw Exception('User not found');

    final updated = User(
      id: user.id,
      telegramId: user.telegramId,
      telegramUsername: user.telegramUsername,
      activeChain: chain,
      walletAddress: null, // clear wallet when switching chains
      subscriptionTier: user.subscriptionTier,
      isBotActive: false,  // stop bot when switching chains
      createdAt: user.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );

    return _users.update(updated);
  }

  // ── DASHBOARD ─────────────────────────────────────────────────────────────

  /// Get a user's full status snapshot for the Telegram dashboard.
  Future<Map<String, dynamic>> getStatus(
    Session session,
    int telegramId,
  ) async {
    final user = await _users.findByTelegramId(telegramId);
    if (user == null) throw Exception('User not found. Send /start first.');

    final openTrades = await _trades.getOpenTrades(user.id!);
    final riskProfile = await _trades.getRiskProfile(user.id!);
    final tradesToday = await _trades.countTradesToday(user.id!);

    return {
      'user': {
        'chain': user.activeChain,
        'wallet': user.walletAddress ?? 'not set',
        'tier': user.subscriptionTier,
        'bot_active': user.isBotActive,
      },
      'open_trades': openTrades.length,
      'trades_today': tradesToday,
      'daily_limit': riskProfile.dailyTradeLimit,
      'max_trade_percent': riskProfile.maxTradePercent,
    };
  }
}
