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
// ─────────────────────────────────────────────────────────────────────────────

@Envied(path: '.env', obfuscate: true)
abstract class Env {
  // ── Telegram ──────────────────────────────────────────────────────────────
  @EnviedField(varName: 'TELEGRAM_BOT_TOKEN', obfuscate: true, defaultValue: '')
  static final String telegramToken = _Env.telegramToken;

  // ── Supabase ──────────────────────────────────────────────────────────────
  @EnviedField(varName: 'SUPABASE_URL', obfuscate: true, defaultValue: '')
  static final String supabaseUrl = _Env.supabaseUrl;

  @EnviedField(varName: 'SUPABASE_SERVICE_ROLE_KEY', obfuscate: true, defaultValue: '')
  static final String supabaseServiceRoleKey = _Env.supabaseServiceRoleKey;

  // ── AI Provider (dartantic_ai supports multiple — pick one to start) ──────
  // Set AI_PROVIDER=google or AI_PROVIDER=openai in .env to switch providers.
  @EnviedField(varName: 'AI_PROVIDER', defaultValue: 'google')
  static final String aiProvider = _Env.aiProvider;

  @EnviedField(varName: 'GEMINI_API_KEY', obfuscate: true, defaultValue: '')
  static final String geminiApiKey = _Env.geminiApiKey;

  @EnviedField(varName: 'OPENAI_API_KEY', obfuscate: true, defaultValue: '')
  static final String openaiApiKey = _Env.openaiApiKey;

  @EnviedField(varName: 'ANTHROPIC_API_KEY', obfuscate: true, defaultValue: '')
  static final String anthropicApiKey = _Env.anthropicApiKey;

  // ── Intelligence layer (Step 2) ──────────────────────────────────────────
  // GoPlus needs no key for basic use.

  // RugCheck — Solana token analysis. Free tier works without a key for
  // basic lookups; set a key for higher rate limits.
  @EnviedField(varName: 'RUGCHECK_API_KEY', obfuscate: true, defaultValue: '')
  static final String rugCheckApiKey = _Env.rugCheckApiKey;

  // Optional — TokenSniffer Pro API ($99/mo). Leave empty to skip this layer.
  @EnviedField(varName: 'TOKENSNIFFER_API_KEY', obfuscate: true, defaultValue: '')
  static final String tokenSnifferApiKey = _Env.tokenSnifferApiKey;

  // Optional — ChainGPT sentiment layer. Leave empty to skip this layer.
  @EnviedField(varName: 'CHAINGPT_API_KEY', obfuscate: true, defaultValue: '')
  static final String chainGptApiKey = _Env.chainGptApiKey;

  // On-chain forensics (Layer 5) — free tier API keys
  @EnviedField(varName: 'ETHERSCAN_API_KEY', obfuscate: true, defaultValue: '')
  static final String etherscanApiKey = _Env.etherscanApiKey;

  @EnviedField(varName: 'BSCSCAN_API_KEY', obfuscate: true, defaultValue: '')
  static final String bscscanApiKey = _Env.bscscanApiKey;

  // ── Serverpod Mini ────────────────────────────────────────────────────────
  @EnviedField(varName: 'SERVER_PORT', defaultValue: '8080')
  static final String serverPort = _Env.serverPort;

  // Webhook URL base for Telegram (e.g. https://yourdomain.com — the
  // /webhooks/telegram suffix is appended automatically in telegram_bot.dart).
  // Empty = polling mode (default, simplest for local dev). For local webhook
  // testing, set this to an ngrok URL — see README "Local development with ngrok".
  @EnviedField(varName: 'WEBHOOK_BASE_URL', defaultValue: '')
  static final String webhookBaseUrl = _Env.webhookBaseUrl;
}
