// File: server/lib/utils/logger/asami_logger.dart

import 'package:serverpod/serverpod.dart' hide LogLevel;
import 'package:talker/talker.dart';

/// Global Talker instance for application-wide logging
final talker = Talker(
  settings: TalkerSettings(
    useConsoleLogs: true,
    colors: {
      TalkerKey.error: AnsiPen()..red(),
      TalkerKey.warning: AnsiPen()..yellow(),
      TalkerKey.info: AnsiPen()..blue(),
      TalkerKey.debug: AnsiPen()..gray(level: 0.5),
      TalkerKey.verbose: AnsiPen()..gray(level: 0.3),
      TalkerKey.critical: AnsiPen()..magenta(),
    },
  ),
  logger: TalkerLogger(
    settings: TalkerLoggerSettings(
      enableColors: true,
      defaultTitle: 'ASAMI-LOG'
      // lineLength: 120,
    ),
  ),
);

/// Enhanced logger with Talker integration
class Log {
  static Session? _currentSession;

  /// Set current session for dual logging (Talker + Serverpod)
  static void setSession(Session session) {
    _currentSession = session;
  }

  /// Clear current session
  static void clearSession() {
    _currentSession = null;
  }

  // ==================== PAYMENT SPECIFIC LOGS ====================

  /// Log payment initialization
  static void paymentInit({
    required String reference,
    required double amount,
    required String userId,
    String? productId,
    String? cartId,
    Session? session,
  }) {
    final msg = '''
💳 PAYMENT INITIALIZED
   Reference: $reference
   Amount: ₦${amount.toStringAsFixed(2)}
   User ID: $userId
   ${productId != null ? 'Product ID: $productId' : ''}
   ${cartId != null ? 'Cart ID: $cartId' : ''}
''';
    talker.info(msg);
    _serverpodLog(msg, session: session, level: LogLevel.info);
  }

  /// Log payment verification
  static void paymentVerify({
    required String reference,
    required String status,
    double? amount,
    Session? session,
  }) {
    final msg = '''
🔍 PAYMENT VERIFICATION
   Reference: $reference
   Status: $status
   ${amount != null ? 'Amount: ₦${amount.toStringAsFixed(2)}' : ''}
''';
    talker.info(msg);
    _serverpodLog(msg, session: session, level: LogLevel.info);
  }

  /// Log payment success
  static void paymentSuccess({
    required String reference,
    required double amount,
    String? orderId,
    Session? session,
  }) {
    final msg = '''
✅ PAYMENT SUCCESSFUL
   Reference: $reference
   Amount: ₦${amount.toStringAsFixed(2)}
   ${orderId != null ? 'Order ID: $orderId' : ''}
''';
    talker.info(msg);
    _serverpodLog(msg, session: session, level: LogLevel.info);
  }

  /// Log payment failure
  static void paymentFailed({
    required String reference,
    required String reason,
    Session? session,
  }) {
    final msg = '''
❌ PAYMENT FAILED
   Reference: $reference
   Reason: $reason
''';
    talker.error(msg);
    _serverpodLog(msg, session: session, level: LogLevel.error);
  }

  // ==================== GENERAL LOGS ====================

  /// Debug level
  static void debug(String message, {dynamic data, Session? session}) {
    final msg = data != null ? '$message\n${_formatData(data)}' : message;
    talker.debug('🐛 $msg');
    _serverpodLog('🐛 $msg', session: session, level: LogLevel.debug);
  }

  /// Info level
  static void info(String message, {dynamic data, Session? session}) {
    final msg = data != null ? '$message\n${_formatData(data)}' : message;
    talker.info('ℹ️ $msg');
    _serverpodLog('ℹ️ $msg', session: session, level: LogLevel.info);
  }

  /// Warning level
  static void warning(String message, {dynamic data, Session? session}) {
    final msg = data != null ? '$message\n${_formatData(data)}' : message;
    talker.warning('⚠️ $msg');
    _serverpodLog('⚠️ $msg', session: session, level: LogLevel.warning);
  }

  /// Error level
  static void error(
    String message, {
    dynamic error,
    StackTrace? stackTrace,
    Session? session,
  }) {
    final errorMsg = error != null ? '$message: $error' : message;
    talker.error('❌ $errorMsg', error, stackTrace);
    _serverpodLog('❌ $errorMsg',
        session: session, level: LogLevel.error, stackTrace: stackTrace);
  }

