// chaingpt_service.dart
//
// Wraps ChainGPT's InfoFI API for sentiment and social intelligence.
//
// WHY THIS LAYER MATTERS (plain English):
//   Everything so far (DexScreener, GoPlus, RugCheck, TokenSniffer) tells
//   you whether a token is SAFE. None of it tells you whether anyone
//   actually CARES about it. A perfectly safe token with zero social
//   interest usually just sits flat or dies quietly.
//
//   ChainGPT's InfoFI API gives you the "is anyone talking about this"
//   signal — mindshare score, sentiment (bullish/bearish/neutral), and
//   KOL (influencer) mention tracking. This is the difference between
//   a token that's safe-but-dead and a token that's safe-and-about-to-move.
//
// IMPORTANT HONESTY NOTE:
//   ChainGPT's sentiment coverage is strongest for tokens that already
//   have some market presence (top hundreds to low thousands by mcap).
//   Brand new, just-launched degen tokens often won't have ChainGPT
//   coverage yet — in that case this layer returns "no data" and the
//   AI scoring engine should weight Layer 4 lower / Layer 2-3 higher
//   for ultra-fresh launches. We handle this gracefully below.
//
// API: Requires API key. https://docs.chaingpt.org

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'token_intelligence_report.dart';

final _log = Logger('ChainGPTService');

class ChainGPTService {
  static const _baseUrl = 'https://api.chaingpt.org';

  final String _apiKey;
  late final Dio _dio;

  ChainGPTService({required String apiKey}) : _apiKey = apiKey {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Authorization': 'Bearer $_apiKey'},
    ));
  }

  /// Fetch sentiment + mindshare data for a token by symbol.
  /// Returns null if ChainGPT has no coverage for this token yet
  /// (common for brand-new degen launches).
  Future<({SentimentData data, List<IntelligenceFlag> flags})?>
      checkSentiment({
    required String symbol,
    required String tokenName,
  }) async {
    _log.info('ChainGPT sentiment check: $symbol');

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/infofi/v1/sentiment',
        queryParameters: {'symbol': symbol},
      );

      final data = response.data;
      if (data == null || data['found'] == false) {
        _log.info('No ChainGPT coverage for $symbol — likely too new');
        return null;
      }

      return _parseResponse(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _log.info('ChainGPT has no data for $symbol');
        return null;
      }
      _log.warning('ChainGPT API error: ${e.message}');
      return null;
    }
  }

  ({SentimentData data, List<IntelligenceFlag> flags}) _parseResponse(
    Map<String, dynamic> d,
  ) {
    final flags = <IntelligenceFlag>[];

    final mindshare = (d['mindshareScore'] as num?)?.toDouble();
    final sentimentScore = (d['sentimentScore'] as num?)?.toDouble() ?? 0.0;
    final sentimentLabel = d['sentimentLabel'] as String? ?? 'neutral';
    final kolMentions = d['kolMentionCount'] as int? ?? 0;
    final narrative = d['narrative'] as String?;
    final socialLinks = (d['socialLinks'] as List? ?? []).cast<String>();

    // Heuristic for organic vs artificial growth:
    // High KOL mentions + very high mindshare in a short window can mean
    // a coordinated pump rather than genuine community interest.
    final velocityFlag = d['mindshareVelocity'] as num?;
    final isOrganic = velocityFlag == null || velocityFlag.toDouble() < 5.0;

    if (!isOrganic) {
      flags.add(const IntelligenceFlag(
        source: 'ChainGPT',
        severity: FlagSeverity.medium,
        message:
            'Unusually rapid mindshare spike — may indicate coordinated promotion',
      ));
    }

    if (sentimentLabel == 'bearish' && sentimentScore < -0.5) {
      flags.add(const IntelligenceFlag(
        source: 'ChainGPT',
        severity: FlagSeverity.medium,
        message: 'Strongly bearish sentiment detected in social discussion',
      ));
    }

    if (socialLinks.isEmpty) {
      flags.add(const IntelligenceFlag(
        source: 'ChainGPT',
        severity: FlagSeverity.low,
        message: 'No verified social links found',
      ));
    }

    final sentimentData = SentimentData(
      mindshareScore: mindshare,
      sentimentLabel: sentimentLabel,
      sentimentScore: sentimentScore,
      kolMentionCount: kolMentions,
      isOrganicGrowth: isOrganic,
      narrativeMatch: narrative,
      socialLinks: socialLinks,
    );

    return (data: sentimentData, flags: flags);
  }
}
