// // lib/src/config/dependency_injection.dart

// import 'package:get_it/get_it.dart';
// import 'package:logging/logging.dart';
// import '../bot/core/platform_type.dart';
// import 'env.dart';
// import '../bot/core/messaging_service_factory.dart';
// import '../bot/telegram/telegram_service.dart';
// import '../bot/telegram/telegram_service_adapter.dart';
// import '../bot/telegram/telegram_webhook_handler.dart';
// import '../endpoints/bot_endpoint.dart';

// final getIt = GetIt.instance;
// final _log = Logger('DI');

// /// Sets up all dependency injection for the degenbot server.
// Future<void> setupDependencyInjection() async {
//   _log.info('🔧 Setting up dependency injection...');

//   // 1. Register Core Services & Endpoints
//   final botEndpoint = BotEndpoint();
//   getIt.registerSingleton<BotEndpoint>(botEndpoint);

//   // 2. Setup Telegram
//   await _setupTelegram(botEndpoint);

//   // 3. Initialize Messaging Factory
//   _initializeMessagingFactory();

//   _log.info('✅ Dependency injection setup complete!');
// }

// Future<void> _setupTelegram(BotEndpoint botEndpoint) async {
//   final token = Env.telegramToken;
//   if (token.isEmpty) {
//     _log.warning('⚠️ Telegram bot token not provided, skipping setup');
//     return;
//   }

//   try {
//     // Construct webhook URL if base URL is provided
//     final webhookUrl = Env.webhookBaseUrl.isNotEmpty 
//         ? '${Env.webhookBaseUrl}/telegram' 
//         : null;

//     final telegramService = TelegramService(
//       botToken: token,
//       webhookUrl: webhookUrl,
//     );

//     final telegramAdapter = TelegramServiceAdapter(telegramService);

//     getIt.registerSingleton<TelegramService>(telegramService);
//     getIt.registerSingleton<TelegramServiceAdapter>(telegramAdapter);

//     // Start the bot (registers webhook or starts polling)
//     await telegramService.start();

//     // Initialize webhook handler (singleton inside)
//     TelegramWebhookHandler(
//       telegramService: telegramService,
//       botEndpoint: botEndpoint,
//     );

//     _log.info('   ✅ Telegram service configured and started');
//   } catch (e, stackTrace) {
//     _log.severe('   ⚠️ Failed to initialize Telegram: $e', e, stackTrace);
//   }
// }

// void _initializeMessagingFactory() {
//   _log.info('🏭 Initializing Messaging Service Factory...');

//   if (getIt.isRegistered<TelegramServiceAdapter>()) {
//     MessagingServiceFactory.register(
//       PlatformType.telegram, 
//       getIt<TelegramServiceAdapter>()
//     );
//   }

//   _log.info('   ✅ Messaging Service Factory ready');
// }
