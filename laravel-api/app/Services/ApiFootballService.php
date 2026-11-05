<?php

namespace App\Services;

use App\Models\Fixture;
use App\Models\League;
use App\Models\MatchEvent;
use App\Models\MatchInsight;
use App\Models\Team;
use Carbon\Carbon;
use DateTimeZone;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Pool;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use InvalidArgumentException;
use RuntimeException;
use Throwable;

class ApiFootballService
{
    public function liveFixtures(): array
    {
        return Cache::remember('api-football.live-fixtures', 60, fn (): array => $this->fetchLiveFixtures());
    }

    public function upcomingFixtures(array $filters = []): array
    {
        $timezone = $filters['timezone'] ?? config('app.timezone', 'UTC');
        if (! is_string($timezone) || $timezone === '') {
            $timezone = 'UTC';
        }
        try {
            new DateTimeZone($timezone);
        } catch (InvalidArgumentException $error) {
            throw new InvalidArgumentException('API-Football timezone must be a valid IANA timezone.', 0, $error);
        }

        $now = now(is_string($timezone) ? $timezone : 'UTC');
        $query = $this->upcomingFixtureQuery($filters, $now->toDateString());
        $cacheKey = 'api-football.upcoming-fixtures.'.hash(
            'sha256',
            json_encode($query, JSON_THROW_ON_ERROR),
        );

        return Cache::remember(
            $cacheKey,
            300,
            fn (): array => $this->fetchUpcomingFixtures($query),
        );
    }

    public function fixtureEvents(string $providerId): array
    {
        return Cache::remember(
            "api-football.events.$providerId",
            60,
            fn (): array => $this->fetchFixtureEvents($providerId),
        );
    }

    public function matchInsights(string $providerId): array
    {
        $this->validateFixtureId($providerId);
        $fixture = Fixture::with(['homeTeam', 'awayTeam'])
            ->where('provider', 'api-football')
            ->where('provider_id', $providerId)
            ->first();

        if ($fixture?->starts_at?->isFuture()) {
            return Cache::remember(
                "api-football.upcoming-insights.$providerId",
                21600,
                function () use ($fixture): array {
                    $storedInsights = $this->recentStoredInsights($fixture);
                    if ($storedInsights !== null) {
                        return $storedInsights;
                    }

                    $data = $this->fetchUpcomingMatchInsights($fixture);
                    MatchInsight::updateOrCreate(
                        ['fixture_id' => $fixture->id],
                        ['data' => $data, 'synced_at' => now()],
                    );

                    return $data;
                },
            );
        }

        return Cache::remember("api-football.insights.$providerId", 60, function () use ($providerId, $fixture): array {
            $storedInsights = $this->recentStoredInsights($fixture, 60);
            if ($storedInsights !== null) {
                return $storedInsights;
            }

            return $this->fetchMatchInsights($providerId, $fixture);
        });
    }

    public function syncLiveData(): array
    {
        $startedAt = now();
        $runId = DB::table('sync_runs')->insertGetId([
            'provider' => 'api-football',
            'status' => 'running',
            'started_at' => $startedAt,
            'created_at' => $startedAt,
            'updated_at' => $startedAt,
        ]);

        try {
            $fixtures = $this->fetchLiveFixtures();
            $eventsCount = 0;
            Cache::put('api-football.live-fixtures', $fixtures, 60);

            foreach ($fixtures as $fixture) {
                $events = $this->fetchFixtureEvents($fixture['id']);
                $eventsCount += count($events);
                Cache::put("api-football.events.{$fixture['id']}", $events, 60);

                $insights = $this->fetchMatchInsights($fixture['id']);
                Cache::put("api-football.insights.{$fixture['id']}", $insights, 300);
            }

            DB::table('sync_runs')->where('id', $runId)->update([
                'status' => 'success',
                'fixtures_count' => count($fixtures),
                'events_count' => $eventsCount,
                'finished_at' => now(),
                'updated_at' => now(),
            ]);

            return ['fixtures' => count($fixtures), 'events' => $eventsCount];
        } catch (Throwable $error) {
            DB::table('sync_runs')->where('id', $runId)->update([
                'status' => 'failed',
                'error_message' => Str::limit($error->getMessage(), 60000),
                'finished_at' => now(),
                'updated_at' => now(),
            ]);
            report($error);
            throw $error;
        }
    }

    private function fetchLiveFixtures(): array
    {
        $response = $this->request('/fixtures', ['live' => 'all'], timeoutSeconds: 18);
        $fixtures = collect($response['response'] ?? [])
            ->filter(fn (mixed $item): bool => is_array($item))
            ->map(fn (array $item): array => $this->normalizeFixture($item))
            ->filter(fn (array $fixture): bool => $fixture['id'] !== '')
            ->values()
            ->all();

        foreach ($fixtures as $fixture) {
            $this->storeFixture($fixture);
        }

        return $fixtures;
    }

    private function fetchUpcomingFixtures(array $query): array
    {
        $response = $this->request('/fixtures', $query, timeoutSeconds: 18);
        $fixtures = collect($response['response'] ?? [])
            ->filter(fn (mixed $item): bool => is_array($item))
            ->map(fn (array $item): array => $this->normalizeFixture($item))
            ->filter(fn (array $fixture): bool => $fixture['id'] !== '')
            ->values()
            ->all();

        $this->storeFixtures($fixtures);

        return $fixtures;
    }

