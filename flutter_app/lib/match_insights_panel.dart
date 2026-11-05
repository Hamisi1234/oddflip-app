import 'package:flutter/material.dart';

import 'ai_service.dart';
import 'app_loading_indicator.dart';
import 'models.dart';

class MatchInsightsPanel extends StatefulWidget {
  const MatchInsightsPanel({
    required this.fixture,
    required this.events,
    required this.insights,
    this.error,
    super.key,
  });

  final LiveFixture fixture;
  final List<MatchEvent> events;
  final MatchInsights? insights;
  final String? error;

  @override
  State<MatchInsightsPanel> createState() => _MatchInsightsPanelState();
}

class _MatchInsightsPanelState extends State<MatchInsightsPanel> {
  final _aiService = AiService();
  bool _aiLoading = false;
  String? _aiError;
  String? _aiAnalysis;

  LiveFixture get fixture => widget.fixture;
  List<MatchEvent> get events => widget.events;
  MatchInsights? get insights => widget.insights;
  String? get error => widget.error;

  Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  double? _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  String _count(double? value) =>
      value == null ? '—' : value.round().toString();

  @override
  void didUpdateWidget(covariant MatchInsightsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fixture.id != widget.fixture.id) {
      _aiLoading = false;
      _aiError = null;
      _aiAnalysis = null;
    }
  }

  Future<void> _askAiAnalyst() async {
    if (_aiLoading) return;
    final requestedFixtureId = fixture.id;
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });

    try {
      final prediction =
          await _aiService.getMatchPrediction(requestedFixtureId);
      if (!mounted || widget.fixture.id != requestedFixtureId) return;
      if (prediction.startsWith(AiService.errorPrefix)) {
        setState(() => _aiError = prediction);
      } else {
        setState(() => _aiAnalysis = prediction);
      }
    } finally {
      if (mounted && widget.fixture.id == requestedFixtureId) {
        setState(() => _aiLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final analysis = insights?.analysis ?? const <String, dynamic>{};
    final discipline = _map(analysis['discipline']);
    final pressure = _map(analysis['pressure']);
    final probabilities = _map(analysis['probabilities']);
    final aggression = _map(discipline['aggressionIndex']);
    final momentum = _map(pressure['momentum']);
    final shots = _map(pressure['totalShots']);
    final shotsOnTarget = _map(pressure['shotsOnTarget']);
    final corners = _map(pressure['corners']);
    final yellowFromStats = _map(discipline['yellowCards']);
    final redFromStats = _map(discipline['redCards']);
    final totalGoals = fixture.home.goals + fixture.away.goals;
    final goalLines = probabilities['goalLines'] is List
        ? (probabilities['goalLines'] as List)
            .whereType<Map>()
            .map((line) => Map<String, dynamic>.from(line))
            .toList()
        : [
            {
              'line': 1.5,
              'probability': probabilities['over15'],
            },
            {
              'line': 2.5,
              'probability': probabilities['over25'],
            },
          ]
            .where((line) => (line['line'] as double) + 0.5 > totalGoals)
            .toList();
    final homeYellow = events
        .where((event) =>
            event.isCard &&
            !event.isRedCard &&
            event.teamName == fixture.home.name)
        .length;
    final awayYellow = events
        .where((event) =>
            event.isCard &&
            !event.isRedCard &&
            event.teamName == fixture.away.name)
        .length;
    final homeRed = events
        .where(
            (event) => event.isRedCard && event.teamName == fixture.home.name)
        .length;
    final awayRed = events
        .where(
            (event) => event.isRedCard && event.teamName == fixture.away.name)
        .length;
    final refereeStats = _map(analysis['referee']);
    final hasInsights = insights != null;
    final refereeName = refereeStats['name'] as String? ?? fixture.referee;
    final teamHistory = _map(analysis['teamHistory']);
    final historyHome = _map(teamHistory['home']);
    final historyAway = _map(teamHistory['away']);
    final isHistory = analysis['source'] == 'team_season_history' ||
        analysis['source'] == 'live_match_and_team_history';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_outlined, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Match insights',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                if (!hasInsights && error == null)
                  const AppLoadingIndicator(
                    compact: true,
                    label: 'Loading match insights',
                  )
                else
                  Text(
                    !hasInsights
                        ? 'UNAVAILABLE'
                        : isHistory
                            ? 'TEAM HISTORY'
                            : 'LIVE DATA',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .6,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${fixture.home.name} vs ${fixture.away.name}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
            if (isHistory) ...[
              const SizedBox(height: 18),
              _sectionTitle(
                'Team history · ${analysis['season'] ?? 'Current season'}',
                Icons.history,
              ),
              const SizedBox(height: 10),
              if (teamHistory['available'] == true)
                Row(
                  children: [
                    Expanded(
                      child: _historySummary(fixture.home.name, historyHome),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _historySummary(fixture.away.name, historyAway),
                    ),
                  ],
                )
              else
                _emptyHint(
                  'Season history is not available for these teams yet.',
                ),
            ],
            const SizedBox(height: 18),
            _sectionTitle('Card Risk & Discipline', Icons.gavel_outlined),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _disciplineStat(
                    isHistory ? 'Red cards / match' : 'Red cards',
                    homeRed > 0 || awayRed > 0
                        ? '$homeRed  —  $awayRed'
                        : '${_disciplineValue(redFromStats['home'], isHistory)}  —  '
                            '${_disciplineValue(redFromStats['away'], isHistory)}',
                    scheme.error,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _disciplineStat(
                    isHistory ? 'Yellow cards / match' : 'Yellow cards',
                    homeYellow > 0 || awayYellow > 0
                        ? '$homeYellow  —  $awayYellow'
                        : '${_disciplineValue(yellowFromStats['home'], isHistory)}  —  '
                            '${_disciplineValue(yellowFromStats['away'], isHistory)}',
                    scheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _comparisonBar(
              label: 'Team aggression index',
              homeValue: _number(aggression['home']),
              awayValue: _number(aggression['away']),
              homeColor: scheme.error,
              awayColor: scheme.secondary,
              suffix: '/100',
            ),
            const SizedBox(height: 7),
            Text(
              'Referee: ${refereeName ?? 'Not reported'}'
              '${refereeStats['available'] == true ? '' : ' · referee history unavailable'}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Pressure & Momentum', Icons.bolt_outlined),
            const SizedBox(height: 12),
            if (pressure['available'] == true) ...[
              _comparisonBar(
                label: 'Attacking momentum',
                homeValue: _number(momentum['home']),
                awayValue: _number(momentum['away']),
                homeColor: scheme.primary,
                awayColor: scheme.secondary,
                suffix: '/100',
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: _teamMetric(
                      'Shots',
                      _count(_number(shots['home'])),
                      _count(_number(shots['away'])),
                    ),
                  ),
                  Expanded(
                    child: _teamMetric(
                      'On target',
                      _count(_number(shotsOnTarget['home'])),
                      _count(_number(shotsOnTarget['away'])),
                    ),
                  ),
                  Expanded(
                    child: _teamMetric(
                      'Corners',
                      _count(_number(corners['home'])),
                      _count(_number(corners['away'])),
                    ),
                  ),
                ],
              ),
            ] else
              _emptyHint(isHistory
                  ? 'Live pressure stats will be available after kickoff.'
                  : 'Pressure statistics are not available yet.'),
            const SizedBox(height: 20),
            _sectionTitle('Goal Expectancy', Icons.track_changes_outlined),
            const SizedBox(height: 12),
            if (probabilities['available'] == true) ...[
              if (goalLines.isEmpty)
                _emptyHint(
                    'All displayed goal lines have already been reached.')
              else
                ...goalLines.expand(
                  (market) => [
                    _probabilityBar(
                      'Over ${market['line']} goals',
                      _number(market['probability']),
                    ),
                    const SizedBox(height: 11),
                  ],
                ),
              _probabilityBar(
                  'Both teams to score', _number(probabilities['btts'])),
              const SizedBox(height: 10),
              Text(
                'Expected total: ${probabilities['expectedGoals'] ?? '—'} goals. '
                '${probabilities['method'] ?? ''}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
              ),
            ] else
              _emptyHint(
                probabilities['method']?.toString() ??
                    'Goal probabilities are unavailable until match statistics are reported.',
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _aiLoading || !hasInsights ? null : _askAiAnalyst,
                icon: _aiLoading
                    ? const AppLoadingIndicator(
                        compact: true,
                        label: 'AI analyst is reviewing the match',
                      )
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(
                  _aiLoading ? 'AI analyst is reviewing…' : 'Ask AI Analyst',
                ),
              ),
            ),
            if (_aiError != null) ...[
              const SizedBox(height: 8),
              Text(
                _aiError!,
                style: TextStyle(color: scheme.secondary, fontSize: 10),
              ),
            ],
            if (_aiAnalysis != null) ...[
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey(fixture.id),
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: .24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _aiAnalysis!,
                        style: TextStyle(
                          color: scheme.onSurface,
                          height: 1.5,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'AI-generated statistical summary, not a guaranteed result.',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (!hasInsights || error != null) ...[
              const SizedBox(height: 12),
              Text(
                error ??
                    'Some live statistics have not been reported by the provider.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) => Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 7),
          Text(title,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      );

  Widget _disciplineStat(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                )),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(
              '${fixture.home.name}  —  ${fixture.away.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 8,
              ),
            ),
          ],
        ),
      );

  Widget _comparisonBar({
    required String label,
    required double? homeValue,
    required double? awayValue,
    required Color homeColor,
    required Color awayColor,
    required String suffix,
  }) {
    final home = (homeValue ?? 0).clamp(0, 100).toDouble();
    final away = (awayValue ?? 0).clamp(0, 100).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
            Text(
              '${homeValue == null ? '—' : homeValue.round()}  —  '
              '${awayValue == null ? '—' : awayValue.round()}$suffix',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: _animatedBar(home / 100, homeColor),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _animatedBar(away / 100, awayColor, alignRight: true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _probabilityBar(String label, double? probability) {
    final value = probability?.clamp(0, 100).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
            Text(value == null ? '—' : '${value.round()}%',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 5),
        _animatedBar(
          (value ?? 0) / 100,
          Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }

  Widget _animatedBar(double value, Color color, {bool alignRight = false}) =>
      SizedBox(
        height: 7,
        child: LayoutBuilder(
          builder: (context, constraints) => ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(color: color.withValues(alpha: .13)),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value),
                  duration: const Duration(milliseconds: 850),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedValue, _) => Align(
                    alignment: alignRight
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: constraints.maxWidth * animatedValue,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _teamMetric(String label, String home, String away) => Column(
        children: [
          Text(label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 9,
              )),
          const SizedBox(height: 4),
          Text('$home  —  $away',
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      );

  Widget _historySummary(String teamName, Map<String, dynamic> history) {
    final form = history['form']?.toString();
    final scheme = Theme.of(context).colorScheme;
    final formColors = {
      'W': const Color(0xFF3DDC97),
      'D': scheme.secondary,
      'L': scheme.error,
    };

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            teamName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            '${history['played'] ?? '—'} played · '
            '${history['wins'] ?? '—'}W '
            '${history['draws'] ?? '—'}D '
            '${history['losses'] ?? '—'}L',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9),
          ),
          if (form != null && form.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 3,
              children: form.split('').map((result) {
                final color = formColors[result] ?? scheme.onSurfaceVariant;
                return Container(
                  width: 17,
                  height: 17,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    result,
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            'Goals avg: ${_historyNumber(history['goalsForPerMatch'])} for · '
            '${_historyNumber(history['goalsAgainstPerMatch'])} against',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9),
          ),
          Text(
            'Cards avg: ${_historyNumber(history['yellowCardsPerMatch'])} yellow · '
            '${_historyNumber(history['redCardsPerMatch'])} red',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9),
          ),
        ],
      ),
    );
  }

  String _historyNumber(Object? value) {
    final number = _number(value);
    return number == null ? '—' : number.toStringAsFixed(2);
  }

  String _disciplineValue(Object? value, bool isHistory) =>
      isHistory ? _historyNumber(value) : _count(_number(value));

  Widget _emptyHint(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      );
}
