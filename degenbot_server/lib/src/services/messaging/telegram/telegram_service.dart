// telegram_service.dart
//
// Full-featured Telegram Bot service. This is the low-level wrapper around
// Televerse — every other piece of bot code talks to Telegram THROUGH this,
// never directly through Bot/RawAPI.
//
// KEY DESIGN DECISION — NO BUILT-IN WEBHOOK SERVER:
//   Televerse can run its own webhook HTTP server via `_bot.startWebhook()`,
//   but we deliberately DON'T use that here. Serverpod's Relic web server
//   already owns port 8080 and our /webhooks/telegram route lives there.
//   Instead, Telegram POSTs updates to Serverpod's route, which decodes
//   them and calls `telegramService.handleUpdate(update)` — feeding the
//   update into Televerse's internal handler pipeline without Televerse
//   ever opening its own socket.
//
// LOCAL DEV NOTE:
//   Telegram needs a public HTTPS URL to deliver webhooks to. Your
//   laptop doesn't have one. For local development, run `ngrok http 8080`
//   to get a temporary public URL, then set WEBHOOK_BASE_URL to that
//   ngrok URL in .env. In production (Fly.io/Railway/VPS), the server's
//   real public domain IS the webhook URL — no ngrok needed there.

import 'dart:io';
import 'package:logging/logging.dart';
import 'package:televerse/telegram.dart'
    show
        Message,
        ParseMode,
        ChatAction,
        ReplyParameters,
        BotCommand,
        BotCommandScope,
        ReplyMarkup,
        MessageEntity,
        InputPollOption,
        PollType,
        InlineKeyboardMarkup,
        LinkPreviewOptions,
        User,
        Update,
        InlineKeyboardButton;
import 'package:televerse/televerse.dart';

final _log = Logger('TelegramService');

/// Enhanced Telegram Bot service with full feature support.
class TelegramService {
  TelegramService._({
    required String botToken,
    this.webhookUrl,
    this.webhookPort,
  }) : _bot = Bot(botToken);

  factory TelegramService({
    required String botToken,
    String? webhookUrl,
    int? webhookPort,
  }) {
    return TelegramService._(
      botToken: botToken,
      webhookUrl: webhookUrl,
      webhookPort: webhookPort,
    );
  }

  final Bot _bot;
  final String? webhookUrl;
  final int? webhookPort;
  bool _isStarted = false;

  Bot get bot => _bot;
  RawAPI get api => _bot.api;

  // ==================== LIFECYCLE ====================

  /// Start the bot — DOES NOT start Televerse's own webhook server.
  /// Serverpod's Relic route handles the actual HTTP endpoint; this just
  /// authenticates the bot and, if a webhookUrl is configured, registers
  /// it with Telegram's servers via setWebhook (a one-time API call, not
  /// a running server).
  Future<void> start() async {
    
    if (_isStarted) return;

    try {
      _log.info('Initializing Telegram bot...');

      final me = await api.getMe();
      _log.info('Bot authenticated: @${me.username}');

      if (webhookUrl != null && webhookUrl!.isNotEmpty) {
        await _configureWebhook();
      } else {
        _log.info('No webhook URL provided — using polling mode (dev only)');
        await _bot.start();
        _log.info('Telegram bot started in polling mode');
      }

      _isStarted = true;
      _log.info('Telegram service fully initialized');
    } catch (e, stackTrace) {
      _log.severe('Failed to start Telegram bot: $e', e, stackTrace);

      if (e.toString().contains('Network') || e.toString().contains('Dio')) {
        _log.warning(
          'NETWORK ERROR — check internet connection, VPN if Telegram '
          'is blocked in your region, and that the bot token is correct.',
        );
      }

      rethrow;
    }
  }

