// user_repository.dart
//
// All database read/write operations for User records.
//
// PATTERN:
//   Every method speaks only in Serverpod model types (User).
//   Supabase JSON is handled entirely inside this file via UserDto.
//   Callers (endpoints, services) never see raw Maps.
//
// ARCHITECTURE NOTE:
//   This is the only place that imports 'supabase_client.dart' for users.
//   If you switch databases later, only this file changes.

import 'package:logging/logging.dart';
import 'package:degenbot_server/src/generated/protocol.dart';
import 'package:degenbot_server/src/services/dto/user_dto.dart';
import 'supabase_client.dart';

final _log = Logger('UserRepository');

// Single shared DTO instance (stateless, safe to reuse)
const _dto = UserDto();

class UserRepository {
  const UserRepository();

  // ── READ ──────────────────────────────────────────────────────────────────

  /// Find a user by their Telegram ID.
  /// Returns null if the user has never used the bot before.
  Future<User?> findByTelegramId(int telegramId) async {
    _log.fine('findByTelegramId($telegramId)');
    final response = await supabase
        .from('users')
        .select()
        .eq('telegram_id', telegramId)
        .maybeSingle(); // returns null instead of throwing if not found

    if (response == null) return null;
    return _dto.fromRow(response);
  }

  /// Find a user by their Supabase integer PK.
  Future<User?> findById(int id) async {
    _log.fine('findById($id)');
    final response = await supabase
        .from('users')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return _dto.fromRow(response);
  }

  // ── WRITE ─────────────────────────────────────────────────────────────────

  /// Create a new user record. Returns the created user with Supabase-assigned id.
  Future<User> create(User user) async {
    _log.info('Creating user telegramId=${user.telegramId}');
    final row = _dto.toRow(user, includeId: false);
    // Add created_at here since the DTO omits it on updates
    row['created_at'] = DateTime.now().toUtc().toIso8601String();

    final response = await supabase
        .from('users')
        .insert(row)
        .select()
        .single(); // throws if insert fails

    return _dto.fromRow(response);
  }

  /// Update an existing user. Matches on id.
  Future<User> update(User user) async {
    _log.info('Updating user id=${user.id}');
    final row = _dto.toRow(user, includeId: false);
    row['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final response = await supabase
        .from('users')
        .update(row)
        .eq('id', user.id!)
        .select()
        .single();

    return _dto.fromRow(response);
  }

  /// Upsert by telegram_id — create if new, update if existing.
  /// This is the main entry point when a Telegram user starts the bot.
  Future<User> upsertByTelegramId(User user) async {
    _log.info('Upserting user telegramId=${user.telegramId}');
    final row = _dto.toRow(user);
    row['created_at'] = DateTime.now().toUtc().toIso8601String();
    row['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final response = await supabase
        .from('users')
        .upsert(row, onConflict: 'telegram_id')
        .select()
        .single();

    return _dto.fromRow(response);
  }

  /// Toggle the bot on or off for a user.
  Future<User> setBotActive(int userId, {required bool active}) async {
    _log.info('setBotActive userId=$userId active=$active');
    final response = await supabase
        .from('users')
        .update({
          'is_bot_active': active,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', userId)
        .select()
        .single();

    return _dto.fromRow(response);
  }
}