    /**
     * Persist an upcoming provider response in batches so a full day's schedule
     * does not trigger several database round trips for every fixture.
     *
     * @param  array<int, array<string, mixed>>  $fixtures
     */
    private function storeFixtures(array $fixtures): void
    {
        if ($fixtures === []) {
            return;
        }

        $timestamp = now()->toDateTimeString();
        $leagues = [];
        $teams = [];

        foreach ($fixtures as $fixture) {
            $league = $fixture['league'];
            $leagues[$league['id']] = [
                'provider' => 'api-football',
                'provider_id' => $league['id'],
                'name' => $league['name'],
                'country' => $league['country'],
                'logo_url' => $league['logo'],
                'created_at' => $timestamp,
                'updated_at' => $timestamp,
            ];

            foreach (['home', 'away'] as $side) {
                $team = $fixture[$side];
                $providerId = $team['id'] !== '' ? $team['id'] : 'name:'.Str::slug($team['name']);
                $teams[$providerId] = [
                    'provider' => 'api-football',
                    'provider_id' => $providerId,
                    'name' => $team['name'],
                    'logo_url' => $team['logo'] ?: null,
                    'created_at' => $timestamp,
                    'updated_at' => $timestamp,
                ];
            }
        }

        DB::transaction(function () use ($fixtures, $leagues, $teams, $timestamp): void {
            foreach (array_chunk(array_values($leagues), 100) as $chunk) {
                DB::table('leagues')->upsert(
                    $chunk,
                    ['provider', 'provider_id'],
                    ['name', 'country', 'logo_url', 'updated_at'],
                );
            }
            foreach (array_chunk(array_values($teams), 100) as $chunk) {
                DB::table('teams')->upsert(
                    $chunk,
                    ['provider', 'provider_id'],
                    ['name', 'logo_url', 'updated_at'],
                );
            }

            $leagueIds = $this->providerRecordIds('leagues', array_keys($leagues));
            $teamIds = $this->providerRecordIds('teams', array_keys($teams));
            $fixtureRows = [];

            foreach ($fixtures as $fixture) {
                $homeProviderId = $fixture['home']['id'] !== ''
                    ? $fixture['home']['id']
                    : 'name:'.Str::slug($fixture['home']['name']);
                $awayProviderId = $fixture['away']['id'] !== ''
                    ? $fixture['away']['id']
                    : 'name:'.Str::slug($fixture['away']['name']);

                $fixtureRows[] = [
                    'provider' => 'api-football',
                    'provider_id' => $fixture['id'],
                    'league_id' => $leagueIds[$fixture['league']['id']],
                    'home_team_id' => $teamIds[$homeProviderId],
                    'away_team_id' => $teamIds[$awayProviderId],
                    'status' => $fixture['status'],
                    'minute' => $fixture['minute'],
                    'venue' => $fixture['venue'],
                    'referee' => $fixture['referee'],
                    'season' => $fixture['league']['season'],
                    'has_timeline' => $fixture['hasTimeline'],
                    'home_score' => $fixture['home']['goals'],
                    'away_score' => $fixture['away']['goals'],
                    'starts_at' => $fixture['startsAt'] === null
                        ? null
                        : Carbon::parse($fixture['startsAt'])->utc()->toDateTimeString(),
                    'last_synced_at' => $timestamp,
                    'created_at' => $timestamp,
                    'updated_at' => $timestamp,
                ];
            }

            foreach (array_chunk($fixtureRows, 100) as $chunk) {
                DB::table('fixtures')->upsert(
                    $chunk,
                    ['provider_id'],
                    [
                        'provider', 'league_id', 'home_team_id', 'away_team_id',
                        'status', 'minute', 'venue', 'referee', 'season',
                        'has_timeline', 'home_score', 'away_score', 'starts_at',
                        'last_synced_at', 'updated_at',
                    ],
                );
            }
        });
    }

    /**
     * @param  array<int, string>  $providerIds
     * @return array<string, int>
     */
    private function providerRecordIds(string $table, array $providerIds): array
    {
        $ids = [];
        foreach (array_chunk($providerIds, 100) as $chunk) {
            $ids += DB::table($table)
                ->where('provider', 'api-football')
                ->whereIn('provider_id', $chunk)
                ->pluck('id', 'provider_id')
                ->all();
        }

        return $ids;
    }

    /**
     * Build only documented and validated API-Football fixtures parameters.
     *
     * @param  array<string, mixed>  $filters
     * @return array<string, string|int>
     */
    private function upcomingFixtureQuery(array $filters, string $today): array
    {
        $date = $filters['date'] ?? null;
        if (is_string($date) && strtolower(trim($date)) === 'all') {
            $date = null;
        }
        if ($date === null || $date === '') {
            $date = $today;
        }

        if (! is_string($date)) {
            throw new InvalidArgumentException('API-Football date must use YYYY-MM-DD.');
        }
        $dateParts = explode('-', $date);
        if (! preg_match('/^\d{4}-\d{2}-\d{2}$/', $date)
            || count($dateParts) !== 3
            || ! checkdate((int) $dateParts[1], (int) $dateParts[2], (int) $dateParts[0])) {
            throw new InvalidArgumentException('API-Football date must use YYYY-MM-DD.');
        }

        $query = ['date' => $date];
        $league = $filters['league'] ?? null;
        $season = $filters['season'] ?? null;
        if (($league !== null && $league !== '') && ctype_digit((string) $league)) {
            if ($season === null || $season === '') {
                $season = Fixture::query()
                    ->where('provider', 'api-football')
                    ->whereHas('league', fn ($query) => $query
                        ->where('provider', 'api-football')
                        ->where('provider_id', (string) $league))
                    ->whereNotNull('season')
                    ->max('season');
            }
            if ($season !== null && $season !== '') {
                if (! is_string($season) && ! is_int($season) || ! ctype_digit((string) $season)
                    || (int) $season < 1900 || (int) $season > 2100) {
                    throw new InvalidArgumentException('API-Football season must be a valid four-digit year.');
                }
                $query['league'] = (string) $league;
                $query['season'] = (int) $season;
            }
        } elseif ($season !== null && $season !== '') {
            if (! is_string($season) && ! is_int($season) || ! ctype_digit((string) $season)
                || (int) $season < 1900 || (int) $season > 2100) {
                throw new InvalidArgumentException('API-Football season must be a valid four-digit year.');
            }
            $query['season'] = (int) $season;
        }

        $timezone = $filters['timezone'] ?? config('app.timezone', 'UTC');
        if (is_string($timezone) && $timezone !== '') {
            try {
                new DateTimeZone($timezone);
                $query['timezone'] = $timezone;
            } catch (InvalidArgumentException $error) {
                throw new InvalidArgumentException('API-Football timezone must be a valid IANA timezone.', 0, $error);
            }
        }

        return $query;
    }

    private function fetchFixtureEvents(string $providerId): array
    {
        $this->validateFixtureId($providerId);
        $fixture = Fixture::where('provider', 'api-football')
            ->where('provider_id', $providerId)
            ->first();
        $response = $this->request(
            '/fixtures/events',
            ['fixture' => $providerId],
            timeoutSeconds: 18,
        );

        return collect($response['response'] ?? [])
            ->filter(fn (mixed $item): bool => is_array($item))
            ->map(fn (array $event): array => $this->normalizeEvent($providerId, $event))
            ->tap(fn ($events) => $events->each(fn (array $event) => $this->storeEvent($event, $fixture)))
            ->values()
            ->all();
    }

