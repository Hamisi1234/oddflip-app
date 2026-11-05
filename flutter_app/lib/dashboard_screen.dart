import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'models.dart';

class MatchModel {
  const MatchModel({
    required this.matchId,
    required this.homeTeam,
    required this.awayTeam,
    required this.currentMinute,
    required this.homeScore,
    required this.awayScore,
    required this.redCardsHome,
    required this.redCardsAway,
    required this.matchStatus,
    required this.league,
    this.redCardPlayer,
    this.redCardMinute,
  });

  final String matchId;
  final String homeTeam;
  final String awayTeam;
  final int currentMinute;
  final int homeScore;
  final int awayScore;
  final int redCardsHome;
  final int redCardsAway;
  final String matchStatus;
  final String league;
  final String? redCardPlayer;
  final int? redCardMinute;

  int get redCardCount => redCardsHome + redCardsAway;
  bool get isLive => matchStatus.toLowerCase() == 'live';

  factory MatchModel.fromFixture(
    LiveFixture fixture,
    List<MatchEvent> events,
  ) {
    final redCards = events.where((event) => event.isRedCard).toList();
    var homeRedCards = 0;
    var awayRedCards = 0;
    for (final event in redCards) {
      if (event.teamName.toLowerCase() == fixture.home.name.toLowerCase()) {
        homeRedCards++;
      } else if (event.teamName.toLowerCase() ==
          fixture.away.name.toLowerCase()) {
        awayRedCards++;
      }
    }
    final latestRedCard = redCards.isEmpty ? null : redCards.last;

    return MatchModel(
      matchId: fixture.id,
      homeTeam: fixture.home.name,
      awayTeam: fixture.away.name,
      currentMinute: fixture.minute ?? 0,
      homeScore: fixture.home.goals,
      awayScore: fixture.away.goals,
      redCardsHome: homeRedCards,
      redCardsAway: awayRedCards,
      matchStatus: fixture.status,
      league: fixture.league.name,
      redCardPlayer: latestRedCard?.playerName,
      redCardMinute: latestRedCard?.minute,
    );
  }

  factory MatchModel.fromJson(Map<String, dynamic> json) => MatchModel(
        matchId: '${json['match_id'] ?? json['id'] ?? ''}',
        homeTeam: '${json['home_team'] ?? 'Home'}',
        awayTeam: '${json['away_team'] ?? 'Away'}',
        currentMinute: (json['current_minute'] as num?)?.toInt() ?? 0,
        homeScore: (json['home_score'] as num?)?.toInt() ?? 0,
        awayScore: (json['away_score'] as num?)?.toInt() ?? 0,
        redCardsHome: (json['red_cards_home'] as num?)?.toInt() ?? 0,
        redCardsAway: (json['red_cards_away'] as num?)?.toInt() ?? 0,
        matchStatus: '${json['match_status'] ?? 'live'}',
        league: '${json['league'] ?? 'Live football'}',
        redCardPlayer: json['red_card_player'] as String?,
        redCardMinute: (json['red_card_minute'] as num?)?.toInt(),
      );

  static const mockMatches = <MatchModel>[
    MatchModel(
      matchId: 'mock-arsenal-liverpool',
      homeTeam: 'Arsenal',
      awayTeam: 'Liverpool',
      currentMinute: 67,
      homeScore: 1,
      awayScore: 1,
      redCardsHome: 1,
      redCardsAway: 0,
      matchStatus: 'live',
      league: 'Premier League',
      redCardPlayer: 'William Saliba',
      redCardMinute: 58,
    ),
    MatchModel(
      matchId: 'mock-real-madrid-city',
      homeTeam: 'Real Madrid',
      awayTeam: 'Man City',
      currentMinute: 72,
      homeScore: 2,
      awayScore: 2,
      redCardsHome: 0,
      redCardsAway: 1,
      matchStatus: 'live',
      league: 'UEFA Champions League',
      redCardPlayer: 'Ruben Dias',
      redCardMinute: 64,
    ),
    MatchModel(
      matchId: 'mock-barcelona-atletico',
      homeTeam: 'Barcelona',
      awayTeam: 'Atletico Madrid',
      currentMinute: 39,
      homeScore: 1,
      awayScore: 0,
      redCardsHome: 0,
      redCardsAway: 0,
      matchStatus: 'live',
      league: 'La Liga',
    ),
    MatchModel(
      matchId: 'mock-inter-napoli',
      homeTeam: 'Inter',
      awayTeam: 'Napoli',
      currentMinute: 54,
      homeScore: 0,
      awayScore: 0,
      redCardsHome: 0,
      redCardsAway: 0,
      matchStatus: 'live',
      league: 'Serie A',
    ),
  ];
}

