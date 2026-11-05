import 'package:flutter/foundation.dart';

import 'api_client.dart';

class AiService {
  AiService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  static const errorPrefix = 'AI analysis failed:';

  final ApiClient _apiClient;

  Future<String> getMatchPrediction(String fixtureId) async {
    try {
      final analysis = await _apiClient.fetchAiAnalysis(fixtureId);
      final lines = [analysis.reply];
      final betslip = analysis.betslip;
      if (betslip != null && betslip.picks.isNotEmpty) {
        lines
          ..add('')
          ..add('Cautious betslip (${betslip.overallRisk} risk):');
        for (final pick in betslip.picks) {
          lines.add('${pick.match}: ${pick.market}');
        }
        lines.add(betslip.note);
      }
      return lines.join('\n');
    } catch (error) {
      debugPrint('AI ERROR: $error');
      return '$errorPrefix $error';
    }
  }
}
