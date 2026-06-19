// messaging_service_interface.dart
//
// The contract EVERY messaging platform adapter must implement.
//
// PLAIN ENGLISH:
//   This is the "shape" both Telegram and WhatsApp must fit into.
//   Your DegenBot business logic (command handlers, AI handler, trade
//   notifications) calls methods on THIS interface — never on Televerse
//   or a WhatsApp SDK directly. That indirection is what lets you swap
//   or add a platform without touching a single line of trading logic.

import 'messaging_result.dart';

abstract class IMessagingService {
  PlatformType get platformType;

  Future<MessagingResult> sendText({
    required String recipient,
    required String text,
    bool? previewUrl,
    String? parseMode,
  });

  Future<MessagingResult> sendMedia({
    required String recipient,
    required String mediaUrl,
    required MediaType mediaType,
    String? caption,
  });

  Future<MessagingResult> sendButtons({
    required String recipient,
    required String bodyText,
    required List<MessageButton> buttons,
    String? headerText,
    String? footerText,
    Map<String, dynamic>? headerInteractive,
  });

  Future<MessagingResult> sendList({
    required String recipient,
    required String bodyText,
    required String buttonText,
    required List<ListSection> sections,
    String? headerText,
    String? footerText,
  });

  Future<MessagingResult> sendLocation({
    required String recipient,
    required double latitude,
    required double longitude,
    String? name,
    String? address,
  });

  Future<bool> markAsRead({required String messageId});

  Future<MessagingResult> replyToMessage({
    required String recipient,
    required String messageId,
    required String text,
    bool? previewUrl,
  });

  Future<bool> sendTypingIndicator({
    required String recipient,
    TypingIndicatorType? type,
  });

  void dispose();
}