class OddFlipDashboardScreen extends StatefulWidget {
  const OddFlipDashboardScreen({
    this.apiClient,
    this.onViewOdds,
    this.onLogin,
    super.key,
  });

  final ApiClient? apiClient;
  final ValueChanged<MatchModel>? onViewOdds;
  final VoidCallback? onLogin;

  @override
  State<OddFlipDashboardScreen> createState() => _OddFlipDashboardScreenState();
}

class _OddFlipDashboardScreenState extends State<OddFlipDashboardScreen>
    with TickerProviderStateMixin {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  late final AnimationController _hotZoneController;
  late final AnimationController _liveController;
  late final AnimationController _listController;
  List<MatchModel> _matches = MatchModel.mockMatches;
  Timer? _refreshTimer;

  List<MatchModel> get _liveMatches =>
      _matches.where((match) => match.isLive).toList(growable: false);

  List<MatchModel> get _hotMatches => _liveMatches
      .where((match) => match.redCardCount > 0)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _hotZoneController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    _liveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _listController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
    _loadMatches();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadMatches(),
    );
  }

  Future<void> _loadMatches() async {
    try {
      final fixtures = await _api.fetchLiveFixtures();
      if (fixtures.isEmpty) return;
      final matches = await Future.wait(fixtures.map((fixture) async {
        if (!fixture.hasTimeline) {
          return MatchModel.fromFixture(fixture, const []);
        }
        try {
          final events = await _api.fetchEvents(fixture.id);
          return MatchModel.fromFixture(fixture, events);
        } catch (_) {
          return MatchModel.fromFixture(fixture, const []);
        }
      }));
      if (!mounted || matches.isEmpty) return;
      setState(() => _matches = matches);
      _listController.forward(from: 0);
    } catch (_) {
      // Keep the bundled fixtures visible when the API is not reachable.
    }
  }

  Future<void> _refresh() => _loadMatches();

  void _showOdds(MatchModel match) {
    final callback = widget.onViewOdds;
    if (callback != null) {
      callback(match);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Live odds for ${match.homeTeam} vs ${match.awayTeam}')),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _hotZoneController.dispose();
    _liveController.dispose();
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveMatches = _liveMatches;
    final hotMatches = _hotMatches;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            const Text('Odd',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 23)),
            Text('Flip',
                style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 23)),
            const SizedBox(width: 12),
            _LiveIndicator(controller: _liveController, compact: true),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Log in or sign up',
            onPressed: widget.onLogin,
            icon: const Icon(Icons.person_outline),
          ),
          Container(
            margin: const EdgeInsets.only(right: 18),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20)),
            child: Text('${liveMatches.length} LIVE',
                style: TextStyle(
                    color: scheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: scheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
                child: _SectionHeading(
                    eyebrow: 'MATCH INTELLIGENCE',
                    title: 'The live picture',
                    trailing: _LiveIndicator(controller: _liveController))),
            if (hotMatches.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 17, 20, 11),
                  child: Row(children: [
                    Icon(Icons.flash_on, color: scheme.error, size: 18),
                    const SizedBox(width: 6),
                    Text('HOT ZONE',
                        style: TextStyle(
                            color: scheme.error,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1)),
                    const SizedBox(width: 8),
                    Text(
                        '${hotMatches.length} match${hotMatches.length == 1 ? '' : 'es'} with red cards',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 11)),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 217,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: hotMatches.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => _HotZoneCard(
                        match: hotMatches[index],
                        glow: _hotZoneController,
                        live: _liveController,
                        onViewOdds: () => _showOdds(hotMatches[index])),
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 27, 20, 12),
                child:
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('ON THE PITCH',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .9)),
                        SizedBox(height: 4),
                        Text('All live matches',
                            style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w900)),
                      ])),
                  Text('${liveMatches.length} FIXTURES',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
            if (liveMatches.isEmpty)
              SliverToBoxAdapter(
                  child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('No live matches right now'))))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final match = liveMatches[index];
                      final start = (index * .075).clamp(0.0, .62);
                      final end = (start + .38).clamp(0.0, 1.0);
                      final entry = CurvedAnimation(
                          parent: _listController,
                          curve:
                              Interval(start, end, curve: Curves.easeOutCubic));
                      return FadeTransition(
                        opacity: entry,
                        child: SlideTransition(
                          position: Tween<Offset>(
                                  begin: const Offset(0, .12), end: Offset.zero)
                              .animate(entry),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _LiveMatchTile(
                                key: ValueKey(match.matchId),
                                match: match,
                                live: _liveController,
                                onTap: () => _showOdds(match)),
                          ),
                        ),
                      );
                    },
                    childCount: liveMatches.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(
      {required this.eyebrow, required this.title, required this.trailing});
  final String eyebrow;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(eyebrow,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
                const SizedBox(height: 5),
                Text(title,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 25,
                        fontWeight: FontWeight.w900)),
              ])),
          trailing,
        ]),
      );
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.controller, this.compact = false});
  final Animation<double> controller;
  final bool compact;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final scale = .82 + controller.value * .18;
          final scheme = Theme.of(context).colorScheme;
          return Container(
            padding:
                EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary
                        .withValues(alpha: .72 + controller.value * .28),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: scheme.primary
                              .withValues(alpha: .18 + controller.value * .22),
                          blurRadius: 6)
                    ],
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text('LIVE',
                    style: TextStyle(
                        color: scheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .7)),
              ],
            ]),
          );
        },
      );
}

