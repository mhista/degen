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

abstract class User
    implements _i1.SerializableModel, _i1.ProtocolSerialization {
  User._({
    this.id,
    required this.telegramId,
    this.telegramUsername,
    required this.activeChain,
    this.walletAddress,
    required this.subscriptionTier,
    required this.isBotActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User({
    int? id,
    required int telegramId,
    String? telegramUsername,
    required String activeChain,
    String? walletAddress,
    required String subscriptionTier,
    required bool isBotActive,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _UserImpl;

  factory User.fromJson(Map<String, dynamic> jsonSerialization) {
    return User(
      id: jsonSerialization['id'] as int?,
      telegramId: jsonSerialization['telegramId'] as int,
      telegramUsername: jsonSerialization['telegramUsername'] as String?,
      activeChain: jsonSerialization['activeChain'] as String,
      walletAddress: jsonSerialization['walletAddress'] as String?,
      subscriptionTier: jsonSerialization['subscriptionTier'] as String,
      isBotActive: _i1.BoolJsonExtension.fromJson(
        jsonSerialization['isBotActive'],
      ),
      createdAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['createdAt'],
      ),
      updatedAt: _i1.DateTimeJsonExtension.fromJson(
        jsonSerialization['updatedAt'],
      ),
    );
  }

  int? id;

  int telegramId;

  String? telegramUsername;

  String activeChain;

  String? walletAddress;

  String subscriptionTier;

  bool isBotActive;

  DateTime createdAt;

  DateTime updatedAt;

  /// Returns a shallow copy of this [User]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  User copyWith({
    int? id,
    int? telegramId,
    String? telegramUsername,
    String? activeChain,
    String? walletAddress,
    String? subscriptionTier,
    bool? isBotActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'User',
      if (id != null) 'id': id,
      'telegramId': telegramId,
      if (telegramUsername != null) 'telegramUsername': telegramUsername,
      'activeChain': activeChain,
      if (walletAddress != null) 'walletAddress': walletAddress,
      'subscriptionTier': subscriptionTier,
      'isBotActive': isBotActive,
      'createdAt': createdAt.toJson(),
      'updatedAt': updatedAt.toJson(),
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'User',
      if (id != null) 'id': id,
      'telegramId': telegramId,
      if (telegramUsername != null) 'telegramUsername': telegramUsername,
      'activeChain': activeChain,
      if (walletAddress != null) 'walletAddress': walletAddress,
      'subscriptionTier': subscriptionTier,
      'isBotActive': isBotActive,
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

class _UserImpl extends User {
  _UserImpl({
    int? id,
    required int telegramId,
    String? telegramUsername,
    required String activeChain,
    String? walletAddress,
    required String subscriptionTier,
    required bool isBotActive,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : super._(
         id: id,
         telegramId: telegramId,
         telegramUsername: telegramUsername,
         activeChain: activeChain,
         walletAddress: walletAddress,
         subscriptionTier: subscriptionTier,
         isBotActive: isBotActive,
         createdAt: createdAt,
         updatedAt: updatedAt,
       );

  /// Returns a shallow copy of this [User]
  /// with some or all fields replaced by the given arguments.
  @_i1.useResult
  @override
  User copyWith({
    Object? id = _Undefined,
    int? telegramId,
    Object? telegramUsername = _Undefined,
    String? activeChain,
    Object? walletAddress = _Undefined,
    String? subscriptionTier,
    bool? isBotActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id is int? ? id : this.id,
      telegramId: telegramId ?? this.telegramId,
      telegramUsername: telegramUsername is String?
          ? telegramUsername
          : this.telegramUsername,
      activeChain: activeChain ?? this.activeChain,
      walletAddress: walletAddress is String?
          ? walletAddress
          : this.walletAddress,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      isBotActive: isBotActive ?? this.isBotActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
