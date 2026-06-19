/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod_client/serverpod_client.dart' as _i1;

abstract class Trade implements _i1.SerializableModel {
  Trade._({
    this.id,
    required this.userId,
    required this.coinCandidateId,
    required this.chain,
    required this.contractAddress,
    required this.symbol,
    required this.amountSpentNative,
    required this.amountSpentUsd,
    required this.buyPriceUsd,
    this.buyTxHash,
    this.boughtAt,
    this.sellPriceUsd,
    this.sellTxHash,
    this.soldAt,
    this.takeProfitPriceUsd,
    this.stopLossPriceUsd,
    this.realizedPnlUsd,
    this.roiPercent,
    this.closeReason,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Trade({
    int? id,
    required int userId,
    required int coinCandidateId,
    required String chain,
    required String contractAddress,
    required String symbol,
    required double amountSpentNative,
    required double amountSpentUsd,
    required double buyPriceUsd,
    String? buyTxHash,
    DateTime? boughtAt,
    double? sellPriceUsd,
    String? sellTxHash,
    DateTime? soldAt,
    double? takeProfitPriceUsd,
    double? stopLossPriceUsd,
    double? realizedPnlUsd,
    double? roiPercent,
    String? closeReason,
    required String status,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _TradeImpl;

  factory Trade.fromJson(Map<String, dynamic> jsonSerialization) {
    return Trade(
      id: jsonSerialization['id'] as int?,
      userId: jsonSerialization['userId'] as int,
      coinCandidateId: jsonSerialization['coinCandidateId'] as int,
      chain: jsonSerialization['chain'] as String,
      contractAddress: jsonSerialization['contractAddress'] as String,
      symbol: jsonSerialization['symbol'] as String,
      amountSpentNative: (jsonSerialization['amountSpentNative'] as num)
          .toDouble(),
      amountSpentUsd: (jsonSerialization['amountSpentUsd'] as num).toDouble(),
      buyPriceUsd: (jsonSerialization['buyPriceUsd'] as num).toDouble(),
      buyTxHash: jsonSerialization['buyTxHash'] as String?,
      boughtAt: jsonSerialization['boughtAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['boughtAt']),
      sellPriceUsd: (jsonSerialization['sellPriceUsd'] as num?)?.toDouble(),
      sellTxHash: jsonSerialization['sellTxHash'] as String?,
      soldAt: jsonSerialization['soldAt'] == null
          ? null
          : _i1.DateTimeJsonExtension.fromJson(jsonSerialization['soldAt']),
      takeProfitPriceUsd: (jsonSerialization['takeProfitPriceUsd'] as num?)
          ?.toDouble(),
      stopLossPriceUsd: (jsonSerialization['stopLossPriceUsd'] as num?)
          ?.toDouble(),
      realizedPnlUsd: (jsonSerialization['realizedPnlUsd'] as num?)?.toDouble(),
      roiPercent: (jsonSerialization['roiPercent'] as num?)?.toDouble(),
      closeReason: jsonSerialization['closeReason'] as String?,
      status: jsonSerialization['status'] as String,
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      updatedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
    );
  }

  int? id;

  int userId;

  int coinCandidateId;

  String chain;

  String contractAddress;

  String symbol;

  double amountSpentNative;

  double amountSpentUsd;

  double buyPriceUsd;

  String? buyTxHash;

  DateTime? boughtAt;

  double? sellPriceUsd;

  String? sellTxHash;

  DateTime? soldAt;

  double? takeProfitPriceUsd;

  double? stopLossPriceUsd;

  double? realizedPnlUsd;

  double? roiPercent;

  String? closeReason;

  String status;

  DateTime createdAt;

  DateTime updatedAt;

  /// Returns a shallow copy of this [Trade]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  Trade copyWith({
    int? id,
    int? userId,
    int? coinCandidateId,
    String? chain,
    String? contractAddress,
    String? symbol,
    double? amountSpentNative,
    double? amountSpentUsd,
    double? buyPriceUsd,
    String? buyTxHash,
    DateTime? boughtAt,
    double? sellPriceUsd,
    String? sellTxHash,
    DateTime? soldAt,
    double? takeProfitPriceUsd,
    double? stopLossPriceUsd,
    double? realizedPnlUsd,
    double? roiPercent,
    String? closeReason,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'Trade',
      if (id != null) 'id': id,
      'userId': userId,
      'coinCandidateId': coinCandidateId,
      'chain': chain,
      'contractAddress': contractAddress,
      'symbol': symbol,
      'amountSpentNative': amountSpentNative,
      'amountSpentUsd': amountSpentUsd,
      'buyPriceUsd': buyPriceUsd,
      if (buyTxHash != null) 'buyTxHash': buyTxHash,
      if (boughtAt != null) 'boughtAt': boughtAt?.toJson(),
      if (sellPriceUsd != null) 'sellPriceUsd': sellPriceUsd,
      if (sellTxHash != null) 'sellTxHash': sellTxHash,
      if (soldAt != null) 'soldAt': soldAt?.toJson(),
      if (takeProfitPriceUsd != null) 'takeProfitPriceUsd': takeProfitPriceUsd,
      if (stopLossPriceUsd != null) 'stopLossPriceUsd': stopLossPriceUsd,
      if (realizedPnlUsd != null) 'realizedPnlUsd': realizedPnlUsd,
      if (roiPercent != null) 'roiPercent': roiPercent,
      if (closeReason != null) 'closeReason': closeReason,
      'status': status,
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _TradeImpl extends Trade {
  _TradeImpl({
    int? id,
    required int userId,
    required int coinCandidateId,
    required String chain,
    required String contractAddress,
    required String symbol,
    required double amountSpentNative,
    required double amountSpentUsd,
    required double buyPriceUsd,
    String? buyTxHash,
    DateTime? boughtAt,
    double? sellPriceUsd,
    String? sellTxHash,
    DateTime? soldAt,
    double? takeProfitPriceUsd,
    double? stopLossPriceUsd,
    double? realizedPnlUsd,
    double? roiPercent,
    String? closeReason,
    required String status,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         userId: userId,
         coinCandidateId: coinCandidateId,
         chain: chain,
         contractAddress: contractAddress,
         symbol: symbol,
         amountSpentNative: amountSpentNative,
         amountSpentUsd: amountSpentUsd,
         buyPriceUsd: buyPriceUsd,
         buyTxHash: buyTxHash,
         boughtAt: boughtAt,
         sellPriceUsd: sellPriceUsd,
         sellTxHash: sellTxHash,
         soldAt: soldAt,
         takeProfitPriceUsd: takeProfitPriceUsd,
         stopLossPriceUsd: stopLossPriceUsd,
         realizedPnlUsd: realizedPnlUsd,
         roiPercent: roiPercent,
         closeReason: closeReason,
         status: status,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [Trade]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  Trade copyWith({
    Object? id = _Undefined,
    int? userId,
    int? coinCandidateId,
    String? chain,
    String? contractAddress,
    String? symbol,
    double? amountSpentNative,
    double? amountSpentUsd,
    double? buyPriceUsd,
    Object? buyTxHash = _Undefined,
    Object? boughtAt = _Undefined,
    Object? sellPriceUsd = _Undefined,
    Object? sellTxHash = _Undefined,
    Object? soldAt = _Undefined,
    Object? takeProfitPriceUsd = _Undefined,
    Object? stopLossPriceUsd = _Undefined,
    Object? realizedPnlUsd = _Undefined,
    Object? roiPercent = _Undefined,
    Object? closeReason = _Undefined,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Trade(
      id: id is int? ? id : this.id,
      userId: userId ?? this.userId,
      coinCandidateId: coinCandidateId ?? this.coinCandidateId,
      chain: chain ?? this.chain,
      contractAddress: contractAddress ?? this.contractAddress,
      symbol: symbol ?? this.symbol,
      amountSpentNative: amountSpentNative ?? this.amountSpentNative,
      amountSpentUsd: amountSpentUsd ?? this.amountSpentUsd,
      buyPriceUsd: buyPriceUsd ?? this.buyPriceUsd,
      buyTxHash: buyTxHash is String? ? buyTxHash : this.buyTxHash,
      boughtAt: boughtAt is DateTime? ? boughtAt : this.boughtAt,
      sellPriceUsd: sellPriceUsd is double? ? sellPriceUsd : this.sellPriceUsd,
      sellTxHash: sellTxHash is String? ? sellTxHash : this.sellTxHash,
      soldAt: soldAt is DateTime? ? soldAt : this.soldAt,
      takeProfitPriceUsd: takeProfitPriceUsd is double?
          ? takeProfitPriceUsd
          : this.takeProfitPriceUsd,
      stopLossPriceUsd: stopLossPriceUsd is double?
          ? stopLossPriceUsd
          : this.stopLossPriceUsd,
      realizedPnlUsd: realizedPnlUsd is double?
          ? realizedPnlUsd
          : this.realizedPnlUsd,
      roiPercent: roiPercent is double? ? roiPercent : this.roiPercent,
      closeReason: closeReason is String? ? closeReason : this.closeReason,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
