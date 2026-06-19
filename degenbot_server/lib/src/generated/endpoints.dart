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
import '../endpoints/health_endpoint.dart' as _i2;
import '../endpoints/trade_endpoint.dart' as _i3;
import '../endpoints/user_endpoint.dart' as _i4;

class Endpoints extends _i1.EndpointDispatch {
  @override
  void initializeEndpoints(_i1.Server server) {
    var endpoints = <String, _i1.Endpoint>{
      'health': _i2.HealthEndpoint()
        ..initialize(
          server,
          'health',
          null,
        ),
      'trade': _i3.TradeEndpoint()
        ..initialize(
          server,
          'trade',
          null,
        ),
      'user': _i4.UserEndpoint()
        ..initialize(
          server,
          'user',
          null,
        ),
    };
    connectors['health'] = _i1.EndpointConnector(
      name: 'health',
      endpoint: endpoints['health']!,
      methodConnectors: {
        'check': _i1.MethodConnector(
          name: 'check',
          params: {},
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['health'] as _i2.HealthEndpoint).check(session),
        ),
      },
    );
    connectors['trade'] = _i1.EndpointConnector(
      name: 'trade',
      endpoint: endpoints['trade']!,
      methodConnectors: {
        'getHistory': _i1.MethodConnector(
          name: 'getHistory',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'limit': _i1.ParameterDescription(
              name: 'limit',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['trade'] as _i3.TradeEndpoint).getHistory(
                session,
                params['telegramId'],
                limit: params['limit'],
              ),
        ),
        'getOpenPositions': _i1.MethodConnector(
          name: 'getOpenPositions',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['trade'] as _i3.TradeEndpoint).getOpenPositions(
                    session,
                    params['telegramId'],
                  ),
        ),
        'getRiskProfile': _i1.MethodConnector(
          name: 'getRiskProfile',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['trade'] as _i3.TradeEndpoint).getRiskProfile(
                    session,
                    params['telegramId'],
                  ),
        ),
        'updateRiskSetting': _i1.MethodConnector(
          name: 'updateRiskSetting',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'field': _i1.ParameterDescription(
              name: 'field',
              type: _i1.getType<String>(),
              nullable: false,
            ),
            'value': _i1.ParameterDescription(
              name: 'value',
              type: _i1.getType<double>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['trade'] as _i3.TradeEndpoint).updateRiskSetting(
                    session,
                    params['telegramId'],
                    params['field'],
                    params['value'],
                  ),
        ),
        'getSummaryStats': _i1.MethodConnector(
          name: 'getSummaryStats',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['trade'] as _i3.TradeEndpoint).getSummaryStats(
                    session,
                    params['telegramId'],
                  ),
        ),
      },
    );
    connectors['user'] = _i1.EndpointConnector(
      name: 'user',
      endpoint: endpoints['user']!,
      methodConnectors: {
        'registerOrGet': _i1.MethodConnector(
          name: 'registerOrGet',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'telegramUsername': _i1.ParameterDescription(
              name: 'telegramUsername',
              type: _i1.getType<String?>(),
              nullable: true,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['user'] as _i4.UserEndpoint).registerOrGet(
                session,
                params['telegramId'],
                params['telegramUsername'],
              ),
        ),
        'setBotActive': _i1.MethodConnector(
          name: 'setBotActive',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'active': _i1.ParameterDescription(
              name: 'active',
              type: _i1.getType<bool>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['user'] as _i4.UserEndpoint).setBotActive(
                session,
                params['telegramId'],
                params['active'],
              ),
        ),
        'setWalletAddress': _i1.MethodConnector(
          name: 'setWalletAddress',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'address': _i1.ParameterDescription(
              name: 'address',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async =>
                  (endpoints['user'] as _i4.UserEndpoint).setWalletAddress(
                    session,
                    params['telegramId'],
                    params['address'],
                  ),
        ),
        'setActiveChain': _i1.MethodConnector(
          name: 'setActiveChain',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
            'chain': _i1.ParameterDescription(
              name: 'chain',
              type: _i1.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['user'] as _i4.UserEndpoint).setActiveChain(
                session,
                params['telegramId'],
                params['chain'],
              ),
        ),
        'getStatus': _i1.MethodConnector(
          name: 'getStatus',
          params: {
            'telegramId': _i1.ParameterDescription(
              name: 'telegramId',
              type: _i1.getType<int>(),
              nullable: false,
            ),
          },
          call:
              (
                _i1.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['user'] as _i4.UserEndpoint).getStatus(
                session,
                params['telegramId'],
              ),
        ),
      },
    );
  }
}