    private function fetchMatchInsights(string $providerId, ?Fixture $fixture = null): array
    {
        $this->validateFixtureId($providerId);
        $response = $this->request(
            '/fixtures/statistics',
            ['fixture' => $providerId],
            timeoutSeconds: 18,
        );
        $teams = collect($response['response'] ?? [])
            ->filter(fn (mixed $item): bool => is_array($item))
            ->values();
        $home = $this->normalizeTeamStatistics($teams->get(0, []));
        $away = $this->normalizeTeamStatistics($teams->get(1, []));
        $fixture ??= Fixture::with(['homeTeam', 'awayTeam', 'league'])
            ->where('provider', 'api-football')
            ->where('provider_id', $providerId)
            ->first();
        $homeHistory = $this->emptyTeamSeasonHistory();
        $awayHistory = $this->emptyTeamSeasonHistory();
        if ($fixture && $fixture->league && $fixture->homeTeam && $fixture->awayTeam) {
            [$homeHistory, $awayHistory] = $this->fetchTeamSeasonHistories(
                [
                    'home' => (string) $fixture->homeTeam->provider_id,
                    'away' => (string) $fixture->awayTeam->provider_id,
                ],
                (string) $fixture->league->provider_id,
                (int) ($fixture->season ?? $fixture->starts_at?->year ?? now()->year),
            );
        }
        $data = [
            'fixtureId' => $providerId,
            'home' => $home,
            'away' => $away,
            'analysis' => $this->buildMatchAnalysis(
                $home['statistics'],
                $away['statistics'],
                (int) ($fixture?->home_score ?? 0),
                (int) ($fixture?->away_score ?? 0),
                $fixture?->referee,
                $homeHistory,
                $awayHistory,
                $fixture?->minute,
            ),
        ];
        $data['analysis']['source'] = 'live_match_and_team_history';

        if ($fixture) {
            $fixture->fill([
                'home_yellow_cards' => $this->statCount($home['statistics'], 'Yellow Cards'),
                'away_yellow_cards' => $this->statCount($away['statistics'], 'Yellow Cards'),
                'home_red_cards' => $this->statCount($home['statistics'], 'Red Cards'),
                'away_red_cards' => $this->statCount($away['statistics'], 'Red Cards'),
                'home_shots' => $this->statCount($home['statistics'], 'Total Shots'),
                'away_shots' => $this->statCount($away['statistics'], 'Total Shots'),
                'home_shots_on_target' => $this->statCount($home['statistics'], 'Shots on Goal'),
                'away_shots_on_target' => $this->statCount($away['statistics'], 'Shots on Goal'),
                'home_corners' => $this->statCount($home['statistics'], 'Corner Kicks'),
                'away_corners' => $this->statCount($away['statistics'], 'Corner Kicks'),
            ])->save();
            MatchInsight::updateOrCreate(
                ['fixture_id' => $fixture->id],
                ['data' => $data, 'synced_at' => now()],
            );
        }

        return $data;
    }

    private function fetchUpcomingMatchInsights(Fixture $fixture): array
    {
        $season = (int) ($fixture->season ?? $fixture->starts_at?->year ?? now()->year);
        $leagueId = (string) $fixture->league->provider_id;
        $homeTeamId = (string) $fixture->homeTeam->provider_id;
        $awayTeamId = (string) $fixture->awayTeam->provider_id;
        [$homeHistory, $awayHistory] = $this->fetchTeamSeasonHistories(
            [
                'home' => $homeTeamId,
                'away' => $awayTeamId,
            ],
            $leagueId,
            $season,
        );
        $recentForm = [
            'home' => $this->recentTeamResults($homeTeamId),
            'away' => $this->recentTeamResults($awayTeamId),
        ];
        $headToHead = $this->headToHeadResults($homeTeamId, $awayTeamId);

        $homeExpectedGoals = $this->expectedGoalsForUpcomingMatch($homeHistory, $awayHistory);
        $awayExpectedGoals = $this->expectedGoalsForUpcomingMatch($awayHistory, $homeHistory);
        $totalExpectedGoals = $homeExpectedGoals !== null && $awayExpectedGoals !== null
            ? $homeExpectedGoals + $awayExpectedGoals
            : null;
        $homeYellowAverage = $homeHistory['yellowCardsPerMatch'];
        $awayYellowAverage = $awayHistory['yellowCardsPerMatch'];
        $homeRedAverage = $homeHistory['redCardsPerMatch'];
        $awayRedAverage = $awayHistory['redCardsPerMatch'];

        return [
            'fixtureId' => $fixture->provider_id,
            'home' => [
                'name' => $fixture->homeTeam->name,
                'statistics' => [],
            ],
            'away' => [
                'name' => $fixture->awayTeam->name,
                'statistics' => [],
            ],
            'analysis' => [
                'source' => 'team_season_history',
                'season' => $season,
                'teamHistory' => [
                    'home' => $homeHistory,
                    'away' => $awayHistory,
                    'available' => $homeHistory['available'] || $awayHistory['available'],
                ],
                'recentForm' => $recentForm,
                'headToHead' => $headToHead,
                'pressure' => [
                    'totalShots' => ['home' => null, 'away' => null],
                    'shotsOnTarget' => ['home' => null, 'away' => null],
                    'corners' => ['home' => null, 'away' => null],
                    'possession' => ['home' => null, 'away' => null],
                    'momentum' => ['home' => null, 'away' => null],
                    'available' => false,
                ],
                'discipline' => [
                    'yellowCards' => [
                        'home' => $homeHistory['yellowCardsPerMatch'],
                        'away' => $awayHistory['yellowCardsPerMatch'],
                    ],
                    'redCards' => [
                        'home' => $homeHistory['redCardsPerMatch'],
                        'away' => $awayHistory['redCardsPerMatch'],
                    ],
                    'aggressionIndex' => [
                        'home' => $this->historyAggressionIndex($homeHistory),
                        'away' => $this->historyAggressionIndex($awayHistory),
                    ],
                    'available' => $homeYellowAverage !== null
                        || $awayYellowAverage !== null
                        || $homeRedAverage !== null
                        || $awayRedAverage !== null,
                ],
                'referee' => [
                    'name' => $fixture->referee,
                    'yellowCardsPerMatch' => null,
                    'redCardsPerMatch' => null,
                    'sampleMatches' => 0,
                    'available' => false,
                ],
                'probabilities' => $totalExpectedGoals === null
                    ? [
                        'over15' => null,
                        'over25' => null,
                        'goalLines' => [],
                        'btts' => null,
                        'expectedGoals' => null,
                        'available' => false,
                        'method' => 'Recent team scoring history is unavailable.',
                    ]
                    : [
                        'over15' => $this->poissonAtLeast($totalExpectedGoals, 2),
                        'over25' => $this->poissonAtLeast($totalExpectedGoals, 3),
                        'goalLines' => $this->goalLines($totalExpectedGoals, 0),
                        'btts' => $this->historyBttsProbability($homeHistory, $awayHistory),
                        'expectedGoals' => round($totalExpectedGoals, 2),
                        'available' => true,
                        'method' => "Estimated from {$season} league-season team goal averages; not a guarantee.",
                    ],
            ],
        ];
    }

