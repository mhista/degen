// telegram_routes.dart
//
// The Relic Route that IS the public HTTP endpoint Telegram talks to.
//
// PLAIN ENGLISH — WHY THIS FILE EXISTS:
//   Serverpod Mini ships with the Relic web server built in, but it
//   doesn't wire up any custom routes for you automatically — you
//   register them yourself, the same way you'd register any endpoint.
//   This route is registered in server.dart via:
//     pod.webServer.addRoute(TelegramWebhookRoute(), '/webhooks/telegram');
//
//   Once registered, Telegram's servers can POST to
//   https://yourdomain.com/webhooks/telegram and this class handles it.
//
// LOCAL DEV vs PRODUCTION:
//   - Production: your real domain (Fly.io/Railway/VPS) already serves
//     this route on a public HTTPS URL — set WEBHOOK_BASE_URL to that
//     domain and TelegramService.start() registers it with Telegram.
//   - Local dev: your machine has no public URL. Run `ngrok http 8080`
//     to get a temporary one (e.g. https://abcd1234.ngrok.io), set that
//     as WEBHOOK_BASE_URL, restart the server. Telegram will now reach
//     your laptop through the ngrok tunnel. Alternatively, leave
//     WEBHOOK_BASE_URL empty and TelegramService falls back to polling
//     mode — no ngrok needed at all for local development, just slightly
//     higher latency per message (a few hundred ms vs instant push).
//
// ALWAYS RETURN 200 OK:
//   Telegram retries aggressively on any non-2xx response, which can
//   cause duplicate processing. We catch every error internally and
//   still return 200 — errors are logged, not surfaced to Telegram.

import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:serverpod/serverpod.dart' hide Logger;
import 'package:televerse/telegram.dart';
import 'package:degenbot_server/src/services/messaging/telegram/telegram_webhook_handler.dart';

final _log = Logger('TelegramWebhookRoute');

class TelegramWebhookRoute extends Route {
  TelegramWebhookRoute() : super(methods: {Method.get, Method.post});

  @override
  Future<Result> handleCall(Session session, Request request) async {
    // ── GET: simple info endpoint, handy for sanity-checking deployment ──
    if (request.method == Method.get) {
      final response = {
        'status': 'Telegram webhook endpoint',
        'method': 'POST',
        'path': '/webhooks/telegram',
        'message': 'Telegram delivers updates here via POST. This GET response is just a health check.',
      };
      return Response.ok(
        body: Body.fromString(jsonEncode(response), mimeType: MimeType.json),
      );
    }

    // ── POST: actual Telegram update delivery ────────────────────────────
    try {
      final body = await request.readAsString();

      if (body.isEmpty) {
        _log.warning('Empty request body received');
        return Response.ok(
          body: Body.fromString(jsonEncode({'ok': true}), mimeType: MimeType.json),
        );
      }

      final payload = jsonDecode(body) as Map<String, dynamic>;

      if (!payload.containsKey('update_id')) {
        _log.warning('Invalid Telegram update — missing update_id');
        return Response.ok(
          body: Body.fromString(jsonEncode({'ok': true}), mimeType: MimeType.json),
        );
      }

      final handler = TelegramWebhookHandler.instance;
      if (handler == null) {
        _log.severe('TelegramWebhookHandler not initialized — was TelegramService.start() called?');
        return Response.ok(
          body: Body.fromString(jsonEncode({'ok': true}), mimeType: MimeType.json),
        );
      }

      final result = await handler.processWebhook(session, payload);
      _log.fine('Webhook processed: success=${result['success']}');

      // Always 200 OK regardless of internal outcome — see file header note.
      return Response.ok(
        body: Body.fromString(jsonEncode({'ok': true}), mimeType: MimeType.json),
      );
    } catch (e, stackTrace) {
      _log.severe('Error processing Telegram webhook', e, stackTrace);
      session.log('Telegram webhook error: $e', stackTrace: stackTrace);

      // Still 200 OK to prevent Telegram retry storms.
      return Response.ok(
        body: Body.fromString(jsonEncode({'ok': true}), mimeType: MimeType.json),
      );
    }
  }
}