class _HotZoneCard extends StatelessWidget {
  const _HotZoneCard(
      {required this.match,
      required this.glow,
      required this.live,
      required this.onViewOdds});
  final MatchModel match;
  final Animation<double> glow;
  final Animation<double> live;
  final VoidCallback onViewOdds;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: glow,
        builder: (context, _) {
          final intensity = .24 + glow.value * .34;
          final scheme = Theme.of(context).colorScheme;
          return Container(
            width: 310,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: scheme.error.withValues(alpha: .45 + glow.value * .45),
                  width: 1.2),
              boxShadow: [
                BoxShadow(
                    color: scheme.error.withValues(alpha: intensity * .22),
                    blurRadius: 9 + glow.value * 10,
                    spreadRadius: glow.value * 1.4)
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.flash_on, color: scheme.error, size: 15),
                      const SizedBox(width: 4),
                      Text('RED CARD ALERT',
                          style: TextStyle(
                              color: scheme.error,
                              fontWeight: FontWeight.w900,
                              fontSize: 9,
                              letterSpacing: .7)),
                      const Spacer(),
                      _LiveIndicator(controller: live),
                    ]),
                    const Spacer(),
                    _ScoreLine(match: match, compact: true),
                    const SizedBox(height: 9),
                    Row(children: [
                      Icon(Icons.crop_portrait, color: scheme.error, size: 17),
                      const SizedBox(width: 5),
                      Expanded(
                          child: Text(
                              '${match.redCardPlayer ?? 'Red card'}  ${match.redCardMinute ?? ''}′',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800))),
                      Text(match.league,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 9)),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 34,
                      child: FilledButton.icon(
                        onPressed: onViewOdds,
                        style: FilledButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                            padding: const EdgeInsets.symmetric(horizontal: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        icon: const Icon(Icons.trending_up, size: 15),
                        label: const Text('View Live Odds',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
            ),
          );
        },
      );
}

class _LiveMatchTile extends StatelessWidget {
  const _LiveMatchTile(
      {required this.match,
      required this.live,
      required this.onTap,
      super.key});
  final MatchModel match;
  final Animation<double> live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: .5)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text(match.league,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 10))),
                if (match.redCardCount > 0)
                  _RedCardBadge(count: match.redCardCount)
                else
                  _LiveIndicator(controller: live),
              ]),
              const SizedBox(height: 9),
              _ScoreLine(match: match),
            ]),
          ),
        ),
      );
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({required this.match, this.compact = false});
  final MatchModel match;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(
          child: Text(match.homeTeam,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w800))),
      Column(children: [
        Text('${match.homeScore}  -  ${match.awayScore}',
            style: TextStyle(
                color: scheme.onSurface,
                fontSize: compact ? 22 : 20,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()])),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: compact ? 8 : 9,
            height: compact ? 8 : 9,
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
            child: Center(
              child: Container(
                width: compact ? 4 : 5,
                height: compact ? 4 : 5,
                decoration: BoxDecoration(
                    color: scheme.primary, shape: BoxShape.circle),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text('${match.currentMinute}′',
              style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ]),
      ]),
      Expanded(
          child: Text(match.awayTeam,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w800))),
    ]);
  }
}

class _RedCardBadge extends StatefulWidget {
  const _RedCardBadge({required this.count});
  final int count;

  @override
  State<_RedCardBadge> createState() => _RedCardBadgeState();
}

class _RedCardBadgeState extends State<_RedCardBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.22), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.22, end: .96), weight: 30),
      TweenSequenceItem(tween: Tween(begin: .96, end: 1), weight: 35),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant _RedCardBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > oldWidget.count) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: scheme.error, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7,
              height: 10,
              decoration: BoxDecoration(
                  color: scheme.onError,
                  borderRadius: BorderRadius.circular(1))),
          const SizedBox(width: 5),
          Text('RED ${widget.count}',
              style: TextStyle(
                  color: scheme.onError,
                  fontSize: 9,
                  fontWeight: FontWeight.w900)),
        ]),
      ),
    );
  }
}