    /**
     * @return array{form: string, matches: array<int, array<string, mixed>>, available: bool}
     */
    private function recentTeamResults(string $teamId): array
    {
        $empty = ['form' => '', 'matches' => [], 'available' => false];
        if (! ctype_digit($teamId)) {
            return $empty;
        }

        return Cache::remember(
            "api-football.team-recent-results.$teamId",
            1800,
            function () use ($teamId, $empty): array {
                try {
                    $response = $this->request('/fixtures', [
                        'team' => $teamId,
                        'last' => 5,
                    ]);
                } catch (ApiFootballException $error) {
                    report($error);

                    return $empty;
                }

                $matches = collect($response['response'] ?? [])
                    ->filter(fn (mixed $item): bool => is_array($item))
                    ->filter(fn (array $item): bool => $this->isCompletedPastFixture($item))
                    ->map(fn (array $item): array => $this->normalizeFixture($item))
                    ->sortByDesc(fn (array $fixture): int => strtotime((string) $fixture['startsAt']) ?: 0)
                    ->take(5)
                    ->map(function (array $fixture) use ($teamId): array {
                        $isHome = $fixture['home']['id'] === $teamId;
                        $teamGoals = $isHome ? $fixture['home']['goals'] : $fixture['away']['goals'];
                        $opponentGoals = $isHome ? $fixture['away']['goals'] : $fixture['home']['goals'];
                        $result = $teamGoals > $opponentGoals
                            ? 'W'
                            : ($teamGoals === $opponentGoals ? 'D' : 'L');

                        return [
                            'date' => $fixture['startsAt'],
                            'opponent' => $isHome ? $fixture['away']['name'] : $fixture['home']['name'],
                            'score' => "$teamGoals-$opponentGoals",
                            'result' => $result,
                            'league' => $fixture['league']['name'],
                        ];
                    })
                    ->values()
                    ->all();

                return [
                    'form' => implode('', array_column($matches, 'result')),
                    'matches' => $matches,
                    'available' => $matches !== [],
                ];
            },
        );
    }

    /**
     * @return array{matches: array<int, array<string, mixed>>, available: bool}
     */
    private function headToHeadResults(string $homeTeamId, string $awayTeamId): array
    {
        $empty = ['matches' => [], 'available' => false];
        if (! ctype_digit($homeTeamId) || ! ctype_digit($awayTeamId)) {
            return $empty;
        }

        $teamIds = [$homeTeamId, $awayTeamId];
        sort($teamIds, SORT_NUMERIC);
        $cacheKey = 'api-football.head-to-head.'.implode('-', $teamIds);

        return Cache::remember($cacheKey, 21600, function () use ($homeTeamId, $awayTeamId, $empty): array {
            try {
                $response = $this->request('/fixtures/headtohead', [
                    'h2h' => "$homeTeamId-$awayTeamId",
                    'last' => 5,
                ]);
            } catch (ApiFootballException $error) {
                report($error);

                return $empty;
            }

            $matches = collect($response['response'] ?? [])
                ->filter(fn (mixed $item): bool => is_array($item))
                ->filter(fn (array $item): bool => $this->isCompletedPastFixture($item))
                ->map(fn (array $item): array => $this->normalizeFixture($item))
                ->sortByDesc(fn (array $fixture): int => strtotime((string) $fixture['startsAt']) ?: 0)
                ->take(5)
                ->map(fn (array $fixture): array => [
                    'date' => $fixture['startsAt'],
                    'home' => $fixture['home']['name'],
                    'away' => $fixture['away']['name'],
                    'score' => $fixture['home']['goals'].'-'.$fixture['away']['goals'],
                    'league' => $fixture['league']['name'],
                ])
                ->values()
                ->all();

            return ['matches' => $matches, 'available' => $matches !== []];
        });
    }

    private function isCompletedPastFixture(array $item): bool
    {
        $status = strtoupper((string) Arr::get($item, 'fixture.status.short', ''));
        $kickoff = strtotime((string) Arr::get($item, 'fixture.date', ''));

        return in_array($status, ['FT', 'AET', 'PEN'], true)
            && $kickoff !== false
            && $kickoff < now()->timestamp
            && is_numeric(Arr::get($item, 'goals.home'))
            && is_numeric(Arr::get($item, 'goals.away'));
    }

