// telegram_bot.dart
//
// DegenBot's Telegram interface built on Televerse, wired through
// TelegramService rather than driving Televerse's Bot directly.
//
// HOW TELEVERSE WORKS (plain English):
//   Televerse is a Dart library that talks to the Telegram Bot API.
//   It gives your bot a "brain" that reacts to messages.
//   You register handlers for specific commands (/start, /buy, etc.)
//   and for free-form text (the AI natural language path).
//
// CRITICAL FIX FROM EARLIER VERSION:
//   This used to call `_bot.startWebhook(url:..., port:...)`, which makes
//   Televerse open its OWN HTTP server on that port. That collides with
//   Serverpod's Relic server, which is already listening on the same
//   port for every endpoint call AND for our /webhooks/telegram route.
//   Two servers can't bind the same port — this would have crashed on
//   startup the moment WEBHOOK_BASE_URL was set.
//
//   The fix: Televerse NEVER starts its own server here. Instead:
//     - `setWebhook(url)` is just an API CALL telling Telegram's servers
//       where to POST updates (handled inside TelegramService.start()).
//     - Serverpod's Relic route (telegram_routes.dart) receives those
//       POSTs and calls `telegramService.handleUpdate(update)`, which
//       feeds the update into Televerse's internal dispatcher without
//       ever opening a socket of its own.
//
// TWO MODES:
//   • Long Polling (dev/local, default if WEBHOOK_BASE_URL is empty):
//     Televerse repeatedly asks Telegram "any new messages?" — no
//     public URL needed, works on a laptop with no setup.
//   • Webhook (production, or local dev via ngrok): Telegram pushes
//     updates to our Relic route the instant a message arrives.
//
// LOCAL DEV WITH NGROK:
//   1. Run the server: dart run bin/main.dart (or via Docker)
//   2. In another terminal: ngrok http 8080
//   3. Copy the https://xxxx.ngrok-free.app URL ngrok gives you
//   4. Set WEBHOOK_BASE_URL=https://xxxx.ngrok-free.app in .env
//   5. Restart the server — Telegram now pushes to your laptop via the tunnel
//   This step is OPTIONAL — leaving WEBHOOK_BASE_URL empty just uses
//   polling instead, which is simpler for day-to-day local development.
//
// AGENTIC PATH:
//   Any message that isn't a command falls through to the AI handler.
//   The AI handler sends the message to dartantic_ai which decides
//   which tool to call (check balance, scan coins, set risk, etc.)
//   and executes it. This is the natural language "just talk to the bot" UX.

import 'package:logging/logging.dart';
import 'package:degenbot_server/src/config/env.dart';
import 'package:degenbot_server/src/bot/handlers/command_handlers.dart';
import 'package:degenbot_server/src/bot/handlers/ai_handler.dart';
import 'package:degenbot_server/src/bot/middleware/user_middleware.dart';
import 'package:degenbot_server/src/services/messaging/telegram/telegram_service.dart';
import 'package:degenbot_server/src/services/messaging/telegram/telegram_service_adapter.dart';
import 'package:degenbot_server/src/services/messaging/telegram/telegram_webhook_handler.dart';
import 'package:televerse/televerse.dart';

final _log = Logger('TelegramBot');

class DegenTelegramBot {
  late final TelegramService _telegramService;
  late final TelegramServiceAdapter _adapter;
  late final CommandHandlers _commands;
  late final AiHandler _ai;

  Future<void> start({required String webhookBaseUrl}) async {
    _log.info('Initialising Telegram service...');

    final webhookUrl =
        webhookBaseUrl.isEmpty ? null : '$webhookBaseUrl/webhooks/telegram';

    _telegramService = TelegramService(
      botToken: Env.telegramToken,
      webhookUrl: webhookUrl,
    );
    _adapter = TelegramServiceAdapter(_telegramService);

    _commands = CommandHandlers(_telegramService.bot);
    _ai = AiHandler(_telegramService.bot);

    _telegramService.bot.use(const UserMiddleware().handle);

    // ── Command handlers ────────────────────────────────────────────────
    _commands.register();
    _commands.registerFeatureToggleCallback();

    // ── AI catch-all ─────────────────────────────────────────────────────
    // Any non-command text message goes to the AI agent.
    // Must be registered LAST — Televerse routes in registration order.
    _ai.register();

    // ── Error handler ────────────────────────────────────────────────────
    _telegramService.bot.onError((err) {
      _log.severe('Unhandled bot error', err.error, err.stackTrace);
    });

    // ── Start: authenticates with Telegram, registers webhook URL via
    //    API call (if set), or starts Televerse's internal polling loop
    //    (if not). NEVER opens its own HTTP server — see file header.
    await _telegramService.start();

    // ── Wire up the singleton the Relic route reaches into ────────────
    // After this, TelegramWebhookHandler.instance is non-null and the
    // /webhooks/telegram route can actually process incoming updates.
    TelegramWebhookHandler(telegramService: _telegramService);

    _log.info(
      'Telegram bot ready (${webhookUrl != null ? "webhook: $webhookUrl" : "long polling"})',
    );
  }

  /// Platform-agnostic adapter — use this for sending proactive messages
  /// (trade notifications, scan alerts) from anywhere else in the codebase
  /// that shouldn't need to know it's specifically Telegram underneath.
  TelegramServiceAdapter get messaging => _adapter;

  /// Raw Televerse bot — only command_handlers.dart and ai_handler.dart
  /// should need this, for registering handlers and Telegram-specific
  /// features (inline keyboards, conversation plugin) the generic
  /// IMessagingService interface doesn't expose.
  Bot<Context> get bot => _telegramService.bot;
}

