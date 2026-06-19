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
import 'package:degenbot_server/src/services/repository/supabase_client.dart';
import 'package:degenbot_server/degen_logger.dart';
import 'package:logging/logging.dart' as logging;
// import 'package:degenbot_server/src/endpoints/user_endpoint.dart';
// import 'package:degenbot_server/src/endpoints/trade_endpoint.dart';
// import 'package:degenbot_server/src/endpoints/health_endpoint.dart';
import 'package:degenbot_server/src/web/routes/telegram_routes.dart';

void setupLogging() {
  logging.Logger.root.level = logging.Level.ALL;
  logging.Logger.root.onRecord.listen((record) {
    if (record.level >= logging.Level.SEVERE) {
      Log.error(
        '${record.loggerName}: ${record.message}',
        error: record.error,
        stackTrace: record.stackTrace,
      );
    } else if (record.level >= logging.Level.WARNING) {
      Log.warning('${record.loggerName}: ${record.message}');
    } else if (record.level >= logging.Level.INFO) {
      Log.info('${record.loggerName}: ${record.message}');
    } else {
      Log.debug('${record.loggerName}: ${record.message}');
    }
  });
}

/// The starting point of the Serverpod server.
void run(List<String> args) async {
  // 1. Initialize logging
  setupLogging();
  Log.startup('DegenBot server is booting up...');

  try {
    // 2. Initialize Supabase client
    Log.startupInfo('Connecting to Supabase database...');
    await initSupabase();
    Log.startupSuccess('Database client successfully ready');

    // 3. Start the Telegram Bot
    Log.startupInfo('Starting Telegram Bot with token: ${Env.telegramToken.substring(0, Env.telegramToken.length > 5 ? 5 : Env.telegramToken.length)}...');
    final bot = DegenTelegramBot();
    await bot.start(webhookBaseUrl: Env.webhookBaseUrl);
    Log.startupSuccess('Telegram bot service started');

    // 4. Initialize Serverpod and connect it with your generated code.
    Log.startupInfo('Configuring Serverpod instance...');
    final pod = Serverpod(
      args,
      Protocol(),
      Endpoints(),
    );

    // ── Telegram webhook route ──────────────────────────────────────────────
    pod.webServer.addRoute(TelegramWebhookRoute(), '/webhooks/telegram');

    // Start the server.
    Log.startupSuccess('Starting Serverpod Mini server...');
    await pod.start();
    Log.startupSuccess('Serverpod Mini running on port ${Env.serverPort}');
  } catch (e, stackTrace) {
    Log.startupError('Fatal error starting Serverpod server', error: e);
    Log.error('Initialization crash', error: e, stackTrace: stackTrace);
    rethrow;
  }
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
