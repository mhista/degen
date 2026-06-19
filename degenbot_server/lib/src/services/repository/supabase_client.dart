// supabase_client.dart
//
// Initialises the Supabase client ONCE at server startup and exposes
// a global getter. Every repository gets the same instance.
//
// WHY service_role key (not anon key):
//   The server is trusted code. Using service_role bypasses Row Level Security
//   (RLS), which is fine because OUR code enforces access rules in the
//   repository layer. The anon key is for untrusted clients (browsers, apps).

import 'package:logging/logging.dart';
import 'package:supabase/supabase.dart';
import 'package:degenbot_server/src/config/env.dart';

final _log = Logger('SupabaseClient');

late final SupabaseClient _client;

/// Call this once from main() before starting the server.
Future<void> initSupabase() async {
  _log.info('Initialising Supabase client → ${Env.supabaseUrl}');
  _client = SupabaseClient(
    Env.supabaseUrl,
    Env.supabaseServiceRoleKey,
    // authOptions: we use service_role so auth flows are server-side only
  );
  _log.info('Supabase client ready');
}

/// Global accessor — use this in every repository.
SupabaseClient get supabase => _client;