    private function fetchTeamSeasonHistories(
        array $teamIds,
        string $leagueId,
        int $season,
    ): array {
        $empty = $this->emptyTeamSeasonHistory();
        $histories = ['home' => $empty, 'away' => $empty];
        $missing = [];

        foreach ($teamIds as $side => $teamId) {
            if (! ctype_digit($teamId) || ! ctype_digit($leagueId)) {
                continue;
            }

            $cacheKey = "api-football.team-history.$leagueId.$season.$teamId";
            if (Cache::has($cacheKey)) {
                $cached = Cache::get($cacheKey);
                $histories[$side] = is_array($cached) ? $cached : $empty;
            } else {
                $missing[$side] = $teamId;
            }
        }

        if ($missing === []) {
            return [$histories['home'], $histories['away']];
        }

        $key = config('services.apifootball.key');
        if (! is_string($key) || trim($key) === '') {
            report(new ApiFootballException('API-Football is not configured.', 503));

            return [$histories['home'], $histories['away']];
        }

        $baseUrl = rtrim((string) config('services.apifootball.base_url'), '/');
        try {
            $responses = Http::pool(function (Pool $pool) use (
                $missing,
                $leagueId,
                $season,
                $key,
                $baseUrl,
            ): array {
                $requests = [];
                foreach ($missing as $side => $teamId) {
                    $requests[$side] = $pool->as($side)
                        ->acceptJson()
                        ->withHeaders(['x-apisports-key' => $key])
                        ->timeout(15)
                        ->get($baseUrl.'/teams/statistics', [
                            'league' => $leagueId,
                            'season' => $season,
                            'team' => $teamId,
                        ]);
                }

                return $requests;
            });
        } catch (Throwable $error) {
            report($error);

            return [$histories['home'], $histories['away']];
        }

        foreach ($missing as $side => $teamId) {
            $response = $responses[$side] ?? null;
            if (! $response instanceof Response || ! $response->successful()) {
                report(new ApiFootballException(
                    'API-Football could not return team-season statistics.',
                    $response?->tooManyRequests() ? 503 : 502,
                ));

                continue;
            }

            $payload = $response->json();
            $data = is_array($payload) ? ($payload['response'] ?? null) : null;
            if (! is_array($data) || $data === [] || ! empty($payload['errors'])) {
                report(new ApiFootballException(
                    'API-Football returned invalid team-season statistics.',
                    502,
                ));

                continue;
            }

            $history = $this->normalizeTeamSeasonHistory($data);
            $histories[$side] = $history;
            Cache::put(
                "api-football.team-history.$leagueId.$season.$teamId",
                $history,
                21600,
            );
        }

        return [$histories['home'], $histories['away']];
    }

    private function emptyTeamSeasonHistory(): array
    {
        return [
            'played' => null,
            'wins' => null,
            'draws' => null,
            'losses' => null,
            'form' => null,
            'goalsForPerMatch' => null,
            'goalsAgainstPerMatch' => null,
            'yellowCardsPerMatch' => null,
            'redCardsPerMatch' => null,
            'available' => false,
        ];
    }

    private function normalizeTeamSeasonHistory(array $data): array
    {
        $played = (int) Arr::get($data, 'fixtures.played.total', 0);
        $goalsFor = Arr::get($data, 'goals.for.average.total');
        $goalsAgainst = Arr::get($data, 'goals.against.average.total');
        $yellowTotal = $this->sumCardTotals(Arr::get($data, 'cards.yellow', []));
        $redTotal = $this->sumCardTotals(Arr::get($data, 'cards.red', []));

        return [
            'played' => $played,
            'wins' => (int) Arr::get($data, 'fixtures.wins.total', 0),
            'draws' => (int) Arr::get($data, 'fixtures.draws.total', 0),
            'losses' => (int) Arr::get($data, 'fixtures.loses.total', 0),
            'form' => isset($data['form']) && is_string($data['form'])
                ? substr($data['form'], -5)
                : null,
            'goalsForPerMatch' => is_numeric($goalsFor) ? (float) $goalsFor : null,
            'goalsAgainstPerMatch' => is_numeric($goalsAgainst) ? (float) $goalsAgainst : null,
            'yellowCardsPerMatch' => $played > 0 && $yellowTotal !== null
                ? round($yellowTotal / $played, 2)
                : null,
            'redCardsPerMatch' => $played > 0 && $redTotal !== null
                ? round($redTotal / $played, 2)
                : null,
            'available' => $played > 0,
        ];
    }

    private function recentStoredInsights(?Fixture $fixture, int $freshForSeconds = 300): ?array
    {
        if (! $fixture) {
            return null;
        }

        $insights = MatchInsight::query()
            ->where('fixture_id', $fixture->id)
            ->where('synced_at', '>=', now()->subSeconds($freshForSeconds))
            ->value('data');

        return is_array($insights) ? $insights : null;
    }

    private function sumCardTotals(mixed $cardGroups): ?int
    {
        if (! is_array($cardGroups) || $cardGroups === []) {
            return null;
        }

        $totals = array_filter(
            array_map(
                static fn (mixed $group): mixed => is_array($group) ? ($group['total'] ?? null) : null,
                $cardGroups,
            ),
            static fn (mixed $total): bool => is_numeric($total),
        );

        return $totals === [] ? null : array_sum($totals);
    }

    private function expectedGoalsForUpcomingMatch(
        array $teamHistory,
        array $opponentHistory,
    ): ?float {
        $scored = $teamHistory['goalsForPerMatch'];
        $conceded = $opponentHistory['goalsAgainstPerMatch'];
        if ($scored === null || $conceded === null) {
            return null;
        }

        return max(0, ($scored + $conceded) / 2);
    }

    private function historyBttsProbability(array $homeHistory, array $awayHistory): ?int
    {
        $homeScored = $homeHistory['goalsForPerMatch'];
        $homeConceded = $homeHistory['goalsAgainstPerMatch'];
        $awayScored = $awayHistory['goalsForPerMatch'];
        $awayConceded = $awayHistory['goalsAgainstPerMatch'];
        if ($homeScored === null || $homeConceded === null
            || $awayScored === null || $awayConceded === null) {
            return null;
        }

        $homeExpected = ($homeScored + $awayConceded) / 2;
        $awayExpected = ($awayScored + $homeConceded) / 2;

        return (int) round(
            (1 - exp(-$homeExpected)) * (1 - exp(-$awayExpected)) * 100,
        );
    }

    private function historyAggressionIndex(array $history): ?int
    {
        $yellow = $history['yellowCardsPerMatch'];
        $red = $history['redCardsPerMatch'];
        if ($yellow === null && $red === null) {
            return null;
        }

        return (int) round(min(100, ($yellow ?? 0) * 20 + ($red ?? 0) * 40));
    }

