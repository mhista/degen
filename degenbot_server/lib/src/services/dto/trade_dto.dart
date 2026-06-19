// trade_dto.dart
//
// Supabase table: trades
//
//   create table trades (
//     id                    bigserial primary key,
//     user_id               bigint not null references users(id),
//     coin_candidate_id     bigint not null references coin_candidates(id),
//     chain                 text not null,
//     contract_address      text not null,
//     symbol                text not null,
//     amount_spent_native   numeric not null,
//     amount_spent_usd      numeric not null,
//     buy_price_usd         numeric not null,
//     buy_tx_hash           text,
//     bought_at             timestamptz,
//     sell_price_usd        numeric,
//     sell_tx_hash          text,
//     sold_at               timestamptz,
//     take_profit_price_usd numeric,
//     stop_loss_price_usd   numeric,
//     realized_pnl_usd      numeric,
//     roi_percent           numeric,
//     close_reason          text,
//     status                text not null default 'open',
//     created_at            timestamptz not null default now(),
//     updated_at            timestamptz not null default now()
//   );
//
//   create index on trades (user_id);
//   create index on trades (status);
//   create index on trades (user_id, created_at desc);

import 'package:degenbot_server/src/generated/protocol.dart';
import 'base_dto.dart';

class TradeDto extends BaseDto<Trade> {
  const TradeDto();

  @override
  Trade fromRow(Map<String, dynamic> row) {
    return Trade(
      id: row['id'] as int?,
      userId: row['user_id'] as int,
      coinCandidateId: row['coin_candidate_id'] as int,
      chain: row['chain'] as String,
      contractAddress: row['contract_address'] as String,
      symbol: row['symbol'] as String,
      amountSpentNative: (row['amount_spent_native'] as num).toDouble(),
      amountSpentUsd: (row['amount_spent_usd'] as num).toDouble(),
      buyPriceUsd: (row['buy_price_usd'] as num).toDouble(),
      buyTxHash: row['buy_tx_hash'] as String?,
      boughtAt: row['bought_at'] != null
          ? DateTime.parse(row['bought_at'] as String)
          : null,
      sellPriceUsd: row['sell_price_usd'] != null
          ? (row['sell_price_usd'] as num).toDouble()
          : null,
      sellTxHash: row['sell_tx_hash'] as String?,
      soldAt: row['sold_at'] != null
          ? DateTime.parse(row['sold_at'] as String)
          : null,
      takeProfitPriceUsd: row['take_profit_price_usd'] != null
          ? (row['take_profit_price_usd'] as num).toDouble()
          : null,
      stopLossPriceUsd: row['stop_loss_price_usd'] != null
          ? (row['stop_loss_price_usd'] as num).toDouble()
          : null,
      realizedPnlUsd: row['realized_pnl_usd'] != null
          ? (row['realized_pnl_usd'] as num).toDouble()
          : null,
      roiPercent: row['roi_percent'] != null
          ? (row['roi_percent'] as num).toDouble()
          : null,
      closeReason: row['close_reason'] as String?,
      status: row['status'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  @override
  Map<String, dynamic> toRow(Trade model, {bool includeId = false}) {
    return {
      if (includeId && model.id != null) 'id': model.id,
      'user_id': model.userId,
      'coin_candidate_id': model.coinCandidateId,
      'chain': model.chain,
      'contract_address': model.contractAddress,
      'symbol': model.symbol,
      'amount_spent_native': model.amountSpentNative,
      'amount_spent_usd': model.amountSpentUsd,
      'buy_price_usd': model.buyPriceUsd,
      if (model.buyTxHash != null) 'buy_tx_hash': model.buyTxHash,
      if (model.boughtAt != null)
        'bought_at': model.boughtAt!.toIso8601String(),
      if (model.sellPriceUsd != null) 'sell_price_usd': model.sellPriceUsd,
      if (model.sellTxHash != null) 'sell_tx_hash': model.sellTxHash,
      if (model.soldAt != null) 'sold_at': model.soldAt!.toIso8601String(),
      if (model.takeProfitPriceUsd != null)
        'take_profit_price_usd': model.takeProfitPriceUsd,
      if (model.stopLossPriceUsd != null)
        'stop_loss_price_usd': model.stopLossPriceUsd,
      if (model.realizedPnlUsd != null)
        'realized_pnl_usd': model.realizedPnlUsd,
      if (model.roiPercent != null) 'roi_percent': model.roiPercent,
      if (model.closeReason != null) 'close_reason': model.closeReason,
      'status': model.status,
      'updated_at': model.updatedAt.toIso8601String(),
    };
  }
}