  /// Registers our webhook URL with Telegram's servers. This tells
  /// Telegram "POST updates to THIS url" — it does not start any local
  /// server. The actual receiving route lives in web/routes/telegram_routes.dart.
  Future<void> _configureWebhook() async {
    try {
      _log.info('Setting webhook URL: $webhookUrl');

      await api.deleteWebhook(dropPendingUpdates: true);

      final success = await api.setWebhook(
        webhookUrl!,
        allowedUpdates: [
          UpdateType.message,
          UpdateType.editedMessage,
          UpdateType.callbackQuery,
          UpdateType.inlineQuery,
          UpdateType.chosenInlineResult,
          UpdateType.myChatMember,
          UpdateType.chatMember,
        ],
      );

      if (success) {
        _log.info('Webhook configured successfully');
        final info = await api.getWebhookInfo();
        _log.info('Webhook info: url=${info.url} pending=${info.pendingUpdateCount}');
        if (info.lastErrorMessage != null) {
          _log.warning('Last webhook error: ${info.lastErrorMessage}');
        }
      } else {
        _log.warning('Failed to set webhook');
      }
    } catch (e) {
      _log.severe('Error configuring webhook: $e');
      rethrow;
    }
  }

  /// Feed a Telegram Update into Televerse's handler pipeline.
  /// Called by web/routes/telegram_routes.dart after decoding the
  /// raw webhook POST body.
  Future<void> handleUpdate(Update update) async {
    if (!_isStarted) {
      _log.warning('Bot not started, ignoring update');
      return;
    }

    try {
      await _bot.handleUpdate(update);
    } catch (e, stackTrace) {
      _log.severe('Error handling update: $e', e, stackTrace);
    }
  }

  Future<bool> isConnected() async {
    if (!_isStarted) return false;
    try {
      await api.getMe().timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      _log.warning('Connection check failed: $e');
      return false;
    }
  }

  Future<void> stop() async {
    if (!_isStarted) return;
    try {
      if (webhookUrl != null) {
        await api.deleteWebhook();
        _log.info('Webhook deleted');
      }
    } catch (e) {
      _log.warning('Error deleting webhook: $e');
    }
    _isStarted = false;
    _log.info('Telegram bot stopped');
  }

  void dispose() {
    stop();
    _log.info('TelegramService disposed');
  }

  void _ensureConnected() {
    if (!_isStarted) {
      throw Exception('Telegram bot is not started');
    }
  }

  // ==================== BASIC MESSAGING ====================

  Future<Message> sendTextMessage({
    required dynamic chatId,
    required String text,
    ParseMode? parseMode,
    bool? disableWebPagePreview,
    int? replyToMessageId,
    ReplyMarkup? replyMarkup,
    List<MessageEntity>? entities,
  }) async {
    _ensureConnected();
    return await api.sendMessage(
      ChatID(chatId),
      text,
      parseMode: parseMode,
      entities: entities,
      linkPreviewOptions: disableWebPagePreview == true
          ? LinkPreviewOptions(isDisabled: true)
          : null,
      replyParameters: replyToMessageId != null
          ? ReplyParameters(messageId: replyToMessageId)
          : null,
      replyMarkup: replyMarkup,
    );
  }

  Future<Message> sendPhoto({
    required dynamic chatId,
    required String photoUrl,
    String? caption,
    ParseMode? parseMode,
    bool? hasSpoiler,
    ReplyMarkup? replyMarkup,
    int? replyToMessageId,
  }) async {
    _ensureConnected();
    return await api.sendPhoto(
      ChatID(chatId),
      InputFile.fromUrl(photoUrl),
      caption: caption,
      parseMode: parseMode,
      hasSpoiler: hasSpoiler,
      replyMarkup: replyMarkup,
      replyParameters: replyToMessageId != null
          ? ReplyParameters(messageId: replyToMessageId)
          : null,
    );
  }

  Future<Message> sendVideo({
    required dynamic chatId,
    required String videoUrl,
    String? caption,
    ParseMode? parseMode,
    bool? supportsStreaming,
    bool? hasSpoiler,
    ReplyMarkup? replyMarkup,
  }) async {
    _ensureConnected();
    return await api.sendVideo(
      ChatID(chatId),
      InputFile.fromUrl(videoUrl),
      caption: caption,
      parseMode: parseMode,
      supportsStreaming: supportsStreaming,
      hasSpoiler: hasSpoiler,
      replyMarkup: replyMarkup,
    );
  }

