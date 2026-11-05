<?php

namespace Tests\Feature;

use App\Models\Fixture;
use App\Models\MatchInsight;
use App\Models\User;
use App\Services\ApiFootballService;
use App\Services\OpenAiAnalystService;
use App\Services\OpenAiApiException;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

class ApiFootballTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config([
            'services.apifootball.key' => 'test-api-key',
            'services.apifootball.base_url' => 'https://v3.football.api-sports.io',
        ]);
    }

    public function test_live_fixtures_use_api_football_and_persist_to_the_database(): void
    {
        Http::fake(fn (Request $request) => Http::response([
            'errors' => [],
            'response' => [$this->fixture()],
        ]));

        $this->getJson('/api/fixtures/live')
            ->assertOk()
            ->assertJsonPath('data.0.id', '12345')
            ->assertJsonPath('data.0.home.name', 'Home FC')
            ->assertJsonPath('data.0.away.goals', 1);

        $this->assertDatabaseHas('fixtures', [
            'provider' => 'api-football',
            'provider_id' => '12345',
            'home_score' => 2,
            'away_score' => 1,
        ]);
        $this->assertDatabaseHas('leagues', [
            'provider_id' => '39',
            'logo_url' => 'https://example.test/league.png',
        ]);
        $this->assertDatabaseHas('teams', [
            'provider_id' => '10',
            'logo_url' => 'https://example.test/home.png',
        ]);
        $this->assertDatabaseHas('fixtures', [
            'provider_id' => '12345',
            'referee' => 'Test Referee',
            'season' => 2026,
        ]);
        Http::assertSent(fn (Request $request): bool => $request->hasHeader('x-apisports-key', 'test-api-key')
            && str_starts_with($request->url(), 'https://v3.football.api-sports.io/fixtures?live=all'));
    }

    public function test_upcoming_fixtures_use_api_football_and_are_returned(): void
    {
        $fixture = $this->fixture();
        $fixture['fixture']['date'] = now()->addDay()->setTime(12, 0)->toIso8601String();
        $secondFixture = $this->fixture();
        $secondFixture['fixture']['id'] = 12346;
        $secondFixture['fixture']['date'] = now()->addDay()->setTime(13, 0)->toIso8601String();

        Http::fake(fn (Request $request) => Http::response([
            'errors' => [],
            'response' => [$fixture, $secondFixture],
        ]));

        $this->getJson('/api/fixtures/upcoming')
            ->assertOk()
            ->assertJsonPath('data.0.id', '12345')
            ->assertJsonPath('data.1.id', '12346')
            ->assertJsonPath('data.0.status', '2H')
            ->assertJsonPath('data.0.startsAt', $fixture['fixture']['date']);

        $this->assertDatabaseHas('fixtures', ['provider_id' => '12345']);
        $this->assertDatabaseHas('fixtures', ['provider_id' => '12346']);
        $this->assertDatabaseCount('leagues', 1);
        $this->assertDatabaseCount('teams', 2);

        Http::assertSent(function (Request $request): bool {
            parse_str((string) parse_url($request->url(), PHP_URL_QUERY), $query);

            return $request->hasHeader('x-apisports-key', 'test-api-key')
                && ($query['date'] ?? null) === now()->toDateString()
                && ! isset($query['from'])
                && ! isset($query['to']);
        });
    }

    public function test_empty_and_all_date_filters_default_to_today_in_selected_timezone(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-10-31T22:30:00+00:00'));
        $timezone = 'Africa/Dar_es_Salaam';
        $localDate = now($timezone)->toDateString();
        $fixture = $this->fixture();
        $fixture['fixture']['date'] = now($timezone)->addHours(2)->toIso8601String();

        Http::fake(fn () => Http::response([
            'errors' => [],
            'response' => [$fixture],
        ]));

        $this->getJson('/api/fixtures/upcoming?timezone='.$timezone)
            ->assertOk()
            ->assertJsonPath('data.0.id', '12345');
        $this->getJson('/api/fixtures/upcoming?date=all&timezone='.$timezone)
            ->assertOk()
            ->assertJsonPath('data.0.id', '12345');

        Http::assertSentCount(1);
        Http::assertSent(function (Request $request) use ($localDate, $timezone): bool {
            parse_str((string) parse_url($request->url(), PHP_URL_QUERY), $query);

            return ($query['date'] ?? null) === $localDate
                && ($query['timezone'] ?? null) === $timezone
                && ! isset($query['from'])
                && ! isset($query['to']);
        });
        Carbon::setTestNow();
    }

    public function test_upcoming_date_league_season_and_timezone_use_valid_provider_query_parameters(): void
    {
        $kickoff = now('Africa/Dar_es_Salaam')->addDay()->setTime(16, 0);
        $fixture = $this->fixture();
        $fixture['fixture']['date'] = $kickoff->toIso8601String();
        $fixture['league']['season'] = (int) $kickoff->format('Y');

        Http::fake(fn () => Http::response([
            'errors' => [],
            'response' => [$fixture],
        ]));

        $this->getJson('/api/fixtures/upcoming?date='.$kickoff->toDateString()
            .'&league=39&season='.$kickoff->format('Y')
            .'&timezone=Africa%2FDar_es_Salaam')
            ->assertOk()
            ->assertJsonPath('data.0.id', '12345');

        Http::assertSent(function (Request $request) use ($kickoff): bool {
            parse_str((string) parse_url($request->url(), PHP_URL_QUERY), $query);

            return $request->hasHeader('x-apisports-key', 'test-api-key')
                && parse_url($request->url(), PHP_URL_HOST) === 'v3.football.api-sports.io'
                && ($query['date'] ?? null) === $kickoff->toDateString()
                && ($query['league'] ?? null) === '39'
                && ($query['season'] ?? null) === $kickoff->format('Y')
                && ($query['timezone'] ?? null) === 'Africa/Dar_es_Salaam'
                && ! array_key_exists('from', $query)
                && ! array_key_exists('to', $query);
        });
    }

    public function test_provider_rejection_logs_response_body_and_returns_safe_json_fallback(): void
    {
        $body = '{"errors":{"date":"Invalid date format"},"response":[]}';
        Log::spy();
        Http::fake(fn () => Http::response([
            'errors' => ['date' => 'Invalid date format'],
            'response' => [],
        ], 200));

        $this->getJson('/api/fixtures/upcoming?date=2026-11-01')
            ->assertStatus(502)
            ->assertJsonPath('message', 'API-Football rejected the request.')
            ->assertJsonPath('data', []);

        Log::shouldHaveReceived('error')->withArgs(
            fn (string $message, array $context): bool => $message === 'API-Football rejected the request.'
                && ($context['endpoint'] ?? null) === '/fixtures'
                && ($context['status'] ?? null) === 200
                && ($context['response_body'] ?? null) === $body,
        )->once();
    }

    public function test_upcoming_filters_match_date_time_league_and_country_and_prioritize_popular(): void
    {
        $fixture = function (int $id, Carbon $startsAt, bool $popular, int $priority = 0): array {
            $item = $this->fixture();
            $item['fixture']['id'] = $id;
            $item['fixture']['date'] = $startsAt->toIso8601String();
            $item['league']['id'] = 39;
            $item['league']['name'] = 'Premier League';
            $item['league']['country'] = 'England';
            $item['is_popular'] = $popular;
            $item['priority'] = $priority;

            return $item;
        };
        $date = now()->addDay();

        Http::fake(fn () => Http::response([
            'errors' => [],
            'response' => [
                $fixture(1, $date->copy()->setTime(15, 0), false),
                $fixture(2, $date->copy()->setTime(16, 0), true),
                $fixture(3, $date->copy()->setTime(15, 30), false, 3),
                $fixture(4, $date->copy()->addDays(3)->setTime(16, 0), true),
            ],
        ]));

        $this->getJson('/api/fixtures/upcoming?date='.$date->toDateString()
            .'&time_from=15%3A00&time_to=17%3A00&league=39&country=England')
            ->assertOk()
            ->assertJsonCount(3, 'data')
            ->assertJsonPath('data.0.id', '3')
            ->assertJsonPath('data.0.isPopular', true)
            ->assertJsonPath('data.1.id', '2')
            ->assertJsonPath('data.2.id', '1');
    }

    public function test_live_fixtures_are_cached_for_subsequent_requests(): void
    {
        Http::fake(fn () => Http::response([
            'errors' => [],
            'response' => [$this->fixture()],
        ]));

        $this->getJson('/api/fixtures/live')->assertOk();
        $this->getJson('/api/fixtures/live')->assertOk();

        Http::assertSentCount(1);
        $this->assertSame(
            Cache::get('fixtures.live'),
            Cache::get('fixtures.live.stale'),
        );
    }

    public function test_live_fixtures_return_stale_cache_when_provider_fails(): void
    {
        Http::fake(fn () => throw new ConnectionException('Connection timed out.'));
        Cache::put('fixtures.live.stale', [[
            'id' => 'cached-fixture',
            'home' => ['name' => 'Cached Home'],
            'away' => ['name' => 'Cached Away'],
        ]], now()->addMinutes(10));

        $this->getJson('/api/fixtures/live')
            ->assertOk()
            ->assertJsonPath('data.0.id', 'cached-fixture')
            ->assertJsonPath('meta.stale', true);
    }

    public function test_events_and_match_insights_are_stored_and_returned(): void
    {
        Http::fake(function (Request $request) {
            if (str_contains($request->url(), '/fixtures/events')) {
                return Http::response([
                    'errors' => [],
                    'response' => [[
                        'id' => 99,
                        'time' => ['elapsed' => 67, 'extra' => null],
                        'team' => ['id' => 10, 'name' => 'Home FC'],
                        'player' => ['id' => 22, 'name' => 'Player One'],
                        'type' => 'Card',
                        'detail' => 'Red Card',
                        'comments' => null,
                    ]],
                ]);
            }

            if (str_contains($request->url(), '/fixtures/statistics')) {
                return Http::response([
                    'errors' => [],
                    'response' => [
                        [
                            'team' => ['id' => 10, 'name' => 'Home FC'],
                            'statistics' => [
                                ['type' => 'Ball Possession', 'value' => '58%'],
                                ['type' => 'Total Shots', 'value' => 10],
                                ['type' => 'Shots on Goal', 'value' => 5],
                                ['type' => 'Corner Kicks', 'value' => 4],
                                ['type' => 'Fouls', 'value' => 12],
                                ['type' => 'Yellow Cards', 'value' => 2],
                            ],
                        ],
                        [
                            'team' => ['id' => 20, 'name' => 'Away FC'],
                            'statistics' => [
                                ['type' => 'Ball Possession', 'value' => '42%'],
                                ['type' => 'Total Shots', 'value' => 7],
                                ['type' => 'Shots on Goal', 'value' => 3],
                                ['type' => 'Corner Kicks', 'value' => 2],
                                ['type' => 'Fouls', 'value' => 8],
                                ['type' => 'Yellow Cards', 'value' => 1],
                                ['type' => 'Red Cards', 'value' => 1],
                            ],
                        ],
                    ],
                ]);
            }

            return Http::response(['errors' => [], 'response' => [$this->fixture()]]);
        });

        $this->getJson('/api/fixtures/live')->assertOk();
        $this->getJson('/api/fixtures/12345/events')
            ->assertOk()
            ->assertJsonPath('data.0.isRedCard', true)
            ->assertJsonPath('data.0.minute', 67);
        $this->getJson('/api/fixtures/12345/insights')
            ->assertOk()
            ->assertJsonPath('data.home.statistics.Ball Possession', '58%')
            ->assertJsonPath('data.analysis.pressure.available', true)
            ->assertJsonPath('data.analysis.pressure.totalShots.home', 10)
            ->assertJsonPath('data.analysis.discipline.yellowCards.away', 1)
            ->assertJsonPath('data.analysis.discipline.redCards.away', 1)
            ->assertJsonPath('data.analysis.probabilities.available', true)
            ->assertJsonPath('data.analysis.referee.name', 'Test Referee')
            ->assertJsonPath('data.analysis.referee.available', false);

        $this->assertDatabaseHas('fixtures', [
            'provider_id' => '12345',
            'home_yellow_cards' => 2,
            'away_yellow_cards' => 1,
            'away_red_cards' => 1,
            'home_shots' => 10,
            'away_shots_on_target' => 3,
            'home_corners' => 4,
        ]);
        $this->assertDatabaseHas('match_events', [
            'provider_event_id' => '99',
            'fixture_id' => 1,
            'is_red_card' => true,
        ]);
        $this->assertDatabaseHas('match_insights', ['fixture_id' => 1]);
        Http::assertSent(fn (Request $request): bool => str_contains($request->url(), '/fixtures?live=all')
            && $request->hasHeader('x-apisports-key', 'test-api-key'));
        Http::assertSent(fn (Request $request): bool => str_contains($request->url(), '/fixtures/events?fixture=12345')
            && $request->hasHeader('x-apisports-key', 'test-api-key'));
        Http::assertSent(fn (Request $request): bool => str_contains($request->url(), '/fixtures/statistics?fixture=12345')
            && $request->hasHeader('x-apisports-key', 'test-api-key'));
    }

    public function test_upcoming_match_insights_use_cached_team_season_history(): void
    {
        Http::fake(function (Request $request) {
            $query = [];
            parse_str((string) parse_url($request->url(), PHP_URL_QUERY), $query);

            if (str_contains($request->url(), '/teams/statistics')) {
                $isHome = ($query['team'] ?? null) === '10';

                return Http::response([
                    'errors' => [],
                    'response' => [
                        'form' => $isHome ? 'WWDLW' : 'LDWDW',
                        'fixtures' => [
                            'played' => ['total' => 10],
                            'wins' => ['total' => $isHome ? 6 : 4],
                            'draws' => ['total' => $isHome ? 2 : 3],
                            'loses' => ['total' => $isHome ? 2 : 3],
                        ],
                        'goals' => [
                            'for' => ['average' => ['total' => $isHome ? '1.8' : '1.4']],
                            'against' => ['average' => ['total' => $isHome ? '0.9' : '1.2']],
                        ],
                        'cards' => [
                            'yellow' => ['all' => ['total' => $isHome ? 20 : 30]],
                            'red' => ['all' => ['total' => $isHome ? 1 : 2]],
                        ],
                    ],
                ]);
            }

            if (str_contains($request->url(), '/fixtures/headtohead')) {
                $pastFixture = $this->fixture();
                $pastFixture['fixture']['id'] = 111;
                $pastFixture['fixture']['date'] = now()->subMonths(2)->toIso8601String();
                $pastFixture['fixture']['status']['short'] = 'FT';
                $pastFixture['goals'] = ['home' => 1, 'away' => 0];

                return Http::response(['errors' => [], 'response' => [$pastFixture]]);
            }
            if (isset($query['team']) && isset($query['last'])) {
                $pastFixture = $this->fixture();
                $pastFixture['fixture']['id'] = 112;
                $pastFixture['fixture']['date'] = now()->subWeek()->toIso8601String();
                $pastFixture['fixture']['status']['short'] = 'FT';
                $pastFixture['goals'] = ['home' => 2, 'away' => 0];

                return Http::response(['errors' => [], 'response' => [$pastFixture]]);
            }

            $fixture = $this->fixture();
            $fixture['fixture']['date'] = now()->addDays(3)->toIso8601String();
            $fixture['fixture']['status']['short'] = 'NS';

            return Http::response(['errors' => [], 'response' => [$fixture]]);
        });

        $this->getJson('/api/fixtures/upcoming')->assertOk();
        $this->getJson('/api/fixtures/12345/insights')
            ->assertOk()
            ->assertJsonPath('data.analysis.source', 'team_season_history')
            ->assertJsonPath('data.analysis.season', 2026)
            ->assertJsonPath('data.analysis.teamHistory.home.wins', 6)
            ->assertJsonPath('data.analysis.teamHistory.home.form', 'WWDLW')
            ->assertJsonPath('data.analysis.teamHistory.away.yellowCardsPerMatch', 3)
            ->assertJsonPath('data.analysis.recentForm.home.form', 'W')
            ->assertJsonPath('data.analysis.recentForm.away.form', 'L')
            ->assertJsonPath('data.analysis.headToHead.available', true)
            ->assertJsonPath('data.analysis.headToHead.matches.0.score', '1-0')
            ->assertJsonPath('data.analysis.probabilities.available', true);
        $this->getJson('/api/fixtures/12345/insights')->assertOk();

        Http::assertSentCount(6);
        $this->assertDatabaseHas('match_insights', ['fixture_id' => 1]);
        Http::assertSent(fn (Request $request): bool => str_contains($request->url(), '/teams/statistics')
            && str_contains($request->url(), 'league=39')
            && str_contains($request->url(), 'season=2026'));
        Http::assertSent(fn (Request $request): bool => str_contains(
            $request->url(),
            '/fixtures/headtohead',
        ) && str_contains($request->url(), 'h2h=10-20'));
        Http::assertSent(fn (Request $request): bool => str_contains(
            $request->url(),
            '/fixtures?team=10',
        ) && str_contains($request->url(), 'last=5'));
    }

    public function test_live_goal_lines_use_team_history_and_remove_completed_lines(): void
    {
        Http::fake(function (Request $request) {
            $url = $request->url();
            if (str_contains($url, '/fixtures/statistics')) {
                return Http::response([
                    'errors' => [],
                    'response' => [
                        [
                            'statistics' => [
                                ['type' => 'Total Shots', 'value' => 7],
                                ['type' => 'Shots on Goal', 'value' => 3],
                            ],
                        ],
                        [
                            'statistics' => [
                                ['type' => 'Total Shots', 'value' => 6],
                                ['type' => 'Shots on Goal', 'value' => 2],
                            ],
                        ],
                    ],
                ]);
            }

            if (str_contains($url, '/teams/statistics')) {
                $query = [];
                parse_str((string) parse_url($url, PHP_URL_QUERY), $query);
                $isHome = ($query['team'] ?? null) === '10';

                return Http::response([
                    'errors' => [],
                    'response' => [
                        'fixtures' => [
                            'played' => ['total' => 10],
                            'wins' => ['total' => 5],
                            'draws' => ['total' => 2],
                            'loses' => ['total' => 3],
                        ],
                        'goals' => [
                            'for' => ['average' => ['total' => $isHome ? '1.8' : '1.4']],
                            'against' => ['average' => ['total' => $isHome ? '0.9' : '1.2']],
                        ],
                    ],
                ]);
            }

            $fixture = $this->fixture();
            $fixture['fixture']['date'] = now()->subMinutes(60)->toIso8601String();
            $fixture['fixture']['status']['elapsed'] = 60;
            $fixture['goals'] = ['home' => 1, 'away' => 1];

            return Http::response(['errors' => [], 'response' => [$fixture]]);
        });

        $this->getJson('/api/fixtures/live')->assertOk();
        $response = $this->getJson('/api/fixtures/12345/insights')
            ->assertOk()
            ->assertJsonPath('data.analysis.source', 'live_match_and_team_history')
            ->assertJsonPath('data.analysis.teamHistory.available', true)
            ->assertJsonPath('data.analysis.probabilities.available', true)
            ->assertJsonPath('data.analysis.probabilities.goalLines.0.line', 2.5)
            ->assertJsonPath('data.analysis.probabilities.goalLines.0.probability', 58);

        $lines = collect($response->json('data.analysis.probabilities.goalLines'))
            ->pluck('line')
            ->all();
        $this->assertNotContains(1.5, $lines);
        $this->assertSame(2.5, $lines[0]);
    }

    public function test_recently_synced_insights_are_returned_without_waiting_for_provider(): void
    {
        Http::fake(fn (Request $request) => Http::response([
            'errors' => [],
            'response' => [$this->fixture()],
        ]));

        $this->getJson('/api/fixtures/live')->assertOk();
        $fixture = Fixture::where('provider_id', '12345')->firstOrFail();
        $cachedInsights = [
            'fixtureId' => '12345',
            'analysis' => ['source' => 'recent_sync'],
        ];
        MatchInsight::create([
            'fixture_id' => $fixture->id,
            'data' => $cachedInsights,
            'synced_at' => now(),
        ]);
        Cache::forget('fixtures.insights.12345');
        Cache::forget('api-football.insights.12345');

        $this->getJson('/api/fixtures/12345/insights')
            ->assertOk()
            ->assertJsonPath('data.analysis.source', 'recent_sync');

        Http::assertSentCount(1);
    }

    public function test_ai_analysis_returns_reply_and_betslip_and_uses_cached_insights(): void
    {
        config([
            'services.openai.key' => 'test-openai-key',
        ]);
        Cache::forget('fixtures.upcoming');
        Cache::forget('api-football.upcoming-fixtures');
        Cache::forget('api-football.team-history.39.2026.10');
        Cache::forget('api-football.team-history.39.2026.20');
        Cache::forget('api-football.upcoming-insights.12345');
        $this->actingAs(User::create([
            'name' => 'AI Trial User',
            'email' => 'ai-trial@example.test',
            'password' => 'password123',
            'subscription_status' => 'free_trial',
            'trial_ends_at' => now()->addDays(3),
        ]));

        Http::fake(function (Request $request) {
            $url = $request->url();
            if (str_contains($url, '/chat/completions')) {
                return Http::response([
                    'choices' => [[
                        'message' => [
                            'content' => json_encode([
                                'reply' => 'Home form looks stronger, though the outcome is uncertain.',
                                'betslip' => [
                                    'picks' => [[
                                        'match' => 'Home FC v Away FC',
                                        'market' => 'Over 2.5',
                                        'odds' => 3.2,
                                        'risk' => 'moderate',
                                        'confidence' => 55,
                                    ]],
                                    'combinedOdds' => 3.2,
                                    'overallRisk' => 'moderate',
                                    'note' => 'Verify prices and team news.',
                                ],
                            ]),
                        ],
                    ]],
                ]);
            }
            if (str_contains($url, '/teams/statistics')) {
                return Http::response([
                    'errors' => [],
                    'response' => [
                        'fixtures' => [
                            'played' => ['total' => 10],
                            'wins' => ['total' => 5],
                            'draws' => ['total' => 3],
                            'loses' => ['total' => 2],
                        ],
                        'goals' => [
                            'for' => ['average' => ['total' => '1.5']],
                            'against' => ['average' => ['total' => '1.0']],
                        ],
                        'cards' => [
                            'yellow' => ['all' => ['total' => 15]],
                            'red' => ['all' => ['total' => 1]],
                        ],
                    ],
                ]);
            }

            $fixture = $this->fixture();
            $fixture['fixture']['date'] = now()->addDays(3)->toIso8601String();
            $fixture['fixture']['status']['short'] = 'NS';

            return Http::response(['errors' => [], 'response' => [$fixture]]);
        });

        $this->getJson('/api/fixtures/upcoming')->assertOk();
        $response = $this->postJson('/api/fixtures/12345/ai-analysis')
            ->assertOk()
            ->assertJsonPath('data.reply', 'Home form looks stronger, though the outcome is uncertain.')
            ->assertJsonPath('data.betslip.picks.0.market', 'Over 2.5')
            ->assertJsonPath('data.betslip.picks.0.odds', null)
            ->assertJsonPath('data.betslip.combinedOdds', null);
        $response->assertJsonCount(2, 'data');

        Cache::forget('api-football.upcoming-insights.12345');
        Cache::forget('api-football.team-history.39.2026.10');
        Cache::forget('api-football.team-history.39.2026.20');
        $this->postJson('/api/fixtures/12345/ai-analysis')->assertOk();
        Http::assertSentCount(7);
        Fixture::where('provider', 'api-football')
            ->where('provider_id', '12345')
            ->update([
                'status' => 'FT',
                'starts_at' => now()->subDay(),
            ]);
        $this->postJson('/api/fixtures/12345/ai-analysis')
            ->assertUnprocessable()
            ->assertJsonPath(
                'message',
                'AI analysis is available only for live matches or upcoming fixtures within three days.',
            );
        Http::assertSentCount(7);
        Http::assertSent(function (Request $request): bool {
            $systemPrompt = data_get($request->data(), 'messages.0.content');
            $userContent = data_get($request->data(), 'messages.1.content');

            return str_starts_with($request->url(), 'https://api.openai.com/v1/chat/completions')
                && $request->hasHeader('Content-Type', 'application/json')
                && $request->hasHeader('Authorization', 'Bearer test-openai-key')
                && data_get($request->data(), 'response_format.type') === 'json_object'
                && data_get($request->data(), 'max_tokens') === 700
                && data_get($request->data(), 'model') === 'gpt-4o-mini'
                && is_string($systemPrompt)
                && str_starts_with($systemPrompt, 'You are Mkaria AI')
                && str_contains($systemPrompt, 'reply naturally in Swahili')
                && str_contains($systemPrompt, 'no markdown, code fences, or text outside the JSON')
                && str_contains($systemPrompt, '{"reply":')
                && str_contains($systemPrompt, '"betslip":null')
                && str_contains($systemPrompt, '#1 1')
                && str_contains($systemPrompt, '#72 Away Win Either Half')
                && str_contains($systemPrompt, 'Never analyze, recommend, or refer to finished, cancelled, abandoned, or past matches')
                && str_contains($systemPrompt, 'only evaluate catalog markets whose outcomes remain unresolved')
                && str_contains($systemPrompt, '"AI Trial User"')
                && data_get($request->data(), 'messages.0.role') === 'system'
                && data_get($request->data(), 'messages.1.role') === 'user'
                && str_contains($userContent, '"country":"England"')
                && str_contains($userContent, '"date":"'.now()->addDays(3)->toDateString().'"');
        });
    }

    public function test_invalid_openai_key_returns_actionable_error_without_exposing_key(): void
    {
        $apiKey = 'test-invalid-openai-key';
        config(['services.openai.key' => $apiKey]);
        Log::spy();
        Http::fake(fn () => Http::response([
            'error' => [
                'message' => 'Provider rejected key '.$apiKey,
            ],
        ], 401));

        $exception = null;
        try {
            app(OpenAiAnalystService::class)->analyze([]);
        } catch (OpenAiApiException $error) {
            $exception = $error;
        }

        $this->assertInstanceOf(OpenAiApiException::class, $exception);
        $this->assertSame(503, $exception->statusCode);
        $this->assertStringContainsString('OpenAI rejected OPENAI_API_KEY', $exception->getMessage());
        $this->assertStringNotContainsString($apiKey, $exception->getMessage());
        Log::shouldHaveReceived('error')->once()->withArgs(
            fn (string $message, array $context): bool => $message === 'OpenAI chat completion request failed.'
                && ! str_contains($context['message'], $apiKey),
        );
        Http::assertSent(fn (Request $request): bool => $request->hasHeader(
            'Authorization',
            'Bearer '.$apiKey,
        ));
    }

    public function test_openai_always_uses_gpt_4o_mini(): void
    {
        config(['services.openai.key' => 'test-openai-key']);
        Http::fake(fn () => Http::response([
            'choices' => [[
                'message' => [
                    'content' => json_encode([
                        'reply' => 'Outcome estimate.',
                        'betslip' => null,
                    ]),
                ],
            ]],
        ]));

        $analysis = app(OpenAiAnalystService::class)->analyze([]);

        $this->assertSame('Outcome estimate.', $analysis['reply']);
        Http::assertSent(fn (Request $request): bool => data_get(
            $request->data(),
            'model',
        ) === 'gpt-4o-mini');
    }

    public function test_openai_rejects_json_missing_required_response_fields(): void
    {
        config(['services.openai.key' => 'test-openai-key']);
        Http::fake(fn () => Http::response([
            'choices' => [[
                'message' => [
                    'content' => '{"reply":"Missing betslip field"}',
                ],
            ]],
        ]));

        $exception = null;
        try {
            app(OpenAiAnalystService::class)->analyze([]);
        } catch (OpenAiApiException $error) {
            $exception = $error;
        }

        $this->assertInstanceOf(OpenAiApiException::class, $exception);
        $this->assertSame(502, $exception->statusCode);
    }

    public function test_unavailable_openai_model_returns_actionable_error(): void
    {
        config(['services.openai.key' => 'test-openai-key']);
        Http::fake(fn () => Http::response([
            'error' => [
                'message' => 'The model `missing-model` was not found.',
                'status' => 'NOT_FOUND',
            ],
        ], 404));

        $exception = null;
        try {
            app(OpenAiAnalystService::class)->analyze([]);
        } catch (OpenAiApiException $error) {
            $exception = $error;
        }

        $this->assertInstanceOf(OpenAiApiException::class, $exception);
        $this->assertSame(503, $exception->statusCode);
        $this->assertStringContainsString('gpt-4o-mini', $exception->getMessage());
    }

    public function test_openai_timeout_returns_a_clean_retryable_error(): void
    {
        config(['services.openai.key' => 'timeout-test-key']);
        Http::fake(fn () => throw new ConnectionException('cURL error 28: Operation timed out.'));

        $exception = null;
        try {
            app(OpenAiAnalystService::class)->analyze([]);
        } catch (OpenAiApiException $error) {
            $exception = $error;
        }

        $this->assertInstanceOf(OpenAiApiException::class, $exception);
        $this->assertSame(504, $exception->statusCode);
        $this->assertSame(
            'OpenAI took too long to respond. Please try again shortly.',
            $exception->getMessage(),
        );
    }

    public function test_ai_analyst_enforces_a_global_free_tier_request_limit(): void
    {
        config(['services.openai.key' => 'quota-test-'.bin2hex(random_bytes(8))]);
        Http::fake(fn () => Http::response([
            'choices' => [[
                'message' => [
                    'content' => json_encode([
                        'reply' => 'Outcome.',
                        'betslip' => null,
                    ]),
                ],
            ]],
        ]));
        $analyst = app(OpenAiAnalystService::class);

        for ($request = 0; $request < 8; $request++) {
            $analyst->analyze([]);
        }

        $exception = null;
        try {
            $analyst->analyze([]);
        } catch (OpenAiApiException $error) {
            $exception = $error;
        }

        $this->assertInstanceOf(OpenAiApiException::class, $exception);
        $this->assertSame(429, $exception->statusCode);
        Http::assertSentCount(8);
    }

    public function test_live_sync_persists_fixtures_events_insights_and_run_status(): void
    {
        Http::fake(function (Request $request) {
            if (str_contains($request->url(), '/fixtures/events')) {
                return Http::response([
                    'errors' => [],
                    'response' => [[
                        'id' => 99,
                        'time' => ['elapsed' => 67, 'extra' => null],
                        'team' => ['id' => 10, 'name' => 'Home FC'],
                        'player' => ['id' => 22, 'name' => 'Player One'],
                        'type' => 'Card',
                        'detail' => 'Red Card',
                    ]],
                ]);
            }

            if (str_contains($request->url(), '/fixtures/statistics')) {
                return Http::response(['errors' => [], 'response' => []]);
            }

            return Http::response(['errors' => [], 'response' => [$this->fixture()]]);
        });

        $result = app(ApiFootballService::class)->syncLiveData();

        $this->assertSame(['fixtures' => 1, 'events' => 1], $result);
        $this->assertDatabaseHas('sync_runs', [
            'provider' => 'api-football',
            'status' => 'success',
            'fixtures_count' => 1,
            'events_count' => 1,
        ]);
        $this->assertDatabaseHas('fixtures', ['provider_id' => '12345']);
        $this->assertDatabaseHas('match_events', ['provider_event_id' => '99']);
        $this->assertDatabaseHas('match_insights', ['fixture_id' => 1]);
    }

    public function test_rate_limited_provider_response_returns_clean_json(): void
    {
        Http::fake(fn () => Http::response(['errors' => ['rateLimit' => 'Reached']], 429));

        $this->getJson('/api/fixtures/live')
            ->assertStatus(503)
            ->assertJsonPath('message', 'API-Football rate limit reached. Please retry later.')
            ->assertJsonPath('data', []);
    }

    public function test_provider_network_failure_returns_clean_json(): void
    {
        Http::fake(fn () => throw new ConnectionException('Connection timed out.'));

        $this->getJson('/api/fixtures/live')
            ->assertStatus(503)
            ->assertJsonPath('message', 'API-Football is temporarily unavailable.')
            ->assertJsonPath('data', []);
    }

    private function fixture(): array
    {
        return [
            'fixture' => [
                'id' => 12345,
                'date' => '2026-10-22T12:00:00+00:00',
                'venue' => ['name' => 'City Stadium'],
                'referee' => 'Test Referee',
                'status' => ['short' => '2H', 'elapsed' => 67],
            ],
            'league' => [
                'id' => 39,
                'name' => 'Premier League',
                'country' => 'England',
                'logo' => 'https://example.test/league.png',
                'season' => 2026,
            ],
            'teams' => [
                'home' => ['id' => 10, 'name' => 'Home FC', 'logo' => 'https://example.test/home.png'],
                'away' => ['id' => 20, 'name' => 'Away FC', 'logo' => 'https://example.test/away.png'],
            ],
            'goals' => ['home' => 2, 'away' => 1],
        ];
    }
}
