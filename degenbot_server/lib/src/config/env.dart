import 'dart:io';
import 'package:envied/envied.dart';

part 'env.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Env — type-safe environment variables via envied.
//
// HOW IT WORKS:
//   1. Copy .env.example → .env  (never commit .env)
//   2. Fill in your real values
//   3. Run `dart run build_runner build` to generate env.g.dart
//   4. Access values as Env.telegramToken, Env.supabaseUrl, etc.
//
// The @EnviedField(obfuscate: true) annotation bakes values into the binary
// as obfuscated strings — they won't appear in plaintext in compiled output.
// In production (e.g. Render/Docker), if the values aren't baked in, we fallback
// to reading from Platform.environment at runtime.
// ─────────────────────────────────────────────────────────────────────────────

@Envied(path: '.env', obfuscate: true)
abstract class Env {
  // ── Telegram ──────────────────────────────────────────────────────────────
  @EnviedField(varName: 'TELEGRAM_BOT_TOKEN', obfuscate: true, defaultValue: '')
  static final String telegramToken = _Env.telegramToken.isNotEmpty
      ? _Env.telegramToken
      : Platform.environment['TELEGRAM_BOT_TOKEN'] ?? '';

  // ── Supabase ──────────────────────────────────────────────────────────────
  @EnviedField(varName: 'SUPABASE_URL', obfuscate: true, defaultValue: '')
  static final String supabaseUrl = _Env.supabaseUrl.isNotEmpty
      ? _Env.supabaseUrl
      : Platform.environment['SUPABASE_URL'] ?? '';

  @EnviedField(varName: 'SUPABASE_SERVICE_ROLE_KEY', obfuscate: true, defaultValue: '')
  static final String supabaseServiceRoleKey = _Env.supabaseServiceRoleKey.isNotEmpty
      ? _Env.supabaseServiceRoleKey
      : Platform.environment['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

  // ── AI Provider (dartantic_ai supports multiple — pick one to start) ──────
  // Set AI_PROVIDER=google or AI_PROVIDER=openai in .env to switch providers.
  @EnviedField(varName: 'AI_PROVIDER', defaultValue: 'google')
  static final String aiProvider = _Env.aiProvider.isNotEmpty
      ? _Env.aiProvider
      : Platform.environment['AI_PROVIDER'] ?? 'google';

  @EnviedField(varName: 'GEMINI_API_KEY', obfuscate: true, defaultValue: '')
  static final String geminiApiKey = _Env.geminiApiKey.isNotEmpty
      ? _Env.geminiApiKey
      : Platform.environment['GEMINI_API_KEY'] ?? '';

  @EnviedField(varName: 'OPENAI_API_KEY', obfuscate: true, defaultValue: '')
  static final String openaiApiKey = _Env.openaiApiKey.isNotEmpty
      ? _Env.openaiApiKey
      : Platform.environment['OPENAI_API_KEY'] ?? '';

  @EnviedField(varName: 'ANTHROPIC_API_KEY', obfuscate: true, defaultValue: '')
  static final String anthropicApiKey = _Env.anthropicApiKey.isNotEmpty
      ? _Env.anthropicApiKey
      : Platform.environment['ANTHROPIC_API_KEY'] ?? '';

  // ── Intelligence layer (Step 2) ──────────────────────────────────────────
  // GoPlus needs no key for basic use.

  // RugCheck — Solana token analysis. Free tier works without a key for
  // basic lookups; set a key for higher rate limits.
  @EnviedField(varName: 'RUGCHECK_API_KEY', obfuscate: true, defaultValue: '')
  static final String rugCheckApiKey = _Env.rugCheckApiKey.isNotEmpty
      ? _Env.rugCheckApiKey
      : Platform.environment['RUGCHECK_API_KEY'] ?? '';

  // Optional — TokenSniffer Pro API ($99/mo). Leave empty to skip this layer.
  @EnviedField(varName: 'TOKENSNIFFER_API_KEY', obfuscate: true, defaultValue: '')
  static final String tokenSnifferApiKey = _Env.tokenSnifferApiKey.isNotEmpty
      ? _Env.tokenSnifferApiKey
      : Platform.environment['TOKENSNIFFER_API_KEY'] ?? '';

  // Optional — ChainGPT sentiment layer. Leave empty to skip this layer.
  @EnviedField(varName: 'CHAINGPT_API_KEY', obfuscate: true, defaultValue: '')
  static final String chainGptApiKey = _Env.chainGptApiKey.isNotEmpty
      ? _Env.chainGptApiKey
      : Platform.environment['CHAINGPT_API_KEY'] ?? '';

  // On-chain forensics (Layer 5) — free tier API keys
  @EnviedField(varName: 'ETHERSCAN_API_KEY', obfuscate: true, defaultValue: '')
  static final String etherscanApiKey = _Env.etherscanApiKey.isNotEmpty
      ? _Env.etherscanApiKey
      : Platform.environment['ETHERSCAN_API_KEY'] ?? '';

  @EnviedField(varName: 'BSCSCAN_API_KEY', obfuscate: true, defaultValue: '')
  static final String bscscanApiKey = _Env.bscscanApiKey.isNotEmpty
      ? _Env.bscscanApiKey
      : Platform.environment['BSCSCAN_API_KEY'] ?? '';

  // ── Serverpod Mini ────────────────────────────────────────────────────────
  @EnviedField(varName: 'SERVER_PORT', defaultValue: '8080')
  static final String serverPort = _Env.serverPort.isNotEmpty
      ? _Env.serverPort
      : Platform.environment['SERVER_PORT'] ?? '8080';

  // Webhook URL base for Telegram (e.g. https://yourdomain.com — the
  // /webhooks/telegram suffix is appended automatically in telegram_bot.dart).
  // Empty = polling mode (default, simplest for local dev). For local webhook
  // testing, set this to an ngrok URL — see README "Local development with ngrok".
  @EnviedField(varName: 'WEBHOOK_BASE_URL', defaultValue: '')
  static final String webhookBaseUrl = _Env.webhookBaseUrl.isNotEmpty
      ? _Env.webhookBaseUrl
      : Platform.environment['WEBHOOK_BASE_URL'] ?? '';
}
