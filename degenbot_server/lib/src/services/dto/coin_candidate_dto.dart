// coin_candidate_dto.dart
//
// Supabase table: coin_candidates
//
//   create table coin_candidates (
//     id                  bigserial primary key,
//     chain               text not null,
//     contract_address    text not null,
//     name                text not null,
//     symbol              text not null,
//     ai_score            int not null default 0,
//     liquidity_usd       numeric not null default 0,
//     volume_usd_24h      numeric not null default 0,
//     price_usd           numeric not null default 0,
//     market_cap_usd      numeric,
//     holder_count        int,
//     price_change_1h     numeric,
//     price_change_6h     numeric,
//     price_change_24h    numeric,
//     ai_reasoning        text,
//     status              text not null default 'pending',
//     scanned_at          timestamptz not null default now(),
//     constraint coin_candidates_unique unique (contract_address, chain)
//   );
//
//   create index on coin_candidates (status);
//   create index on coin_candidates (ai_score desc);

import 'package:degenbot_server/src/generated/protocol.dart';
import 'base_dto.dart';

class CoinCandidateDto extends BaseDto<CoinCandidate> {
  const CoinCandidateDto();

  @override
  CoinCandidate fromRow(Map<String, dynamic> row) {
    return CoinCandidate(
      id: row['id'] as int?,
      chain: row['chain'] as String,
      contractAddress: row['contract_address'] as String,
      name: row['name'] as String,
      symbol: row['symbol'] as String,
      aiScore: row['ai_score'] as int,
      liquidityUsd: (row['liquidity_usd'] as num).toDouble(),
      volumeUsd24h: (row['volume_usd_24h'] as num).toDouble(),
      priceUsd: (row['price_usd'] as num).toDouble(),
      marketCapUsd: row['market_cap_usd'] != null
          ? (row['market_cap_usd'] as num).toDouble()
          : null,
      holderCount: row['holder_count'] as int?,
      priceChange1h: row['price_change_1h'] != null
          ? (row['price_change_1h'] as num).toDouble()
          : null,
      priceChange6h: row['price_change_6h'] != null
          ? (row['price_change_6h'] as num).toDouble()
          : null,
      priceChange24h: row['price_change_24h'] != null
          ? (row['price_change_24h'] as num).toDouble()
          : null,
      aiReasoning: row['ai_reasoning'] as String?,
      status: row['status'] as String,
      scannedAt: DateTime.parse(row['scanned_at'] as String),
    );
  }

  @override
  Map<String, dynamic> toRow(CoinCandidate model, {bool includeId = false}) {
    return {
      if (includeId && model.id != null) 'id': model.id,
      'chain': model.chain,
      'contract_address': model.contractAddress,
      'name': model.name,
      'symbol': model.symbol,
      'ai_score': model.aiScore,
      'liquidity_usd': model.liquidityUsd,
      'volume_usd_24h': model.volumeUsd24h,
      'price_usd': model.priceUsd,
      if (model.marketCapUsd != null) 'market_cap_usd': model.marketCapUsd,
      if (model.holderCount != null) 'holder_count': model.holderCount,
      if (model.priceChange1h != null) 'price_change_1h': model.priceChange1h,
      if (model.priceChange6h != null) 'price_change_6h': model.priceChange6h,
      if (model.priceChange24h != null)
        'price_change_24h': model.priceChange24h,
      if (model.aiReasoning != null) 'ai_reasoning': model.aiReasoning,
      'status': model.status,
      'scanned_at': model.scannedAt.toIso8601String(),
    };
  }
}
