import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_loading_indicator.dart';
import 'api_client.dart';
import 'models.dart';

class RedCardOverviewScreen extends StatefulWidget {
  const RedCardOverviewScreen({required this.onOpenFixture, super.key});

  final ValueChanged<LiveFixture> onOpenFixture;

  @override
  State<RedCardOverviewScreen> createState() => _RedCardOverviewScreenState();
}

class _RedCardOverviewScreenState extends State<RedCardOverviewScreen> {
  static _RedCardOverviewSnapshot? _cachedSnapshot;

  final _api = ApiClient();
  List<_RedCardMatch> _matches = _cachedSnapshot?.matches ?? const [];
  List<String> _errors = _cachedSnapshot?.errors ?? const [];
  bool _loading = _cachedSnapshot == null;
  bool _hasLiveFixtures = _cachedSnapshot?.hasLiveFixtures ?? false;
  bool _timelinesUnavailable = _cachedSnapshot?.timelinesUnavailable ?? false;
  int _uncoveredFixtureCount = _cachedSnapshot?.uncoveredFixtureCount ?? 0;
  String? _liveLoadError;
  String? _progress;
  bool _requestInFlight = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load(silent: _cachedSnapshot != null);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _load(silent: true),
    );
  }

  Future<void> _load({bool silent = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    if (!silent) setState(() => _loading = true);
    try {
      final fixtures = await _api.fetchLiveFixtures();
      final fixturesWithTimelines =
          fixtures.where((fixture) => fixture.hasTimeline).toList();
      final matches = <_RedCardMatch>[];
      final errors = <String>[];
      if (mounted) {
        setState(() {
          _progress = fixturesWithTimelines.isEmpty
              ? null
              : 'Checking red cards in ${fixturesWithTimelines.length} live matches…';
        });
      }
      var checked = 0;
      for (var start = 0; start < fixturesWithTimelines.length; start += 5) {
        final batch = fixturesWithTimelines.skip(start).take(5);
        final results = await Future.wait(batch.map(_scanFixture));
        for (final result in results) {
          if (result.match != null) matches.add(result.match!);
          if (result.error != null) errors.add(result.error!);
        }
        checked += results.length;
        if (mounted) {
          setState(() {
            _matches = List.of(matches);
            _errors = List.of(errors);
            _progress = 'Checked $checked of '
                '${fixturesWithTimelines.length} live matches';
          });
        }
      }

      if (mounted && fixturesWithTimelines.isNotEmpty) {
        setState(() {
          _progress = 'Checked ${fixturesWithTimelines.length} of '
              '${fixturesWithTimelines.length} live matches';
        });
      }

      if (!mounted) return;
      final snapshot = _RedCardOverviewSnapshot(
        matches: matches,
        errors: errors,
        hasLiveFixtures: fixtures.isNotEmpty,
        timelinesUnavailable:
            fixtures.isNotEmpty && fixturesWithTimelines.isEmpty,
        uncoveredFixtureCount: fixtures.length - fixturesWithTimelines.length,
      );
      _cachedSnapshot = snapshot;
      setState(() {
        _matches = snapshot.matches;
        _errors = snapshot.errors;
        _hasLiveFixtures = snapshot.hasLiveFixtures;
        _timelinesUnavailable = snapshot.timelinesUnavailable;
        _uncoveredFixtureCount = snapshot.uncoveredFixtureCount;
        _liveLoadError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (_matches.isEmpty) {
          _matches = const [];
          _hasLiveFixtures = false;
          _timelinesUnavailable = false;
          _uncoveredFixtureCount = 0;
        }
        _errors = [error.message];
        _liveLoadError = error.message;
        _progress = null;
      });
    } finally {
      _requestInFlight = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = null;
        });
      }
    }
  }

  Future<_FixtureScanResult> _scanFixture(LiveFixture fixture) async {
    try {
      final events = await _api.fetchEvents(fixture.id);
      final redCards = events.where((event) => event.isRedCard).toList();
      return _FixtureScanResult(
        match: redCards.isEmpty
            ? null
            : _RedCardMatch(
                fixture: fixture,
                redCards: redCards,
                events: events,
              ),
      );
    } on ApiException catch (error) {
      return _FixtureScanResult(
        error: '${fixture.home.name} vs ${fixture.away.name}: ${error.message}',
      );
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Red card overview',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh live matches',
            onPressed: _loading ? null : _load,
            icon: Icon(Icons.refresh, color: scheme.primary),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            const _EstimateNotice(),
            const SizedBox(height: 14),
            if (_loading && _matches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: AppLoadingIndicator(
                  label: _progress ?? 'Loading red-card match data',
                ),
              )
            else if (_matches.isEmpty)
              _emptyState()
            else ...[
              _SectionHeading(
                title: 'Live matches with red cards',
                count: _matches.length,
              ),
              const SizedBox(height: 10),
              ..._matches.map(
                (match) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RedCardMatchCard(
                    match: match,
                    onTap: () => widget.onOpenFixture(match.fixture),
                  ),
                ),
              ),
            ],
            if (_uncoveredFixtureCount > 0 && !_timelinesUnavailable) ...[
              const SizedBox(height: 6),
              _DataErrorPanel(
                errors: [
                  'Red cards could not be checked in '
                      '$_uncoveredFixtureCount live match(es) because match '
                      'timelines are not available.',
                ],
              ),
            ],
            if (_loading && _progress != null && _matches.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLoadingIndicator(
                      compact: true,
                      label: 'Refreshing red-card results',
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _progress!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 4),
              _DataErrorPanel(errors: _errors),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    final message = _liveLoadError != null
        ? 'Live matches could not be loaded. Check the data error below and try again.'
        : _errors.isNotEmpty
            ? 'Some match timelines could not be loaded, so the red-card list may be incomplete.'
            : !_hasLiveFixtures
                ? 'There are no live matches right now.'
                : _timelinesUnavailable
                    ? 'The live provider is not supplying match timelines, so red cards cannot be confirmed.'
                    : 'No red cards have been reported in the live matches yet.';
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        children: [
          Icon(Icons.credit_card, color: scheme.onSurfaceVariant, size: 38),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _RedCardOverviewSnapshot {
  const _RedCardOverviewSnapshot({
    required this.matches,
    required this.errors,
    required this.hasLiveFixtures,
    required this.timelinesUnavailable,
    required this.uncoveredFixtureCount,
  });

  final List<_RedCardMatch> matches;
  final List<String> errors;
  final bool hasLiveFixtures;
  final bool timelinesUnavailable;
  final int uncoveredFixtureCount;
}

class _RedCardMatch {
  const _RedCardMatch({
    required this.fixture,
    required this.redCards,
    required this.events,
  });

  final LiveFixture fixture;
  final List<MatchEvent> redCards;
  final List<MatchEvent> events;
}

class _FixtureScanResult {
  const _FixtureScanResult({this.match, this.error});

  final _RedCardMatch? match;
  final String? error;
}

class _RedCardMatchCard extends StatelessWidget {
  const _RedCardMatchCard({required this.match, required this.onTap});

  final _RedCardMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fixture = match.fixture;
    final pressure = _pressureSummary(fixture, match.events);
    final goalChance = _goalProbability(match, pressure);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle, color: scheme.error, size: 9),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      fixture.league.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    '${fixture.minute ?? '—'}′',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fixture.home.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${fixture.home.goals} — ${fixture.away.goals}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      fixture.away.name,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...match.redCards.map((event) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 15,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${event.teamName} · ${event.playerName} · ${event.minute}′',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )),
              const Divider(height: 20),
              _InsightRow(
                icon: Icons.bolt,
                title: 'Team under pressure',
                value: pressure.description,
              ),
              const SizedBox(height: 9),
              _InsightRow(
                icon: Icons.sports_soccer,
                title: 'Chance of another goal',
                value: goalChance == null ? 'Unavailable' : '$goalChance%',
                valueColor: goalChance == null
                    ? scheme.onSurfaceVariant
                    : scheme.primary,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'OPEN MATCH DETAILS  ›',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PressureSummary {
  const _PressureSummary({
    required this.description,
    this.underPressureTeam,
    this.attackDifference = 0,
  });

  final String description;
  final String? underPressureTeam;
  final double attackDifference;
}

_PressureSummary _pressureSummary(
  LiveFixture fixture,
  List<MatchEvent> events,
) {
  var homeAttacks = 0;
  var awayAttacks = 0;
  for (final event in events) {
    final activity = '${event.type} ${event.detail}'.toLowerCase();
    final isAttack = activity.contains('shot') ||
        activity.contains('goal') ||
        activity.contains('corner');
    if (!isAttack) continue;
    if (event.teamName.toLowerCase() == fixture.home.name.toLowerCase()) {
      homeAttacks++;
    } else if (event.teamName.toLowerCase() ==
        fixture.away.name.toLowerCase()) {
      awayAttacks++;
    }
  }
  final higher = math.max(homeAttacks, awayAttacks);
  if (higher == 0) {
    return const _PressureSummary(
      description: 'No shots or corners reported',
    );
  }
  final difference = (homeAttacks - awayAttacks).abs() / higher;
  if (higher < 3) {
    return _PressureSummary(
      description: 'Limited data · $homeAttacks–$awayAttacks incidents',
    );
  }
  if (difference < .25) {
    return _PressureSummary(
      description: 'Balanced · $homeAttacks–$awayAttacks attacking incidents',
    );
  }
  final pressuredTeam =
      homeAttacks > awayAttacks ? fixture.away.name : fixture.home.name;
  final attackingTeam =
      homeAttacks > awayAttacks ? fixture.home.name : fixture.away.name;
  final attackCount = math.max(homeAttacks, awayAttacks);
  return _PressureSummary(
    description: '$pressuredTeam · $attackingTeam recorded '
        '$attackCount attacking incidents',
    underPressureTeam: pressuredTeam,
    attackDifference: difference,
  );
}

int? _goalProbability(_RedCardMatch match, _PressureSummary pressure) {
  final minute = match.fixture.minute;
  if (minute == null) return null;
  final remainingMinutes = (90 - minute).clamp(0, 90);
  if (remainingMinutes == 0) return 0;

  var expectedGoalsPerMinute = .016 + match.redCards.length * .004;
  if (match.fixture.home.goals == match.fixture.away.goals) {
    expectedGoalsPerMinute += .003;
  }
  if (pressure.underPressureTeam != null) {
    expectedGoalsPerMinute += math.min(pressure.attackDifference, .5) * .008;
  }
  final probability = 1 - math.exp(-expectedGoalsPerMinute * remainingMinutes);
  return (probability * 100).round().clamp(0, 99);
}

class _EstimateNotice extends StatelessWidget {
  const _EstimateNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.primary, size: 18),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Goal chances are estimates based on the match clock, score and red cards. Pressure uses shots, goals and corners reported in each match timeline.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.error.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: scheme.error,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: scheme.primary, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DataErrorPanel extends StatelessWidget {
  const _DataErrorPanel({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Some live data could not be loaded',
            style: TextStyle(
              color: scheme.error,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ...errors.map(
            (error) => Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                error,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
