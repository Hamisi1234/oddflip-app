import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:red_card_alert/app_loading_indicator.dart';
import 'package:red_card_alert/ai_service.dart';
import 'package:red_card_alert/api_client.dart';
import 'package:red_card_alert/models.dart';
import 'package:red_card_alert/mkaria_chat_screen.dart';
import 'package:red_card_alert/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses a live fixture response', () {
    final fixture = LiveFixture.fromJson({
      'id': 'match-1',
      'league': {
        'id': 'league-1',
        'name': 'Premier League',
        'country': 'England'
      },
      'status': 'live',
      'minute': 67,
      'venue': 'Test Stadium',
      'hasTimeline': true,
      'isPopular': true,
      'priority': 2,
      'home': {'id': 'home-1', 'name': 'Home FC', 'logo': '', 'goals': 2},
      'away': {'id': 'away-1', 'name': 'Away FC', 'logo': '', 'goals': 1},
    });

    expect(fixture.home.goals, 2);
    expect(fixture.away.name, 'Away FC');
    expect(fixture.hasTimeline, isTrue);
    expect(fixture.isPopular, isTrue);
    expect(fixture.priority, 2);
  });

  testWidgets('shows the animated football loading indicator', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppLoadingIndicator(label: 'Loading live matches'),
        ),
      ),
    );

    expect(find.byIcon(Icons.sports_soccer), findsOneWidget);
    expect(find.text('Loading live matches'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('uses cached live fixtures when the API request fails', () async {
    SharedPreferences.setMockInitialValues({});
    final response = jsonEncode({
      'data': [
        {
          'id': 'match-cached',
          'league': {'id': 'league-1', 'name': 'Premier League'},
          'status': 'live',
          'hasTimeline': true,
          'home': {'id': 'home-1', 'name': 'Home FC', 'goals': 1},
          'away': {'id': 'away-1', 'name': 'Away FC', 'goals': 0},
        },
      ],
      'meta': {'stale': false},
    });

    final initialClient = MockClient(
      (_) async => http.Response(response, 200),
    );
    final initialFixtures =
        await ApiClient(client: initialClient).fetchLiveFixtures();
    initialClient.close();
    expect(initialFixtures.single.id, 'match-cached');

    final failingClient = MockClient(
      (_) async => throw http.ClientException('Connection timed out.'),
    );
    final cachedFixtures =
        await ApiClient(client: failingClient).fetchLiveFixtures();
    failingClient.close();

    expect(cachedFixtures.single.id, 'match-cached');
    expect(cachedFixtures.single.home.goals, 1);
  });

  test('loads and caches upcoming fixtures with kickoff times', () async {
    SharedPreferences.setMockInitialValues({});
    final response = jsonEncode({
      'data': [
        {
          'id': 'match-upcoming',
          'league': {
            'id': 'league-1',
            'name': 'Premier League',
            'country': 'England',
          },
          'status': 'NS',
          'startsAt': '2026-10-30T16:30:00+00:00',
          'hasTimeline': true,
          'home': {'id': 'home-1', 'name': 'Home FC', 'goals': 0},
          'away': {'id': 'away-1', 'name': 'Away FC', 'goals': 0},
        },
      ],
      'meta': {'stale': false},
    });

    final initialClient = MockClient((request) async {
      expect(request.url.path, '/api/fixtures/upcoming');
      return http.Response(response, 200);
    });
    final fixtures =
        await ApiClient(client: initialClient).fetchUpcomingFixtures();
    initialClient.close();

    expect(fixtures.single.id, 'match-upcoming');
    expect(
        fixtures.single.startsAt, DateTime.parse('2026-10-30T16:30:00+00:00'));

    final failingClient = MockClient(
      (_) async => throw http.ClientException('Connection timed out.'),
    );
    final cachedFixtures =
        await ApiClient(client: failingClient).fetchUpcomingFixtures();
    failingClient.close();

    expect(cachedFixtures.single.id, 'match-upcoming');
  });

  test('sends upcoming fixture filter query parameters', () async {
    late Uri requestUri;
    final client = MockClient((request) async {
      requestUri = request.url;
      return http.Response(jsonEncode({'data': [], 'meta': {}}), 200);
    });

    await ApiClient(
      baseUrl: 'https://example.test',
      client: client,
    ).fetchUpcomingFixtures(
      date: '2026-10-31',
      timeFrom: '12:00',
      timeTo: '17:59',
      league: '39',
      country: 'England',
    );
    client.close();

    expect(requestUri.path, '/api/fixtures/upcoming');
    expect(requestUri.queryParameters, {
      'date': '2026-10-31',
      'time_from': '12:00',
      'time_to': '17:59',
      'league': '39',
      'country': 'England',
    });
  });

  testWidgets('expands and collapses live and upcoming match lists',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final liveFixtures = List.generate(
      12,
      (index) => {
        'id': 'live-${index + 1}',
        'league': {'id': 'league-1', 'name': 'Premier League'},
        'status': 'live',
        'minute': 12,
        'hasTimeline': false,
        'home': {
          'id': 'live-home-${index + 1}',
          'name': 'Live Home ${index + 1}',
          'goals': 0,
        },
        'away': {
          'id': 'live-away-${index + 1}',
          'name': 'Live Away ${index + 1}',
          'goals': 0,
        },
      },
    );
    final upcomingFixtures = List.generate(
      12,
      (index) => {
        'id': 'upcoming-${index + 1}',
        'league': {
          'id': 'league-1',
          'name': 'Premier League',
          'country': 'England',
        },
        'status': 'NS',
        'startsAt':
            DateTime.now().add(Duration(hours: index + 1)).toIso8601String(),
        'hasTimeline': false,
        'home': {
          'id': 'upcoming-home-${index + 1}',
          'name': 'Upcoming Home ${index + 1}',
          'goals': 0,
        },
        'away': {
          'id': 'upcoming-away-${index + 1}',
          'name': 'Upcoming Away ${index + 1}',
          'goals': 0,
        },
      },
    );
    final client = MockClient((request) async {
      final fixtures =
          request.url.path.endsWith('/live') ? liveFixtures : upcomingFixtures;
      return http.Response(
        jsonEncode({
          'data': fixtures,
          'meta': {'stale': false}
        }),
        200,
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: app.DashboardScreen(
          apiClient: ApiClient(
            baseUrl: 'https://example.test',
            client: client,
            tokenProvider: () async => null,
          ),
          onOpen: (_) {},
          onRedCards: () {},
          onAlert: (_) {},
          onAuthenticated: () {},
          onProfile: () {},
          profile: null,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> scrollUntilBuilt(Finder finder,
        {bool towardBottom = true}) async {
      for (var attempt = 0; attempt < 20; attempt++) {
        if (finder.evaluate().isNotEmpty) return;
        await tester.drag(
          find.byType(Scrollable).first,
          Offset(0, towardBottom ? -500 : 500),
        );
        await tester.pumpAndSettle();
      }
      expect(finder, findsOneWidget);
    }

    await scrollUntilBuilt(find.text('Live Home 10'));
    await tester.scrollUntilVisible(
      find.text('Live Home 10'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Live Home 10'), findsOneWidget);
    expect(find.text('Live Home 11'), findsNothing);
    await scrollUntilBuilt(
      find.byKey(const ValueKey('live-match-expansion')),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('live-match-expansion')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('See more (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-match-expansion')));
    await tester.pumpAndSettle();
    await scrollUntilBuilt(find.text('Live Home 11'));
    await tester.scrollUntilVisible(
      find.text('Live Home 11'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Live Home 11'), findsOneWidget);
    await scrollUntilBuilt(find.text('Live Home 12'));
    await tester.scrollUntilVisible(
      find.text('Live Home 12'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Live Home 12'), findsOneWidget);
    await scrollUntilBuilt(
      find.byKey(const ValueKey('live-match-expansion')),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('live-match-expansion')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('live-match-expansion')));
    await tester.pumpAndSettle();
    expect(find.text('Live Home 11'), findsNothing);

    await scrollUntilBuilt(
      find.text('Upcoming matches'),
      towardBottom: false,
    );
    await tester.scrollUntilVisible(
      find.text('Upcoming matches'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await scrollUntilBuilt(find.text('Upcoming Home 10'));
    await tester.scrollUntilVisible(
      find.text('Upcoming Home 10'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Upcoming Home 10'), findsOneWidget);
    expect(find.text('Upcoming Home 11'), findsNothing);
    await scrollUntilBuilt(
      find.byKey(const ValueKey('upcoming-match-expansion')),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('upcoming-match-expansion')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('See more (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('upcoming-match-expansion')));
    await tester.pumpAndSettle();
    await scrollUntilBuilt(find.text('Upcoming Home 11'));
    await tester.scrollUntilVisible(
      find.text('Upcoming Home 11'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Upcoming Home 11'), findsOneWidget);
    await scrollUntilBuilt(find.text('Upcoming Home 12'));
    await tester.scrollUntilVisible(
      find.text('Upcoming Home 12'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Upcoming Home 12'), findsOneWidget);
    await scrollUntilBuilt(
      find.byKey(const ValueKey('upcoming-match-expansion')),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('upcoming-match-expansion')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('upcoming-match-expansion')));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming Home 11'), findsNothing);

    client.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('requests and parses fixture-specific AI reply and betslip', () async {
    late Uri requestUri;
    final client = MockClient((request) async {
      requestUri = request.url;
      expect(request.method, 'POST');
      expect(
        request.headers['Authorization'],
        'Bearer test-token',
      );
      expect(jsonDecode(request.body), isEmpty);
      return http.Response(
        jsonEncode({
          'data': {
            'reply': 'Form favors the home team, but uncertainty remains.',
            'betslip': {
              'picks': [
                {
                  'match': 'Home FC v Away FC',
                  'market': 'Over 2.5 goals',
                  'odds': null,
                  'risk': 'moderate',
                  'confidence': 55,
                },
              ],
              'combinedOdds': null,
              'overallRisk': 'moderate',
              'note': 'Verify prices and team news.',
            },
          },
        }),
        200,
      );
    });

    final analysis = await ApiClient(
      client: client,
      tokenProvider: () async => 'test-token',
    ).fetchAiAnalysis('fixture-42');
    client.close();

    expect(requestUri.path, '/api/fixtures/fixture-42/ai-analysis');
    expect(
        analysis.reply, 'Form favors the home team, but uncertainty remains.');
    expect(analysis.betslip?.picks.single.match, 'Home FC v Away FC');
    expect(analysis.betslip?.picks.single.market, 'Over 2.5 goals');
    expect(analysis.betslip?.picks.single.odds, isNull);
  });

  test('sends Mkaria chat with auth, conversation history and betslip response',
      () async {
    late Uri requestUri;
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestUri = request.url;
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer test-token');
      return http.Response(
        jsonEncode({
          'data': {
            'reply': 'The data suggests a moderate risk.',
            'betslip': {
              'picks': [
                {
                  'match': 'Home FC v Away FC',
                  'market': 'Over 1.5 goals',
                  'odds': null,
                  'risk': 'moderate',
                  'confidence': 60,
                },
              ],
              'combinedOdds': null,
              'overallRisk': 'moderate',
              'note': 'Odds are not available.',
            },
          },
        }),
        200,
      );
    });

    final response = await ApiClient(
      client: client,
      tokenProvider: () async => 'test-token',
    ).sendMkariaChat(
      message: 'Analyze this fixture.',
      fixtureId: 'fixture-55',
      history: const [
        {'role': 'user', 'content': 'Look at cards.'},
      ],
    );
    client.close();

    expect(requestUri.path, '/api/mkaria-chat');
    expect(requestBody['fixture_id'], 'fixture-55');
    expect(requestBody['history'], hasLength(1));
    expect(response.reply, 'The data suggests a moderate risk.');
    expect(response.betslip?.picks.single.market, 'Over 1.5 goals');
    expect(response.betslip?.picks.single.odds, isNull);
  });

  testWidgets('renders the Mkamaria betslip card actions', (tester) async {
    const slip = MkariaBetslip(
      picks: [
        MkariaBetPick(
          match: 'Home FC v Away FC',
          market: 'Over 1.5 goals',
          risk: 'moderate',
          confidence: 60,
        ),
      ],
      overallRisk: 'moderate',
      note: 'Odds are not available.',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BetslipCard(
          slip: slip,
          onCopy: () {},
          onSave: () {},
        ),
      ),
    ));

    expect(find.text('MKAMARIA BETSLIP'), findsOneWidget);
    expect(find.text('Home FC v Away FC'), findsOneWidget);
    expect(find.text('Over 1.5 goals'), findsOneWidget);
    expect(find.text('Copy slip'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Mkaria chat sends a quick prompt and shows its betslip',
      (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/api/mkaria-chats') {
        return http.Response(jsonEncode({'data': []}), 200);
      }
      return http.Response(
        jsonEncode({
          'data': {
            'reply': 'The live data shows moderate card risk.',
            'betslip': {
              'picks': [
                {
                  'match': 'Home FC v Away FC',
                  'market': 'Over 1.5 goals',
                  'odds': null,
                  'risk': 'moderate',
                  'confidence': 60,
                },
              ],
              'combinedOdds': null,
              'overallRisk': 'moderate',
              'note': 'Verify current prices before deciding.',
            },
            'conversation_id': 17,
          },
        }),
        200,
      );
    });
    await tester.pumpWidget(MaterialApp(
      home: MkariaChatScreen(
        apiClient: ApiClient(
          client: client,
          tokenProvider: () async => 'test-token',
        ),
        userId: '23',
      ),
    ));

    expect(find.text("Analyze today's live matches"), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Check red card risks');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(
        find.text('The live data shows moderate card risk.'), findsOneWidget);
    expect(find.text('MKAMARIA BETSLIP'), findsOneWidget);
    expect(find.text('Copy slip'), findsOneWidget);
    client.close();
  });

  testWidgets('chat history resumes saved conversations and New Chat resets',
      (tester) async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/api/mkaria-chats') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 7,
                'title': 'Previous match analysis',
                'last_message': 'We reviewed the supplied match form.',
                'updated_at': '2026-10-31T02:00:00Z',
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/mkaria-chats/7') {
        return http.Response(
          jsonEncode({
            'data': {
              'id': 7,
              'title': 'Previous match analysis',
              'messages': [
                {
                  'role': 'user',
                  'content': 'Review the previous match form.',
                  'betslip': null,
                },
                {
                  'role': 'assistant',
                  'content': 'We reviewed the supplied match form.',
                  'betslip': null,
                },
              ],
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'data': {
            'reply': 'I will review only the supplied match data.',
            'betslip': null,
            'conversation_id': 8,
          },
        }),
        200,
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: MkariaChatScreen(
        apiClient: ApiClient(
          client: client,
          tokenProvider: () async => 'test-token',
        ),
        userId: '23',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Chat history'));
    await tester.pumpAndSettle();
    expect(find.text('Previous match analysis'), findsOneWidget);
    await tester.tap(find.text('Previous match analysis'));
    await tester.pumpAndSettle();
    expect(find.text('Review the previous match form.'), findsOneWidget);
    expect(find.text('We reviewed the supplied match form.'), findsOneWidget);

    await tester.tap(find.byTooltip('New Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Review the previous match form.'), findsNothing);
    expect(find.textContaining("Hi, I'm Mkamaria AI."), findsOneWidget);
    client.close();
  });

  test('AiService formats reply and structured betslip', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'data': {
              'reply': 'Home form is stronger, but the result is uncertain.',
              'betslip': {
                'picks': [
                  {
                    'match': 'Home FC v Away FC',
                    'market': 'Over 2.5 goals',
                    'odds': 3.2,
                    'risk': 'moderate',
                    'confidence': 55,
                  },
                ],
                'combinedOdds': 3.2,
                'overallRisk': 'moderate',
                'note': 'Verify prices and team news.',
              },
            },
          }),
          200,
        ));

    final prediction = await AiService(
      apiClient: ApiClient(
        client: client,
        tokenProvider: () async => 'test-token',
      ),
    ).getMatchPrediction('fixture-42');
    client.close();

    expect(
      prediction,
      'Home form is stronger, but the result is uncertain.\n'
      '\n'
      'Cautious betslip (moderate risk):\n'
      'Home FC v Away FC: Over 2.5 goals\n'
      'Verify prices and team news.',
    );
  });

  test('AiService returns a readable error when the AI request fails',
      () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({'message': 'AI analysis is not configured.'}),
          503,
        ));

    final prediction = await AiService(
      apiClient: ApiClient(
        client: client,
        tokenProvider: () async => 'test-token',
      ),
    ).getMatchPrediction('fixture-42');
    client.close();

    expect(
      prediction,
      'AI analysis failed: AI analysis is not configured.',
    );
  });
}