  /// Success level
  static void success(String message, {dynamic data, Session? session}) {
    final msg = data != null ? '$message\n${_formatData(data)}' : message;
    talker.info('✅ $msg');
    _serverpodLog('✅ $msg', session: session, level: LogLevel.info);
  }

  /// Critical level
  static void critical(String message, {dynamic error, Session? session}) {
    final msg = error != null ? '$message: $error' : message;
    talker.critical('🔴 $msg');
    _serverpodLog('🔴 $msg', session: session, level: LogLevel.error);
  }

  // ==================== SPECIFIC USE CASES ====================

  /// Webhook logs
  static void webhook(String service, String method, String path,
      {Session? session}) {
    final msg = '📡 $service webhook - Method: $method, Path: $path';
    talker.info(msg);
    _serverpodLog(msg, session: session, level: LogLevel.info);
  }

  /// API request logs
  static void apiRequest({
    required String endpoint,
    required String method,
    Map<String, dynamic>? params,
    Session? session,
  }) {
    final msg = '''
📤 API REQUEST
   Endpoint: $endpoint
   Method: $method
   ${params != null ? 'Params: ${_formatData(params)}' : ''}
''';
    talker.verbose(msg);
    _serverpodLog(msg, session: session, level: LogLevel.debug);
  }

  /// API response logs
  static void apiResponse({
    required String endpoint,
    required int statusCode,
    dynamic data,
    Session? session,
  }) {
    final msg = '''
📥 API RESPONSE
   Endpoint: $endpoint
   Status: $statusCode
   ${data != null ? 'Data: ${_formatData(data)}' : ''}
''';
    talker.verbose(msg);
    _serverpodLog(msg, session: session, level: LogLevel.debug);
  }

  /// Database query logs
  static void dbQuery(String query, {Map<String, dynamic>? params, Session? session}) {
    final msg = '''
🗄️ DATABASE QUERY
   ${_truncate(query, maxLength: 200)}
   ${params != null ? 'Params: ${_formatData(params)}' : ''}
''';
    talker.verbose(msg);
    _serverpodLog(msg, session: session, level: LogLevel.debug);
  }

  /// State change logs
  static void stateChange({
    required String entity,
    required String from,
    required String to,
    Session? session,
  }) {
    final msg = '🔄 STATE CHANGE: $entity | $from → $to';
    talker.info(msg);
    _serverpodLog(msg, session: session, level: LogLevel.info);
  }

  // ==================== STARTUP LOGS ====================

  static void startup(String message) {
    talker.info('🚀 $message');
    print('🚀 $message');
  }

  static void startupInfo(String message) {
    talker.info('   $message');
    print('   $message');
  }

  static void startupSuccess(String message) {
    talker.info('✅ $message');
    print('✅ $message');
  }

  static void startupWarning(String message) {
    talker.warning('⚠️ $message');
    print('⚠️ $message');
  }

  static void startupError(String message, {dynamic error}) {
    final msg = error != null ? '$message\n   Error: $error' : message;
    talker.error('❌ $msg');
    print('❌ $msg');
  }

  // ==================== HELPERS ====================

  /// Log to Serverpod if session available
  static void _serverpodLog(
    String message, {
    Session? session,
    LogLevel level = LogLevel.info,
    StackTrace? stackTrace,
  }) {
    final s = session ?? _currentSession;
    if (s != null) {
      s.log(message, stackTrace: stackTrace);
    }
  }

  /// Format data for display
  static String _formatData(dynamic data) {
    if (data is Map) {
      return data.entries
          .map((e) => '   ${e.key}: ${_truncate(e.value.toString())}')
          .join('\n');
    }
    if (data is List) {
      return data.map((e) => '   - ${_truncate(e.toString())}').join('\n');
    }
    return '   ${_truncate(data.toString())}';
  }

  /// Truncate long strings
  static String _truncate(String text, {int maxLength = 100}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Get Talker history
  static List<TalkerData> getHistory() => talker.history;

  /// Clear Talker history
  static void clearHistory() => talker.cleanHistory();
}