    private function buildMatchAnalysis(
        array $homeStats,
        array $awayStats,
        int $homeGoals,
        int $awayGoals,
        ?string $referee,
        array $homeHistory,
        array $awayHistory,
        ?int $minute,
    ): array {
        $homeShots = $this->statNumber($homeStats, 'Total Shots');
        $awayShots = $this->statNumber($awayStats, 'Total Shots');
        $homeOnTarget = $this->statNumber($homeStats, 'Shots on Goal');
        $awayOnTarget = $this->statNumber($awayStats, 'Shots on Goal');
        $homeCorners = $this->statNumber($homeStats, 'Corner Kicks');
        $awayCorners = $this->statNumber($awayStats, 'Corner Kicks');
        $homePossession = $this->statNumber($homeStats, 'Ball Possession');
        $awayPossession = $this->statNumber($awayStats, 'Ball Possession');
        $homeFouls = $this->statNumber($homeStats, 'Fouls');
        $awayFouls = $this->statNumber($awayStats, 'Fouls');
        $homeYellow = $this->statNumber($homeStats, 'Yellow Cards');
        $awayYellow = $this->statNumber($awayStats, 'Yellow Cards');
        $homeRed = $this->statNumber($homeStats, 'Red Cards');
        $awayRed = $this->statNumber($awayStats, 'Red Cards');

        $homePressure = $this->pressureIndex($homeShots, $homeOnTarget, $homeCorners);
        $awayPressure = $this->pressureIndex($awayShots, $awayOnTarget, $awayCorners);

        return [
            'pressure' => [
                'totalShots' => ['home' => $homeShots, 'away' => $awayShots],
                'shotsOnTarget' => ['home' => $homeOnTarget, 'away' => $awayOnTarget],
                'corners' => ['home' => $homeCorners, 'away' => $awayCorners],
                'possession' => ['home' => $homePossession, 'away' => $awayPossession],
                'momentum' => ['home' => $homePressure, 'away' => $awayPressure],
                'available' => $homeShots !== null || $awayShots !== null
                    || $homeOnTarget !== null || $awayOnTarget !== null
                    || $homeCorners !== null || $awayCorners !== null,
            ],
            'discipline' => [
                'yellowCards' => ['home' => $homeYellow, 'away' => $awayYellow],
                'redCards' => ['home' => $homeRed, 'away' => $awayRed],
                'aggressionIndex' => [
                    'home' => $this->aggressionIndex($homeFouls, $homeYellow, $homeRed),
                    'away' => $this->aggressionIndex($awayFouls, $awayYellow, $awayRed),
                ],
                'available' => $homeFouls !== null || $awayFouls !== null
                    || $homeYellow !== null || $awayYellow !== null
                    || $homeRed !== null || $awayRed !== null,
            ],
            'referee' => [
                'name' => $referee,
                'yellowCardsPerMatch' => null,
                'redCardsPerMatch' => null,
                'sampleMatches' => 0,
                'available' => false,
            ],
            'teamHistory' => [
                'home' => $homeHistory,
                'away' => $awayHistory,
                'available' => $homeHistory['available'] || $awayHistory['available'],
            ],
            'probabilities' => $this->goalProbabilities(
                $homeStats,
                $awayStats,
                $homeGoals,
                $awayGoals,
                $homeHistory,
                $awayHistory,
                $minute,
            ),
        ];
    }

    private function statNumber(array $statistics, string $key): ?float
    {
        $value = $statistics[$key] ?? null;
        if (! is_string($value) && ! is_numeric($value)) {
            return null;
        }

        $number = preg_replace('/[^0-9.\-]/', '', (string) $value);

        return $number !== '' && is_numeric($number) ? (float) $number : null;
    }

    private function statCount(array $statistics, string $key): ?int
    {
        $value = $this->statNumber($statistics, $key);

        return $value === null ? null : max(0, (int) round($value));
    }

    private function pressureIndex(?float $shots, ?float $onTarget, ?float $corners): ?int
    {
        if ($shots === null && $onTarget === null && $corners === null) {
            return null;
        }

        $weightedPressure = ($shots ?? 0) + (($onTarget ?? 0) * 2) + (($corners ?? 0) * 1.5);

        return (int) round(min(100, 100 * $weightedPressure / ($weightedPressure + 24)));
    }

    private function aggressionIndex(?float $fouls, ?float $yellowCards, ?float $redCards): ?int
    {
        if ($fouls === null && $yellowCards === null && $redCards === null) {
            return null;
        }

        return (int) round(min(
            100,
            ($fouls ?? 0) * 1.5 + ($yellowCards ?? 0) * 12 + ($redCards ?? 0) * 25,
        ));
    }

    private function goalProbabilities(
        array $homeStats,
        array $awayStats,
        int $homeGoals,
        int $awayGoals,
        array $homeHistory,
        array $awayHistory,
        ?int $minute,
    ): array {
        $homeShotsOnTarget = $this->statNumber($homeStats, 'Shots on Goal');
        $awayShotsOnTarget = $this->statNumber($awayStats, 'Shots on Goal');
        $homeShots = $this->statNumber($homeStats, 'Total Shots');
        $awayShots = $this->statNumber($awayStats, 'Total Shots');
        $available = $homeShotsOnTarget !== null || $awayShotsOnTarget !== null
            || $homeShots !== null || $awayShots !== null
            || $homeGoals > 0 || $awayGoals > 0;

        if (! $available) {
            return [
                'over15' => null,
                'over25' => null,
                'goalLines' => [],
                'btts' => null,
                'expectedGoals' => null,
                'available' => false,
                'method' => 'Not enough match data to estimate probabilities.',
            ];
        }

        $homeStatEstimate = $homeGoals + ($homeShotsOnTarget ?? 0) * 0.28
            + ($homeShots ?? 0) * 0.025;
        $awayStatEstimate = $awayGoals + ($awayShotsOnTarget ?? 0) * 0.28
            + ($awayShots ?? 0) * 0.025;
        $currentGoals = $homeGoals + $awayGoals;
        $elapsed = max(1, min(90, $minute ?? 45));
        $remainingFraction = (90 - $elapsed) / 90;
        $homeHistoryRate = $this->expectedGoalsForUpcomingMatch($homeHistory, $awayHistory);
        $awayHistoryRate = $this->expectedGoalsForUpcomingMatch($awayHistory, $homeHistory);
        $hasHistory = $homeHistoryRate !== null && $awayHistoryRate !== null;

        if ($hasHistory) {
            $homeRemaining = $homeHistoryRate * $remainingFraction;
            $awayRemaining = $awayHistoryRate * $remainingFraction;
            if ($elapsed > 5) {
                $homeLivePaceRemaining = max(
                    0,
                    ($homeStatEstimate - $homeGoals) / $elapsed * (90 - $elapsed),
                );
                $awayLivePaceRemaining = max(
                    0,
                    ($awayStatEstimate - $awayGoals) / $elapsed * (90 - $elapsed),
                );
                $homeRemaining = $homeRemaining * 0.65 + $homeLivePaceRemaining * 0.35;
                $awayRemaining = $awayRemaining * 0.65 + $awayLivePaceRemaining * 0.35;
            }
        } else {
            $homeRemaining = max(0, $homeStatEstimate - $homeGoals);
            $awayRemaining = max(0, $awayStatEstimate - $awayGoals);
        }
        $homeExpectedGoals = $homeGoals + $homeRemaining;
        $awayExpectedGoals = $awayGoals + $awayRemaining;
        $totalExpectedGoals = $homeExpectedGoals + $awayExpectedGoals;
        $homeScores = $homeGoals > 0 ? 1.0 : 1 - exp(-$homeRemaining);
        $awayScores = $awayGoals > 0 ? 1.0 : 1 - exp(-$awayRemaining);

        return [
            'over15' => $this->poissonAtLeast($totalExpectedGoals, 2),
            'over25' => $this->poissonAtLeast($totalExpectedGoals, 3),
            'goalLines' => $this->goalLines(
                $homeRemaining + $awayRemaining,
                $currentGoals,
            ),
            'btts' => (int) round($homeScores * $awayScores * 100),
            'expectedGoals' => round($totalExpectedGoals, 2),
            'available' => true,
            'remainingExpectedGoals' => round($homeRemaining + $awayRemaining, 2),
            'method' => $hasHistory
                ? 'Estimated from team season goal history, current score, match minute and live shots; not a guarantee.'
                : 'Estimated from current score and available live shots; team goal history is unavailable.',
        ];
    }

