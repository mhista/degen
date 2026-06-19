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
import 'package:serverpod/serverpod.dart' as _i1;

abstract class CoinCandidate
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  CoinCandidate._({
    this.id,
    required this.chain,
    required this.contractAddress,
    required this.name,
    required this.symbol,
    required this.aiScore,
    required this.liquidityUsd,
    required this.volumeUsd24h,
    required this.priceUsd,
    this.marketCapUsd,
    this.holderCount,
    this.priceChange1h,
    this.priceChange6h,
    this.priceChange24h,
    this.aiReasoning,
    required this.status,
    required this.scannedAt,
  });

  factory CoinCandidate({
    int? id,
    required String chain,
    required String contractAddress,
    required String name,
    required String symbol,
    required int aiScore,
    required double liquidityUsd,
    required double volumeUsd24h,
    required double priceUsd,
    double? marketCapUsd,
    int? holderCount,
    double? priceChange1h,
    double? priceChange6h,
    double? priceChange24h,
    String? aiReasoning,
    required String status,
    required DateTime scannedAt,
  }) = _CoinCandidateImpl;

  factory CoinCandidate.fromJson(Map<String, dynamic> jsonSerialization) {
    return CoinCandidate(
      id: jsonSerialization['id'] as int?,
      chain: jsonSerialization['chain'] as String,
      contractAddress: jsonSerialization['contractAddress'] as String,
      name: jsonSerialization['name'] as String,
      symbol: jsonSerialization['symbol'] as String,
      aiScore: jsonSerialization['aiScore'] as int,
      liquidityUsd: (jsonSerialization['liquidityUsd'] as num).toDouble(),
      volumeUsd24h: (jsonSerialization['volumeUsd24h'] as num).toDouble(),
      priceUsd: (jsonSerialization['priceUsd'] as num).toDouble(),
      marketCapUsd: (jsonSerialization['marketCapUsd'] as num?)?.toDouble(),
      holderCount: jsonSerialization['holderCount'] as int?,
      priceChange1h: (jsonSerialization['priceChange1h'] as num?)?.toDouble(),
      priceChange6h: (jsonSerialization['priceChange6h'] as num?)?.toDouble(),
      priceChange24h: (jsonSerialization['priceChange24h'] as num?)?.toDouble(),
      aiReasoning: jsonSerialization['aiReasoning'] as String?,
      status: jsonSerialization['status'] as String,
      scannedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['scannedAt'],
      ),
    );
  }

  int? id;

  String chain;

  String contractAddress;

  String name;

  String symbol;

  int aiScore;

  double liquidityUsd;

  double volumeUsd24h;

  double priceUsd;

  double? marketCapUsd;

  int? holderCount;

  double? priceChange1h;

  double? priceChange6h;

  double? priceChange24h;

  String? aiReasoning;

  String status;

  DateTime scannedAt;

  /// Returns a shallow copy of this [CoinCandidate]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  CoinCandidate copyWith({
    int? id,
    String? chain,
    String? contractAddress,
    String? name,
    String? symbol,
    int? aiScore,
    double? liquidityUsd,
    double? volumeUsd24h,
    double? priceUsd,
    double? marketCapUsd,
    int? holderCount,
    double? priceChange1h,
    double? priceChange6h,
    double? priceChange24h,
    String? aiReasoning,
    String? status,
    DateTime? scannedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'CoinCandidate',
      if (id != null) 'id': id,
      'chain': chain,
      'contractAddress': contractAddress,
      'name': name,
      'symbol': symbol,
      'aiScore': aiScore,
      'liquidityUsd': liquidityUsd,
      'volumeUsd24h': volumeUsd24h,
      'priceUsd': priceUsd,
      if (marketCapUsd != null) 'marketCapUsd': marketCapUsd,
      if (holderCount != null) 'holderCount': holderCount,
      if (priceChange1h != null) 'priceChange1h': priceChange1h,
      if (priceChange6h != null) 'priceChange6h': priceChange6h,
      if (priceChange24h != null) 'priceChange24h': priceChange24h,
      if (aiReasoning != null) 'aiReasoning': aiReasoning,
      'status': status,
      'scannedAt': scannedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'CoinCandidate',
      if (id != null) 'id': id,
      'chain': chain,
      'contractAddress': contractAddress,
      'name': name,
      'symbol': symbol,
      'aiScore': aiScore,
      'liquidityUsd': liquidityUsd,
      'volumeUsd24h': volumeUsd24h,
      'priceUsd': priceUsd,
      if (marketCapUsd != null) 'marketCapUsd': marketCapUsd,
      if (holderCount != null) 'holderCount': holderCount,
      if (priceChange1h != null) 'priceChange1h': priceChange1h,
      if (priceChange6h != null) 'priceChange6h': priceChange6h,
      if (priceChange24h != null) 'priceChange24h': priceChange24h,
      if (aiReasoning != null) 'aiReasoning': aiReasoning,
      'status': status,
      'scannedAt': scannedAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _CoinCandidateImpl extends CoinCandidate {
  _CoinCandidateImpl({
    int? id,
    required String chain,
    required String contractAddress,
    required String name,
    required String symbol,
    required int aiScore,
    required double liquidityUsd,
    required double volumeUsd24h,
    required double priceUsd,
    double? marketCapUsd,
    int? holderCount,
    double? priceChange1h,
    double? priceChange6h,
    double? priceChange24h,
    String? aiReasoning,
    required String status,
    required DateTime scannedAt,
  }) : super._(
         id: id,
         chain: chain,
         contractAddress: contractAddress,
         name: name,
         symbol: symbol,
         aiScore: aiScore,
         liquidityUsd: liquidityUsd,
         volumeUsd24h: volumeUsd24h,
         priceUsd: priceUsd,
         marketCapUsd: marketCapUsd,
         holderCount: holderCount,
         priceChange1h: priceChange1h,
         priceChange6h: priceChange6h,
         priceChange24h: priceChange24h,
         aiReasoning: aiReasoning,
         status: status,
         scannedAt: scannedAt,
       );

  /// Returns a shallow copy of this [CoinCandidate]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  CoinCandidate copyWith({
    Object? id = _Undefined,
    String? chain,
    String? contractAddress,
    String? name,
    String? symbol,
    int? aiScore,
    double? liquidityUsd,
    double? volumeUsd24h,
    double? priceUsd,
    Object? marketCapUsd = _Undefined,
    Object? holderCount = _Undefined,
    Object? priceChange1h = _Undefined,
    Object? priceChange6h = _Undefined,
    Object? priceChange24h = _Undefined,
    Object? aiReasoning = _Undefined,
    String? status,
    DateTime? scannedAt,
  }) {
    return CoinCandidate(
      id: id is int? ? id : this.id,
      chain: chain ?? this.chain,
      contractAddress: contractAddress ?? this.contractAddress,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      aiScore: aiScore ?? this.aiScore,
      liquidityUsd: liquidityUsd ?? this.liquidityUsd,
      volumeUsd24h: volumeUsd24h ?? this.volumeUsd24h,
      priceUsd: priceUsd ?? this.priceUsd,
      marketCapUsd: marketCapUsd is double? ? marketCapUsd : this.marketCapUsd,
      holderCount: holderCount is int? ? holderCount : this.holderCount,
      priceChange1h: priceChange1h is double?
          ? priceChange1h
          : this.priceChange1h,
      priceChange6h: priceChange6h is double?
          ? priceChange6h
          : this.priceChange6h,
      priceChange24h: priceChange24h is double?
          ? priceChange24h
          : this.priceChange24h,
      aiReasoning: aiReasoning is String? ? aiReasoning : this.aiReasoning,
      status: status ?? this.status,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }
}
