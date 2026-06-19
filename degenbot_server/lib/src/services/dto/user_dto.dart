// user_dto.dart
//
// Translates between:
//   Serverpod model  → User  (degenbot_server/lib/src/generated/user.dart)
//   Supabase row     → Map<String, dynamic>
//
// Supabase table: users
// Schema (run this SQL in Supabase SQL editor — see docs/supabase_schema.sql):
//
//   create table users (
//     id                bigserial primary key,
//     telegram_id       bigint not null unique,
//     telegram_username text,
//     active_chain      text not null default 'solana',
//     wallet_address    text,
//     subscription_tier text not null default 'free',
//     is_bot_active     boolean not null default false,
//     created_at        timestamptz not null default now(),
//     updated_at        timestamptz not null default now()
//   );
//
// NOTE: Supabase uses snake_case column names.
//       Serverpod models use camelCase field names.
//       The DTO handles this mapping explicitly — no magic, no reflection.

import 'package:degenbot_server/src/generated/protocol.dart';
import 'base_dto.dart';

class UserDto extends BaseDto<User> {
  const UserDto();

  @override
  User fromRow(Map<String, dynamic> row) {
    return User(
      id: row['id'] as int?,
      telegramId: row['telegram_id'] as int,
      telegramUsername: row['telegram_username'] as String?,
      activeChain: row['active_chain'] as String,
      walletAddress: row['wallet_address'] as String?,
      subscriptionTier: row['subscription_tier'] as String,
      isBotActive: row['is_bot_active'] as bool,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  @override
  Map<String, dynamic> toRow(User model, {bool includeId = false}) {
    return {
      if (includeId && model.id != null) 'id': model.id,
      'telegram_id': model.telegramId,
      'telegram_username': model.telegramUsername,
      'active_chain': model.activeChain,
      'wallet_address': model.walletAddress,
      'subscription_tier': model.subscriptionTier,
      'is_bot_active': model.isBotActive,
      'updated_at': model.updatedAt.toIso8601String(),
      // created_at is set by Supabase default — we never write it on updates
    };
  }
}
