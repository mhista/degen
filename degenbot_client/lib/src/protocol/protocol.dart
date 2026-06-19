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
import 'coin_candidate.dart' as _i2;
import 'risk_profile.dart' as _i3;
import 'trade.dart' as _i4;
import 'user.dart' as _i5;
import 'package:degenbot_client/src/protocol/trade.dart' as _i6;
export 'coin_candidate.dart';
export 'risk_profile.dart';
export 'trade.dart';
export 'user.dart';
export 'client.dart';

class Protocol extends _i1.SerializationManager {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._();

  static String? getClassNameFromObjectJson(dynamic data) {
    if (data is! Map) return null;
    final className = data['__className__'] as String?;
    return className;
  }

  @override
  T deserialize<T>(
    dynamic data, [
    Type? t,
  ]) {
    t ??= T;

    final dataClassName = getClassNameFromObjectJson(data);
    if (dataClassName != null && dataClassName != getClassNameForType(t)) {
      try {
        return deserializeByClassName({
          'className': dataClassName,
          'data': data,
        });
      } on FormatException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _i2.CoinCandidate) {
      return _i2.CoinCandidate.fromJson(data) as T;
    }
    if (t == _i3.RiskProfile) {
      return _i3.RiskProfile.fromJson(data) as T;
    }
    if (t == _i4.Trade) {
      return _i4.Trade.fromJson(data) as T;
    }
    if (t == _i5.User) {
      return _i5.User.fromJson(data) as T;
    }
    if (t == _i1.getType<_i2.CoinCandidate?>()) {
      return (data != null ? _i2.CoinCandidate.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i3.RiskProfile?>()) {
      return (data != null ? _i3.RiskProfile.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i4.Trade?>()) {
      return (data != null ? _i4.Trade.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i5.User?>()) {
      return (data != null ? _i5.User.fromJson(data) : null) as T;
    }
    if (t == Map<String, dynamic>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<dynamic>(v)),
          )
          as T;
    }
    if (t == List<_i6.Trade>) {
      return (data as List).map((e) => deserialize<_i6.Trade>(e)).toList() as T;
    }
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _i2.CoinCandidate => 'CoinCandidate',
      _i3.RiskProfile => 'RiskProfile',
      _i4.Trade => 'Trade',
      _i5.User => 'User',
      _ => null,
    };
  }

  @override
  String? getClassNameForObject(Object? data) {
    String? className = super.getClassNameForObject(data);
    if (className != null) return className;

    if (data is Map<String, dynamic> && data['__className__'] is String) {
      return (data['__className__'] as String).replaceFirst('degenbot.', '');
    }

    switch (data) {
      case _i2.CoinCandidate():
        return 'CoinCandidate';
      case _i3.RiskProfile():
        return 'RiskProfile';
      case _i4.Trade():
        return 'Trade';
      case _i5.User():
        return 'User';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'CoinCandidate') {
      return deserialize<_i2.CoinCandidate>(data['data']);
    }
    if (dataClassName == 'RiskProfile') {
      return deserialize<_i3.RiskProfile>(data['data']);
    }
    if (dataClassName == 'Trade') {
      return deserialize<_i4.Trade>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i5.User>(data['data']);
    }
    return super.deserializeByClassName(data);
  }

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
