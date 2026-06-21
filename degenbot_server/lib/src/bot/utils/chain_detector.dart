// chain_detector.dart
//
// FIRST-PASS format filter only — rejects strings that obviously aren't
// addresses at all, cheaply, with zero API calls. Does NOT decide the
// final chain anymore: DexScreenerService.resolveChain() is the actual
// chain router (see token_intelligence_pipeline.analyzeAuto), since it
// asks DexScreener directly instead of guessing eth-vs-bnb-vs-base.
//
// This still matters because it's instant and free — no point calling
// DexScreener for a string that isn't shaped like any address at all.

class ChainDetector {
  static const _solanaPattern = r'^[1-9A-HJ-NP-Za-km-z]{32,44}$';
  static const _evmPattern = r'^0x[0-9a-fA-F]{40}$';

  /// Returns 'solana', 'evm', or null if the format matches neither.
  static String? detect(String address) {
    final trimmed = address.trim();
    if (RegExp(_evmPattern).hasMatch(trimmed)) return 'evm';
    if (RegExp(_solanaPattern).hasMatch(trimmed)) return 'solana';
    return null;
  }

  /// Strict check against a SPECIFIC chain — used by wallet/trade flows
  /// where the chain is already known and you're validating against it,
  /// as opposed to detect() which figures out the chain from scratch.
  static bool isValidForChain(String address, String chain) {
    final trimmed = address.trim();
    return switch (chain) {
      'solana' => RegExp(_solanaPattern).hasMatch(trimmed),
      'ethereum' || 'bnb' => RegExp(_evmPattern).hasMatch(trimmed),
      _ => false,
    };
  }
}