    private function goalLines(float $expectedGoals, int $currentGoals): array
    {
        $markets = [];
        $lastThreshold = max(5, $currentGoals + 3);
        for ($goalThreshold = 2; $goalThreshold <= $lastThreshold; $goalThreshold++) {
            if ($goalThreshold <= $currentGoals) {
                continue;
            }

            $markets[] = [
                'line' => $goalThreshold - 0.5,
                'probability' => $this->poissonAtLeast(
                    $expectedGoals,
                    $goalThreshold - $currentGoals,
                ),
            ];
        }

        return $markets;
    }

    private function poissonAtLeast(float $lambda, int $threshold): int
    {
        $probabilityBelowThreshold = 0.0;
        $term = exp(-$lambda);
        for ($goals = 0; $goals < $threshold; $goals++) {
            if ($goals > 0) {
                $term *= $lambda / $goals;
            }
            $probabilityBelowThreshold += $term;
        }

        return (int) round(max(0, min(100, (1 - $probabilityBelowThreshold) * 100)));
    }

    private function request(string $endpoint, array $query = [], int $timeoutSeconds = 20): array
    {
        $key = config('services.apifootball.key');
        if (! is_string($key) || trim($key) === '') {
            throw new ApiFootballException('API-Football is not configured.', 503);
        }

        $baseUrl = rtrim((string) config('services.apifootball.base_url'), '/');
        $base = parse_url($baseUrl);
        if (! is_array($base)
            || strtolower((string) ($base['scheme'] ?? '')) !== 'https'
            || strtolower((string) ($base['host'] ?? '')) !== 'v3.football.api-sports.io'
            || isset($base['user'])
            || isset($base['pass'])
            || isset($base['query'])
            || isset($base['fragment'])) {
            Log::error('Invalid API-Football base URL configuration.', [
                'host' => is_array($base) ? ($base['host'] ?? null) : null,
            ]);
            throw new ApiFootballException('API-Football endpoint configuration is invalid.', 500);
        }

        try {
            $response = Http::acceptJson()
                ->withHeaders(['x-apisports-key' => $key])
                ->withOptions(['allow_redirects' => false])
                ->connectTimeout(5)
                ->timeout($timeoutSeconds)
                ->get($baseUrl.$endpoint, $query);
        } catch (ConnectionException $error) {
            Log::error('API-Football connection failed.', [
                'endpoint' => $endpoint,
                'query' => $query,
                'message' => $error->getMessage(),
            ]);
            throw new ApiFootballException(
                'API-Football is temporarily unavailable.',
                503,
                $error,
            );
        }

        if ($response->tooManyRequests()) {
            $this->logProviderFailure($endpoint, $query, $response, 'API-Football rate limit reached.');
            throw new ApiFootballException('API-Football rate limit reached. Please retry later.', 503);
        }
        if (! $response->successful()) {
            $this->logProviderFailure($endpoint, $query, $response, 'API-Football returned an unsuccessful HTTP response.');
            throw new ApiFootballException('API-Football returned an unsuccessful response.', 502);
        }

        $payload = $response->json();
        if (! is_array($payload)) {
            Log::error('API-Football returned invalid JSON.', [
                'endpoint' => $endpoint,
                'query' => $query,
                'status' => $response->status(),
                'response_body' => $this->redactApiKey($response->body(), $key),
            ]);
            throw new ApiFootballException('API-Football returned an invalid response.', 502);
        }

        $errors = $payload['errors'] ?? [];
        if ($errors !== [] && $errors !== null) {
            $this->logProviderFailure($endpoint, $query, $response, 'API-Football rejected the request.');
            throw new ApiFootballException('API-Football rejected the request.', 502);
        }

        return $payload;
    }

    private function logProviderFailure(
        string $endpoint,
        array $query,
        Response $response,
        string $reason,
    ): void {
        $key = config('services.apifootball.key');
        Log::error($reason, [
            'endpoint' => $endpoint,
            'query' => $query,
            'status' => $response->status(),
            'response_body' => $this->redactApiKey(
                $response->body(),
                is_string($key) ? $key : '',
            ),
        ]);
    }

    private function redactApiKey(string $body, string $key): string
    {
        return $key === '' ? $body : str_replace($key, '[REDACTED]', $body);
    }

