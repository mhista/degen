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

abstract class RiskProfile implements _i1.SerializableModel {
  RiskProfile._({
    this.id,
    required this.userId,
    required this.maxTradePercent,
    required this.dailyTradeLimit,
    required this.tradesToday,
    required this.defaultTakeProfitPercent,
    required this.defaultStopLossPercent,
    required this.lastResetDate,
    required this.updatedAt,
  });

  factory RiskProfile({
    int? id,
    required int userId,
    required double maxTradePercent,
    required int dailyTradeLimit,
    required int tradesToday,
    required double defaultTakeProfitPercent,
    required double defaultStopLossPercent,
    required DateTime lastResetDate,
    required DateTime updatedAt,
  }) = _RiskProfileImpl;

  factory RiskProfile.fromJson(Map<String, dynamic> jsonSerialization) {
    return RiskProfile(
      id: jsonSerialization['id'] as int?,
      userId: jsonSerialization['userId'] as int,
      maxTradePercent: (jsonSerialization['maxTradePercent'] as num).toDouble(),
      dailyTradeLimit: jsonSerialization['dailyTradeLimit'] as int,
      tradesToday: jsonSerialization['tradesToday'] as int,
      defaultTakeProfitPercent:
          (jsonSerialization['defaultTakeProfitPercent'] as num).toDouble(),
      defaultStopLossPercent:
          (jsonSerialization['defaultStopLossPercent'] as num).toDouble(),
      lastResetDate: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['lastResetDate'],
      ),
      updatedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
    );
  }

  int? id;

  int userId;

  double maxTradePercent;

  int dailyTradeLimit;

  int tradesToday;

  double defaultTakeProfitPercent;

  double defaultStopLossPercent;

  DateTime lastResetDate;

  DateTime updatedAt;

  /// Returns a shallow copy of this [RiskProfile]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  RiskProfile copyWith({
    int? id,
    int? userId,
    double? maxTradePercent,
    int? dailyTradeLimit,
    int? tradesToday,
    double? defaultTakeProfitPercent,
    double? defaultStopLossPercent,
    DateTime? lastResetDate,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'RiskProfile',
      if (id != null) 'id': id,
      'userId': userId,
      'maxTradePercent': maxTradePercent,
      'dailyTradeLimit': dailyTradeLimit,
      'tradesToday': tradesToday,
      'defaultTakeProfitPercent': defaultTakeProfitPercent,
      'defaultStopLossPercent': defaultStopLossPercent,
      'lastResetDate': lastResetDate.toJson(),
      'updatedAt': updatedAt.toJson(),
    };
  }

  @override
  String toString() {
    return _i1.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _RiskProfileImpl extends RiskProfile {
  _RiskProfileImpl({
    int? id,
    required int userId,
    required double maxTradePercent,
    required int dailyTradeLimit,
    required int tradesToday,
    required double defaultTakeProfitPercent,
    required double defaultStopLossPercent,
    required DateTime lastResetDate,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         userId: userId,
         maxTradePercent: maxTradePercent,
         dailyTradeLimit: dailyTradeLimit,
         tradesToday: tradesToday,
         defaultTakeProfitPercent: defaultTakeProfitPercent,
         defaultStopLossPercent: defaultStopLossPercent,
         lastResetDate: lastResetDate,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [RiskProfile]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  RiskProfile copyWith({
    Object? id = _Undefined,
    int? userId,
    double? maxTradePercent,
    int? dailyTradeLimit,
    int? tradesToday,
    double? defaultTakeProfitPercent,
    double? defaultStopLossPercent,
    DateTime? lastResetDate,
    DateTime? updatedAt,
  }) {
    return RiskProfile(
      id: id is int? ? id : this.id,
      userId: userId ?? this.userId,
      maxTradePercent: maxTradePercent ?? this.maxTradePercent,
      dailyTradeLimit: dailyTradeLimit ?? this.dailyTradeLimit,
      tradesToday: tradesToday ?? this.tradesToday,
      defaultTakeProfitPercent:
          defaultTakeProfitPercent ?? this.defaultTakeProfitPercent,
      defaultStopLossPercent:
          defaultStopLossPercent ?? this.defaultStopLossPercent,
      lastResetDate: lastResetDate ?? this.lastResetDate,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