  Future<Message> sendAudio({
    required dynamic chatId,
    required String audioUrl,
    String? caption,
    String? performer,
    String? title,
    int? duration,
  }) async {
    _ensureConnected();
    return await api.sendAudio(
      ChatID(chatId),
      InputFile.fromUrl(audioUrl),
      caption: caption,
      performer: performer,
      title: title,
      duration: duration,
    );
  }

  Future<Message> sendDocument({
    required dynamic chatId,
    required String documentUrl,
    String? caption,
    String? fileName,
    bool? disableContentTypeDetection,
  }) async {
    _ensureConnected();
    return await api.sendDocument(
      ChatID(chatId),
      InputFile.fromUrl(documentUrl),
      caption: caption,
      disableContentTypeDetection: disableContentTypeDetection,
    );
  }

  Future<Message> sendSticker({
    required dynamic chatId,
    required String stickerUrl,
    String? emoji,
  }) async {
    _ensureConnected();
    return await api.sendSticker(
      ChatID(chatId),
      InputFile.fromUrl(stickerUrl),
      emoji: emoji,
    );
  }

  // ==================== INTERACTIVE MESSAGES ====================

  Future<Message> sendInlineKeyboard({
    required dynamic chatId,
    required String text,
    required List<List<InlineKeyboardButton>> keyboard,
    ParseMode? parseMode,
  }) async {
    _ensureConnected();
    return await api.sendMessage(
      ChatID(chatId),
      text,
      parseMode: parseMode,
      replyMarkup: ReplyMarkup.inlineKeyboard(inlineKeyboard: keyboard),
    );
  }

  Future<Message> sendPoll({
    required dynamic chatId,
    required String question,
    required List<InputPollOption> options,
    bool? isAnonymous,
    PollType type = PollType.regular,
    bool? allowsMultipleAnswers,
  }) async {
    _ensureConnected();
    return await api.sendPoll(
      ChatID(chatId),
      question,
      options,
      isAnonymous: isAnonymous,
      type: type,
      allowsMultipleAnswers: allowsMultipleAnswers,
    );
  }

  // ==================== MESSAGE ACTIONS ====================

  Future<bool> sendChatAction({
    required dynamic chatId,
    required ChatAction action,
  }) async {
    _ensureConnected();
    return await api.sendChatAction(ChatID(chatId), action);
  }

  Future<Message> editMessageText({
    required dynamic chatId,
    required int messageId,
    required String text,
    ParseMode? parseMode,
    InlineKeyboardMarkup? replyMarkup,
  }) async {
    _ensureConnected();
    return await api.editMessageText(
      ChatID(chatId),
      messageId,
      text,
      parseMode: parseMode,
      replyMarkup: replyMarkup,
    );
  }

  Future<bool> deleteMessage({
    required dynamic chatId,
    required int messageId,
  }) async {
    _ensureConnected();
    return await api.deleteMessage(ChatID(chatId), messageId);
  }

  // ==================== LOCATION ====================

  Future<Message> sendLocation({
    required dynamic chatId,
    required double latitude,
    required double longitude,
  }) async {
    _ensureConnected();
    return await api.sendLocation(ChatID(chatId), latitude, longitude);
  }

  // ==================== CALLBACK QUERIES ====================

  Future<bool> answerCallbackQuery({
    required String callbackQueryId,
    String? text,
    bool? showAlert,
  }) async {
    return await api.answerCallbackQuery(
      callbackQueryId,
      text: text,
      showAlert: showAlert ?? false,
    );
  }

  // ==================== FILE OPERATIONS ====================

  Future<File?> downloadFile({
    required String fileId,
    required String savePath,
  }) async {
    final file = await api.getFile(fileId);
    return file.download(path: savePath);
  }

  // ==================== BOT COMMANDS ====================

  Future<bool> setMyCommands({
    required List<BotCommand> commands,
    BotCommandScope? scope,
  }) async {
    return await api.setMyCommands(commands, scope: scope);
  }

  // ==================== BOT INFO ====================

  Future<User> getMe() async => api.getMe();
}
