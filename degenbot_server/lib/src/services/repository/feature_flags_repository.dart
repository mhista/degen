// feature_flags_repository.dart
//
// Live, no-restart-needed feature toggles, backed by Supabase.
//
// PLAIN ENGLISH:
//   The .env file flags (intelligence_feature_flags.dart) require a
//   server restart to change — fine for "I decided I'm never paying
//   for TokenSniffer" but annoying for "let me try ChainGPT for an
//   hour and see if it's worth it."
//
//   This repository stores the SAME toggles in a Supabase table instead,
//   so you can flip them from a Telegram command and have it take effect
//   on the very next token scan — no redeploy, no restart.
//
// PRECEDENCE RULE:
//   On startup, the live flags table is seeded from the .env defaults.
//   After that, the Supabase value is the source of truth. If you want
//   to permanently change a default, update .env AND clear the
//   Supabase row (or just toggle it via Telegram once).
//
// SQL: see docs/supabase_schema.sql — `feature_flags` table.

import 'package:logging/logging.dart';
import 'package:degenbot_server/src/config/intelligence_feature_flags.dart';
import 'supabase_client.dart';

final _log = Logger('FeatureFlagsRepository');

/// All togglable flag names — kept as constants to avoid typos when
/// calling from Telegram handlers.
class FeatureFlag {
  static const dexScreener = 'dexscreener';
  static const goPlus = 'goplus';
  static const rugCheck = 'rugcheck';
  static const tokenSniffer = 'tokensniffer';
  static const chainGpt = 'chaingpt';
  static const onChainForensics = 'onchain_forensics';
  static const aiScoring = 'ai_scoring';
  static const honeypotIs = 'honeypot_is';

  static const all = [
    dexScreener,
    goPlus,
    rugCheck,
    tokenSniffer,
    chainGpt,
    onChainForensics,
    aiScoring,
    honeypotIs,
  ];

  /// Human-readable label + free/paid note, shown in /features command.
  static const labels = {
    dexScreener: 'DexScreener (market data) — free',
    goPlus: 'GoPlus (safety checks) — free',
    rugCheck: 'RugCheck (Solana safety) — free',
    tokenSniffer: 'TokenSniffer (2nd opinion) — \$99/mo',
    chainGpt: 'ChainGPT (sentiment) — credit-based',
    onChainForensics: 'On-chain forensics (Etherscan/BscScan) — free',
    aiScoring: 'AI scoring engine — required for verdicts',
    honeypotIs: 'Honeypot.is (sell simulation) — free'
  };
}

class FeatureFlagsRepository {
  const FeatureFlagsRepository();

  /// Call once at server startup. Seeds Supabase with .env defaults
  /// ONLY for flags that don't already have a row (so manual toggles
  /// made via Telegram are never overwritten on restart).
  Future<void> seedDefaults() async {
    _log.info('Seeding feature flag defaults...');

    final defaults = {
      FeatureFlag.dexScreener: IntelligenceFeatureFlags.dexScreener,
      FeatureFlag.goPlus: IntelligenceFeatureFlags.goPlus,
      FeatureFlag.rugCheck: IntelligenceFeatureFlags.rugCheck,
      FeatureFlag.tokenSniffer: IntelligenceFeatureFlags.tokenSniffer,
      FeatureFlag.chainGpt: IntelligenceFeatureFlags.chainGpt,
      FeatureFlag.onChainForensics: IntelligenceFeatureFlags.onChainForensics,
      FeatureFlag.aiScoring: IntelligenceFeatureFlags.aiScoring,
      
    };  

    for (final entry in defaults.entries) {
      final existing = await supabase
          .from('feature_flags')
          .select()
          .eq('flag_name', entry.key)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('feature_flags').insert({
          'flag_name': entry.key,
          'is_enabled': entry.value,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        _log.info('Seeded ${entry.key} = ${entry.value}');
      }
    }
  }

  /// Check if a single feature is currently enabled.
  /// Falls back to the .env default if the Supabase row is somehow missing.
  Future<bool> isEnabled(String flagName) async {
    try {
      final row = await supabase
          .from('feature_flags')
          .select('is_enabled')
          .eq('flag_name', flagName)
          .maybeSingle();

      if (row == null) {
        _log.warning('Flag $flagName not found in DB — using .env default');
        return _envDefault(flagName);
      }

      return row['is_enabled'] as bool;
    } catch (e) {
      _log.warning('Failed to read flag $flagName — using .env default', e);
      return _envDefault(flagName);
    }
  }

  /// Get ALL flags at once — used by /features command and by the
  /// pipeline (one query instead of seven).
  Future<Map<String, bool>> getAllFlags() async {
    try {
      final rows = await supabase.from('feature_flags').select();
      final result = <String, bool>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        result[row['flag_name'] as String] = row['is_enabled'] as bool;
      }
      // Fill in any missing flags with .env defaults
      for (final name in FeatureFlag.all) {
        result.putIfAbsent(name, () => _envDefault(name));
      }
      return result;
    } catch (e) {
      _log.warning('Failed to load flags — using all .env defaults', e);
      return {for (final name in FeatureFlag.all) name: _envDefault(name)};
    }
  }

  /// Toggle a single flag. Returns the new state.
  Future<bool> toggle(String flagName) async {
    final current = await isEnabled(flagName);
    final newValue = !current;
    await setEnabled(flagName, newValue);
    return newValue;
  }

  /// Set a flag to a specific value.
  Future<void> setEnabled(String flagName, bool enabled) async {
    _log.info('Setting $flagName = $enabled');
    await supabase.from('feature_flags').upsert({
      'flag_name': flagName,
      'is_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'flag_name');
  }

  // ── PRIVATE ───────────────────────────────────────────────────────────────

  bool _envDefault(String flagName) => switch (flagName) {
        FeatureFlag.dexScreener => IntelligenceFeatureFlags.dexScreener,
        FeatureFlag.goPlus => IntelligenceFeatureFlags.goPlus,
        FeatureFlag.rugCheck => IntelligenceFeatureFlags.rugCheck,
        FeatureFlag.tokenSniffer => IntelligenceFeatureFlags.tokenSniffer,
        FeatureFlag.chainGpt => IntelligenceFeatureFlags.chainGpt,
        FeatureFlag.onChainForensics =>
          IntelligenceFeatureFlags.onChainForensics,
        FeatureFlag.aiScoring => IntelligenceFeatureFlags.aiScoring,
        FeatureFlag.honeypotIs => true,
        _ => true,
      };
}