    private function normalizeFixture(array $item): array
    {
        $fixture = $item['fixture'] ?? [];
        $league = $item['league'] ?? [];
        $teams = $item['teams'] ?? [];
        $goals = $item['goals'] ?? [];
        $home = $teams['home'] ?? [];
        $away = $teams['away'] ?? [];
        $priority = Arr::get(
            $item,
            'priority',
            Arr::get($fixture, 'priority', Arr::get($league, 'priority', 0)),
        );
        $priorityScore = is_numeric($priority)
            ? (int) $priority
            : (strtolower((string) $priority) === 'high' ? 1 : 0);
        $popularFlag = Arr::get(
            $item,
            'is_popular',
            Arr::get(
                $item,
                'isPopular',
                Arr::get(
                    $fixture,
                    'is_popular',
                    Arr::get(
                        $fixture,
                        'isPopular',
                        Arr::get($league, 'is_popular', Arr::get($league, 'isPopular', false)),
                    ),
                ),
            ),
        );

        return [
            'id' => (string) ($fixture['id'] ?? ''),
            'isPopular' => filter_var($popularFlag, FILTER_VALIDATE_BOOLEAN) || $priorityScore > 0,
            'priority' => $priorityScore,
            'league' => [
                'id' => (string) ($league['id'] ?? ''),
                'name' => $league['name'] ?? 'Football',
                'country' => $league['country'] ?? '',
                'logo' => $league['logo'] ?? null,
                'season' => isset($league['season']) ? (int) $league['season'] : null,
            ],
            'status' => Arr::get($fixture, 'status.short', 'NS'),
            'minute' => Arr::get($fixture, 'status.elapsed'),
            'venue' => Arr::get($fixture, 'venue.name'),
            'startsAt' => $fixture['date'] ?? null,
            'referee' => $fixture['referee'] ?? null,
            'hasTimeline' => true,
            'home' => [
                'id' => (string) ($home['id'] ?? ''),
                'name' => $home['name'] ?? 'Home team',
                'logo' => $home['logo'] ?? '',
                'goals' => (int) ($goals['home'] ?? 0),
            ],
            'away' => [
                'id' => (string) ($away['id'] ?? ''),
                'name' => $away['name'] ?? 'Away team',
                'logo' => $away['logo'] ?? '',
                'goals' => (int) ($goals['away'] ?? 0),
            ],
        ];
    }

    private function normalizeEvent(string $fixtureId, array $event): array
    {
        $minute = Arr::get($event, 'time.elapsed', 0);
        $type = $event['type'] ?? 'event';
        $detail = $event['detail'] ?? $type;
        $description = strtolower($type.' '.$detail);
        $isCard = strtolower($type) === 'card';
        $isRedCard = $isCard && (
            str_contains($description, 'red card') ||
            str_contains($description, 'second yellow')
        );
        $team = $event['team'] ?? [];
        $player = $event['player'] ?? [];
        $canonical = implode(':', [
            $fixtureId,
            $event['id'] ?? '',
            $type,
            $player['id'] ?? $player['name'] ?? '',
            $minute,
            Arr::get($event, 'time.extra', ''),
        ]);

        return [
            'fingerprint' => hash('sha256', $canonical),
            'fixtureId' => $fixtureId,
            'providerEventId' => isset($event['id']) ? (string) $event['id'] : null,
            'minute' => (int) $minute,
            'extraMinute' => isset($event['time']['extra']) ? (int) $event['time']['extra'] : null,
            'type' => $isCard ? 'card' : $type,
            'detail' => $detail,
            'teamId' => isset($team['id']) ? (string) $team['id'] : null,
            'teamName' => $team['name'] ?? 'Unknown team',
            'playerId' => isset($player['id']) ? (string) $player['id'] : null,
            'playerName' => $player['name'] ?? 'Unknown player',
            'comments' => $event['comments'] ?? null,
            'isRedCard' => $isRedCard,
        ];
    }

    private function normalizeTeamStatistics(array $team): array
    {
        $statistics = [];
        foreach ($team['statistics'] ?? [] as $statistic) {
            if (is_array($statistic) && isset($statistic['type'])) {
                $statistics[$statistic['type']] = $statistic['value'] ?? null;
            }
        }

        return [
            'name' => Arr::get($team, 'team.name', 'Unknown team'),
            'statistics' => $statistics,
        ];
    }

    private function storeFixture(array $data): void
    {
        DB::transaction(function () use ($data): void {
            $league = League::updateOrCreate(
                ['provider' => 'api-football', 'provider_id' => $data['league']['id']],
                [
                    'name' => $data['league']['name'],
                    'country' => $data['league']['country'],
                    'logo_url' => $data['league']['logo'],
                ],
            );
            $home = $this->storeTeam($data['home']);
            $away = $this->storeTeam($data['away']);

            Fixture::updateOrCreate(
                ['provider' => 'api-football', 'provider_id' => $data['id']],
                [
                    'league_id' => $league->id,
                    'home_team_id' => $home->id,
                    'away_team_id' => $away->id,
                    'status' => $data['status'],
                    'minute' => $data['minute'],
                    'venue' => $data['venue'],
                    'referee' => $data['referee'],
                    'season' => $data['league']['season'],
                    'has_timeline' => $data['hasTimeline'],
                    'home_score' => $data['home']['goals'],
                    'away_score' => $data['away']['goals'],
                    'starts_at' => $data['startsAt'],
                    'last_synced_at' => now(),
                ],
            );
        });
    }

    private function storeTeam(array $team): Team
    {
        $providerId = $team['id'] !== '' ? $team['id'] : 'name:'.Str::slug($team['name']);

        return Team::updateOrCreate(
            ['provider' => 'api-football', 'provider_id' => $providerId],
            ['name' => $team['name'], 'logo_url' => $team['logo'] ?: null],
        );
    }

    private function storeEvent(array $event, ?Fixture $fixture): void
    {
        if (! $fixture) {
            return;
        }

        MatchEvent::updateOrCreate(
            ['fingerprint' => $event['fingerprint']],
            [
                'fixture_id' => $fixture->id,
                'provider_event_id' => $event['providerEventId'] ?? null,
                'type' => $event['type'],
                'detail' => $event['detail'],
                'minute' => $event['minute'],
                'extra_minute' => $event['extraMinute'],
                'team_provider_id' => $event['teamId'],
                'team_name' => $event['teamName'],
                'player_provider_id' => $event['playerId'],
                'player_name' => $event['playerName'],
                'comments' => $event['comments'],
                'is_red_card' => $event['isRedCard'],
                'occurred_at' => null,
            ],
        );
    }

    private function validateFixtureId(string $providerId): void
    {
        if (! ctype_digit($providerId)) {
            throw new RuntimeException('The fixture identifier must be a numeric API-Football ID.');
        }
    }
}
