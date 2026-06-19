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
import 'dart:async' as _i2;
import 'package:degenbot_client/src/protocol/trade.dart' as _i3;
import 'package:degenbot_client/src/protocol/risk_profile.dart' as _i4;
import 'package:degenbot_client/src/protocol/user.dart' as _i5;
import 'protocol.dart' as _i6;

/// {@category Endpoint}
class EndpointHealth extends _i1.EndpointRef {
  EndpointHealth(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'health';

  _i2.Future<Map<String, dynamic>> check() =>
      caller.callServerEndpoint<Map<String, dynamic>>(
        'health',
        'check',
        {},
      );
}

/// {@category Endpoint}
class EndpointTrade extends _i1.EndpointRef {
  EndpointTrade(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'trade';

  /// Last N closed trades for a user — shown in /history command.
  _i2.Future<List<_i3.Trade>> getHistory(
    int telegramId, {
    required int limit,
  }) => caller.callServerEndpoint<List<_i3.Trade>>(
    'trade',
    'getHistory',
    {
      'telegramId': telegramId,
      'limit': limit,
    },
  );

  /// Open positions — shown in /positions command.
  _i2.Future<List<_i3.Trade>> getOpenPositions(int telegramId) =>
      caller.callServerEndpoint<List<_i3.Trade>>(
        'trade',
        'getOpenPositions',
        {'telegramId': telegramId},
      );

  /// Get the user's current risk settings — shown in /risk command.
  _i2.Future<_i4.RiskProfile> getRiskProfile(int telegramId) =>
      caller.callServerEndpoint<_i4.RiskProfile>(
        'trade',
        'getRiskProfile',
        {'telegramId': telegramId},
      );

  /// Update a single risk setting.
  /// field: 'max_trade_percent' | 'daily_trade_limit' |
  ///        'take_profit_percent' | 'stop_loss_percent'
  _i2.Future<_i4.RiskProfile> updateRiskSetting(
    int telegramId,
    String field,
    double value,
  ) => caller.callServerEndpoint<_i4.RiskProfile>(
    'trade',
    'updateRiskSetting',
    {
      'telegramId': telegramId,
      'field': field,
      'value': value,
    },
  );

  /// ROI summary — total PnL, win rate, best/worst trade.
  /// Used by /stats command.
  _i2.Future<Map<String, dynamic>> getSummaryStats(int telegramId) =>
      caller.callServerEndpoint<Map<String, dynamic>>(
        'trade',
        'getSummaryStats',
        {'telegramId': telegramId},
      );
}

/// {@category Endpoint}
class EndpointUser extends _i1.EndpointRef {
  EndpointUser(_i1.EndpointCaller caller) : super(caller);

  @override
  String get name => 'user';

  /// Called when a Telegram user sends /start for the first time.
  /// Creates the user if they don't exist, returns the user record.
  _i2.Future<_i5.User> registerOrGet(
    int telegramId,
    String? telegramUsername,
  ) => caller.callServerEndpoint<_i5.User>(
    'user',
    'registerOrGet',
    {
      'telegramId': telegramId,
      'telegramUsername': telegramUsername,
    },
  );

  /// Toggle the trading bot on/off for a user.
  _i2.Future<bool> setBotActive(
    int telegramId,
    bool active,
  ) => caller.callServerEndpoint<bool>(
    'user',
    'setBotActive',
    {
      'telegramId': telegramId,
      'active': active,
    },
  );

  /// Save the user's public wallet address for the active chain.
  /// NOTE: we NEVER store private keys — only public addresses.
  _i2.Future<_i5.User> setWalletAddress(
    int telegramId,
    String address,
  ) => caller.callServerEndpoint<_i5.User>(
    'user',
    'setWalletAddress',
    {
      'telegramId': telegramId,
      'address': address,
    },
  );

  /// Switch the active blockchain chain.
  _i2.Future<_i5.User> setActiveChain(
    int telegramId,
    String chain,
  ) => caller.callServerEndpoint<_i5.User>(
    'user',
    'setActiveChain',
    {
      'telegramId': telegramId,
      'chain': chain,
    },
  );

  /// Get a user's full status snapshot for the Telegram dashboard.
  _i2.Future<Map<String, dynamic>> getStatus(int telegramId) =>
      caller.callServerEndpoint<Map<String, dynamic>>(
        'user',
        'getStatus',
        {'telegramId': telegramId},
      );
}

class Client extends _i1.ServerpodClientShared {
  Client(
    String host, {
    dynamic securityContext,
    @Deprecated(
      'Use authKeyProvider instead. This will be removed in future releases.',
    )
    super.authenticationKeyManager,
    Duration? streamingConnectionTimeout,
    Duration? connectionTimeout,
    Function(
      _i1.MethodCallContext,
      Object,
      StackTrace,
    )?
    onFailedCall,
    Function(_i1.MethodCallContext)? onSucceededCall,
    bool? disconnectStreamsOnLostInternetConnection,
  }) : super(
         host,
         _i6.Protocol(),
         securityContext: securityContext,
         streamingConnectionTimeout: streamingConnectionTimeout,
         connectionTimeout: connectionTimeout,
         onFailedCall: onFailedCall,
         onSucceededCall: onSucceededCall,
         disconnectStreamsOnLostInternetConnection:
             disconnectStreamsOnLostInternetConnection,
       ) {
    health = EndpointHealth(this);
    trade = EndpointTrade(this);
    user = EndpointUser(this);
  }

  late final EndpointHealth health;

  late final EndpointTrade trade;

  late final EndpointUser user;

  @override
  Map<String, _i1.EndpointRef> get endpointRefLookup => {
    'health': health,
    'trade': trade,
    'user': user,
  };

  @override
  Map<String, _i1.ModuleEndpointCaller> get moduleLookup => {};
}
