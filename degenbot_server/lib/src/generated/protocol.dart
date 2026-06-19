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
import 'package:serverpod/protocol.dart' as _i2;
import 'coin_candidate.dart' as _i3;
import 'risk_profile.dart' as _i4;
import 'trade.dart' as _i5;
import 'user.dart' as _i6;
import 'package:degenbot_server/src/generated/trade.dart' as _i7;
export 'coin_candidate.dart';
export 'risk_profile.dart';
export 'trade.dart';
export 'user.dart';

class Protocol extends _i1.SerializationManagerServer {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._();

  static final List<_i2.TableDefinition> targetTableDefinitions = [
    ..._i2.Protocol.targetTableDefinitions,
  ];

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

    if (t == _i3.CoinCandidate) {
      return _i3.CoinCandidate.fromJson(data) as T;
    }
    if (t == _i4.RiskProfile) {
      return _i4.RiskProfile.fromJson(data) as T;
    }
    if (t == _i5.Trade) {
      return _i5.Trade.fromJson(data) as T;
    }
    if (t == _i6.User) {
      return _i6.User.fromJson(data) as T;
    }
    if (t == _i1.getType<_i3.CoinCandidate?>()) {
      return (data != null ? _i3.CoinCandidate.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i4.RiskProfile?>()) {
      return (data != null ? _i4.RiskProfile.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i5.Trade?>()) {
      return (data != null ? _i5.Trade.fromJson(data) : null) as T;
    }
    if (t == _i1.getType<_i6.User?>()) {
      return (data != null ? _i6.User.fromJson(data) : null) as T;
    }
    if (t == Map<String, dynamic>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<dynamic>(v)),
          )
          as T;
    }
    if (t == List<_i7.Trade>) {
      return (data as List).map((e) => deserialize<_i7.Trade>(e)).toList() as T;
    }
    try {
      return _i2.Protocol().deserialize<T>(data, t);
    } on _i1.DeserializationTypeNotFoundException catch (_) {}
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _i3.CoinCandidate => 'CoinCandidate',
      _i4.RiskProfile => 'RiskProfile',
      _i5.Trade => 'Trade',
      _i6.User => 'User',
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
      case _i3.CoinCandidate():
        return 'CoinCandidate';
      case _i4.RiskProfile():
        return 'RiskProfile';
      case _i5.Trade():
        return 'Trade';
      case _i6.User():
        return 'User';
    }
    className = _i2.Protocol().getClassNameForObject(data);
    if (className != null) {
      return 'serverpod.$className';
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
      return deserialize<_i3.CoinCandidate>(data['data']);
    }
    if (dataClassName == 'RiskProfile') {
      return deserialize<_i4.RiskProfile>(data['data']);
    }
    if (dataClassName == 'Trade') {
      return deserialize<_i5.Trade>(data['data']);
    }
    if (dataClassName == 'User') {
      return deserialize<_i6.User>(data['data']);
    }
    if (dataClassName.startsWith('serverpod.')) {
      data['className'] = dataClassName.substring(10);
      return _i2.Protocol().deserializeByClassName(data);
    }
    return super.deserializeByClassName(data);
  }

  @override
  _i1.Table? getTableForType(Type t) {
    {
      var table = _i2.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    return null;
  }

  @override
  List<_i2.TableDefinition> getTargetTableDefinitions() =>
      targetTableDefinitions;

  @override
  String getModuleName() => 'degenbot';

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    try {
      return _i2.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
