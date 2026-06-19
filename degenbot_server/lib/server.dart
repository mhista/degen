// server.dart
//
// Creates and configures the Serverpod Mini server.
//
// WHY Serverpod Mini (not full Serverpod)?
//   Full Serverpod manages its own Postgres connection pool via its ORM.
//   We use Supabase for persistence, so we only need the HTTP server,
//   endpoint routing, and client code generation — that's exactly what
//   Serverpod Mini provides.
//
//   When we add the Flutter app (degenbot_flutter), the client package
//   (degenbot_client) generated here is imported directly — no protocol
//   changes needed.
//
// THE WEB SERVER (Relic):
//   Serverpod Mini's underlying web server is Relic — it's there by
//   default, but custom routes (like our Telegram webhook receiver)
//   need to be registered explicitly with pod.webServer.addRoute(...).
//   This is the ONE place that registration happens.
//
// ADDING NEW ENDPOINTS:
//   1. Create a new file in lib/src/endpoints/
//   2. Extend Endpoint from serverpod
//   3. Register it in the endpoints list below
//   4. Run: dart run serverpod generate  (regenerates client)

import 'package:degenbot_server/src/generated/endpoints.dart';
import 'package:degenbot_server/src/generated/protocol.dart';
import 'package:serverpod/serverpod.dart';
import 'package:degenbot_server/src/config/env.dart';
import 'package:degenbot_server/src/bot/telegram_bot.dart';
// import 'package:degenbot_server/src/endpoints/user_endpoint.dart';
// import 'package:degenbot_server/src/endpoints/trade_endpoint.dart';
// import 'package:degenbot_server/src/endpoints/health_endpoint.dart';
import 'package:degenbot_server/src/web/routes/telegram_routes.dart';

import 'src/services/repository/supabase_client.dart';

/// The starting point of the Serverpod server.
void run(List<String> args) async {
  // 1. Initialize Supabase client
  await initSupabase();

  // 2. Start the Telegram Bot
  final bot = DegenTelegramBot();
  await bot.start(webhookBaseUrl: Env.webhookBaseUrl);

  // 3. Initialize Serverpod and connect it with your generated code.
  final pod = Serverpod(
    args,
    Protocol(),
    Endpoints(),
  );

  // ── Telegram webhook route ──────────────────────────────────────────────
  pod.webServer.addRoute(TelegramWebhookRoute(), '/webhooks/telegram');

  // Start the server.
  await pod.start();
}

// Future<Serverpod> createServer({required int port}) async {
//   final pod = Serverpod(
//     ['--mode', 'development'],
//     Protocol(),   // generated — run `dart run serverpod generate`
//     Endpoints()   // generated — run `dart run serverpod generate`
//       // ..initializeEndpoints({
//       //   'health': HealthEndpoint(),
//       //   'user': UserEndpoint(),
//       //   'trade': TradeEndpoint(),
//       //   // 'scan': ScanEndpoint(),     ← added in Step 5
//       //   // 'wallet': WalletEndpoint(), ← added in Step 4
//       // }),
//   );

//   // ── Telegram webhook route ──────────────────────────────────────────────
//   // Telegram POSTs updates here. TelegramWebhookHandler.instance must be
//   // set (via TelegramService.start() in main.dart) BEFORE Telegram ever
//   // delivers an update, or the route will log a warning and no-op safely.
//   pod.webServer.addRoute(TelegramWebhookRoute(), '/webhooks/telegram');

//   return pod;
// }
