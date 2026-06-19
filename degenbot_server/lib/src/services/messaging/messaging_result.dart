// messaging_result.dart
//
// Unified result type returned by every messaging platform adapter.
//
// PLAIN ENGLISH:
//   Whether we send a message through Telegram or (later) WhatsApp,
//   the calling code shouldn't have to know which platform it was.
//   This wraps the outcome — success or failure — in one consistent shape
//   so the bot's business logic never touches Telegram-specific types
//   directly. That's what makes WhatsApp a drop-in replacement later
//   instead of a rewrite.

enum PlatformType { telegram, whatsapp }

enum MediaType { image, video, audio, document, sticker }

enum MessageType { text, image, video, audio, document, location, sticker }

enum TypingIndicatorType { typing, recording, uploadingPhoto, uploadingVideo, uploadingDocument }

class MessagingResult {
  const MessagingResult({
    required this.success,
    required this.platform,
    this.messageId,
    this.recipient,
    this.errorMessage,
    this.metadata,
  });

  final bool success;
  final PlatformType platform;
  final String? messageId;
  final String? recipient;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;

  factory MessagingResult.success({
    required String messageId,
    required String recipient,
    required PlatformType platform,
    Map<String, dynamic>? metadata,
  }) {
    return MessagingResult(
      success: true,
      platform: platform,
      messageId: messageId,
      recipient: recipient,
      metadata: metadata,
    );
  }

  factory MessagingResult.error({
    required String message,
    required PlatformType platform,
  }) {
    return MessagingResult(
      success: false,
      platform: platform,
      errorMessage: message,
    );
  }
}

/// A button shown in an interactive message (inline keyboard equivalent).
class MessageButton {
  const MessageButton({
    required this.id,
    required this.text,
    this.callbackData,
    this.url,
  });

  final String id;
  final String text;
  final String? callbackData;
  final String? url;
}

/// A row inside a list section (for sendList).
class ListRow {
  const ListRow({required this.id, required this.title, this.description});
  final String id;
  final String title;
  final String? description;
}

/// A section grouping multiple list rows.
class ListSection {
  const ListSection({required this.title, required this.rows});
  final String title;
  final List<ListRow> rows;
}
