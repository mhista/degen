// telegram_webhook_handler.dart
//
// Singleton that receives decoded Telegram Updates from the Relic route
// and feeds them through Televerse's handler pipeline.
//
// PLAIN ENGLISH — THE FULL REQUEST PATH:
//   1. Telegram's servers POST a JSON update to our public URL
//      (https://yourdomain.com/webhooks/telegram)
//   2. Serverpod's Relic web server receives it via TelegramWebhookRoute
//      (see web/routes/telegram_routes.dart)
//   3. The route decodes the JSON into a televerse Update object and
//      calls TelegramWebhookHandler.instance.processWebhook(...)
//   4. THIS file calls telegramService.handleUpdate(update), which feeds
//      it into Televerse's internal dispatcher
//   5. Televerse matches the update against whatever was registered via
//      bot.command(...), bot.text(...), bot.callbackQuery(...) in
//      command_handlers.dart / ai_handler.dart — our actual bot logic
//
// WHY A SINGLETON:
//   The Relic route class is instantiated fresh by Serverpod's router
//   machinery and has no constructor args of its own — it needs a way
//   to reach the already-running TelegramService/bot setup.

import 'package:logging/logging.dart';
import 'package:serverpod/serverpod.dart' hide Message, Logger;
import 'package:televerse/telegram.dart';
import 'telegram_service.dart';

final _log = Logger('TelegramWebhookHandler');

class TelegramWebhookHandler {
  TelegramWebhookHandler._({required this.telegramService}) {
    _instance = this;
    _log.info('TelegramWebhookHandler initialized');
  }

  static TelegramWebhookHandler? _instance;
  static TelegramWebhookHandler? get instance => _instance;

  factory TelegramWebhookHandler({required TelegramService telegramService}) {
    if (_instance != null) return _instance!;
    return TelegramWebhookHandler._(telegramService: telegramService);
  }

  final TelegramService telegramService;

  /// Entry point called by TelegramWebhookRoute for every incoming POST.
  /// Always returns a result map — the route returns 200 OK to Telegram
  /// regardless, since Telegram aggressively retries non-200 responses
  /// and we never want a retry storm on a transient internal error.
  Future<Map<String, dynamic>> processWebhook(
    Session session,
    Map<String, dynamic> payload,
  ) async {
    try {
      _log.fine('Processing Telegram webhook...');

      final update = Update.fromJson(payload);
      _log.fine('Update ID: ${update.updateId}');

      // Feed the update into Televerse — this is where bot.command(),
      // bot.text(), bot.callbackQuery() handlers actually get triggered.
      await telegramService.handleUpdate(update);

      return {'success': true};
    } catch (e, stackTrace) {
      _log.severe('Error processing Telegram webhook: $e', e, stackTrace);
      session.log('Telegram webhook error: $e', stackTrace: stackTrace);
      return {'success': false, 'error': e.toString()};
    }
  }
}
