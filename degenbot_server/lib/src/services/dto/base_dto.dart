// base_dto.dart
//
// Every DTO in the system implements this interface.
//
// WHY DTOs EXIST (plain English):
//   Serverpod generates clean Dart model classes from YAML.
//   Supabase stores data as JSON rows in Postgres.
//   These two worlds don't speak the same language directly.
//
//   A DTO (Data Transfer Object) is a translator.
//   It knows how to:
//     • Turn a Supabase JSON map → Serverpod model  (fromRow)
//     • Turn a Serverpod model  → Supabase JSON map (toRow)
//
//   This means:
//     • If you switch from Supabase to Firebase tomorrow, you only
//       rewrite the DTOs — your endpoints and business logic are untouched.
//     • If Serverpod changes its model format, you only touch the DTOs.
//     • Everything stays modular and swappable.

/// Contract that every DTO must satisfy.
///
/// [T] is the Serverpod model type (e.g. User, Trade, CoinCandidate).
abstract class BaseDto<T> {
  const BaseDto();

  /// Convert a Supabase row (Map<String, dynamic>) into a Serverpod model.
  T fromRow(Map<String, dynamic> row);

  /// Convert a Serverpod model into a Supabase row map ready for insert/upsert.
  /// Pass [includeId: false] on inserts (let Supabase assign the id).
  Map<String, dynamic> toRow(T model, {bool includeId = false});
}
