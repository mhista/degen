// health_endpoint.dart
//
// GET /health → returns {"status": "ok", "timestamp": "..."}
//
// Used by:
//   • Docker HEALTHCHECK instruction
//   • Fly.io / Railway deployment health probes
//   • Your own monitoring (uptime robot, etc.)
//
// This endpoint has zero dependencies — if it fails, the server is down.

import 'package:serverpod/serverpod.dart';

class HealthEndpoint extends Endpoint {
  Future<Map<String, dynamic>> check(Session session) async {
    return {
      'status': 'ok',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'service': 'degenbot',
    };
  }
}
