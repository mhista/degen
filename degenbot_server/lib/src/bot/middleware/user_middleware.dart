// user_middleware.dart
//
// Middleware that runs before every Telegram update.
//
// WHAT MIDDLEWARE IS (plain English):
//   Think of it as a security guard at the door.
//   Before any message reaches your command handlers or AI,
//   this code runs first. It checks: "Do we know this person?"
//   If yes → let them through.
//   If no  → register them first, then let them through.
//
// WHY THIS MATTERS:
//   Every handler can now call `_users.findByTelegramId(id)` and
//   KNOW the user exists. No null checks in every handler.
//   It also means new users get registered silently just by
//   messaging the bot — no separate /register step.

import 'package:degenbot_server/src/generated/protocol.dart';
import 'package:degenbot_server/src/services/repository/user_repository.dart';
import 'package:logging/logging.dart';
import 'package:televerse/televerse.dart';

final _log = Logger('UserMiddleware');

class UserMiddleware {
  const UserMiddleware();
  final _users = const UserRepository();

  Future<void> handle(Context ctx, NextFunction next) async {
    final telegramUser = ctx.update.message?.from
        ?? ctx.update.callbackQuery?.from;

    if (telegramUser == null) {
      // Non-user update (e.g. channel post) — pass through
      await next();
      return;
    }

    final telegramId = telegramUser.id;
    final username = telegramUser.username;

    try {
      // Check if user exists; create if not
      final existing = await _users.findByTelegramId(telegramId);

      if (existing == null) {
        _log.info('New user — registering telegramId=$telegramId @$username');
        final now = DateTime.now().toUtc();
        await _users.create(User(
          telegramId: telegramId,
          telegramUsername: username,
          activeChain: 'solana',
          walletAddress: null,
          subscriptionTier: 'free',
          isBotActive: false,
          createdAt: now,
          updatedAt: now,
        ));
      }
    } catch (e, st) {
      // Log but don't block — user can still interact even if DB write fails
      _log.warning('UserMiddleware DB error for $telegramId', e, st);
    }

    // Always continue to the next handler
    await next();
  }
}
