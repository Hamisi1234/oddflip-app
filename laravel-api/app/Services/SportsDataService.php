<?php

namespace App\Services;

use App\Models\Fixture;
use App\Models\League;
use App\Models\MatchEvent;
use App\Models\Team;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Throwable;

class SportsDataService
{
    public function liveFixtures(): array
    {
        return Cache::remember('sports.live-fixtures', 10, function (): array {
            $fixtures = [];
            if (config('services.sportradar.key')) {
                try {
                    $fixtures = $this->sportradarLiveFixtures();
                } catch (Throwable $error) {
                    report($error);
                }
            }

            if ($fixtures === []) {
                $fixtures = $this->publicLiveFixtures();
            }

            foreach ($fixtures as $fixture) {
                $this->storeFixture($fixture);
            }

            return $fixtures;
        });
    }

    public function fixtureEvents(string $providerId): array
    {
        if (str_starts_with($providerId, 'tsdb:')) {
            return [];
        }

        return Cache::remember("sports.events.$providerId", 5, function () use ($providerId): array {
            $response = Http::acceptJson()
                ->timeout(10)
                ->get(
                    rtrim(config('services.sportradar.base_url'), '/').'/sport_events/'.rawurlencode($providerId).'/timeline.json',
                    ['api_key' => config('services.sportradar.key')],
                )
                ->throw()
                ->json();

            $fixture = Fixture::with(['homeTeam', 'awayTeam'])
                ->where('provider_id', $providerId)
                ->first();

            return collect($response['timeline'] ?? [])
                ->map(fn (array $event): array => $this->normalizeEvent($providerId, $event, $fixture))
                ->tap(fn ($events) => $events->each(fn (array $event) => $this->storeEvent($event, $fixture)))
                ->values()
                ->all();
        });
    }

    private function sportradarLiveFixtures(): array
    {
        $response = Http::acceptJson()
            ->timeout(10)
            ->get(
                rtrim(config('services.sportradar.base_url'), '/').'/schedules/live/summaries.json',
                ['api_key' => config('services.sportradar.key')],
            )
            ->throw()
            ->json();

        return collect($response['summaries'] ?? [])
            ->filter(fn (array $summary): bool => Arr::get($summary, 'sport_event_status.status') === 'live')
            ->map(fn (array $summary): array => $this->normalizeSportradarFixture($summary))
            ->values()
            ->all();
    }

    private function publicLiveFixtures(): array
    {
        $response = Http::acceptJson()
            ->timeout(10)
            ->get(config('services.football_fallback_url'))
            ->throw()
            ->json();

        return collect($response['livescore'] ?? [])
            ->map(fn (array $score): array => [
                'id' => 'tsdb:'.($score['idEvent'] ?? $score['idLiveScore'] ?? Str::uuid()),
                'league' => [
                    'id' => (string) ($score['idLeague'] ?? ''),
                    'name' => $score['strLeague'] ?? 'Football',
                    'country' => '',
                ],
                'status' => $score['strStatus'] ?? 'live',
                'minute' => is_numeric($score['strProgress'] ?? null) ? (int) $score['strProgress'] : null,
                'venue' => null,
                'hasTimeline' => false,
                'home' => [
                    'id' => (string) ($score['idHomeTeam'] ?? ''),
                    'name' => $score['strHomeTeam'] ?? 'Home team',
                    'logo' => $score['strHomeTeamBadge'] ?? '',
                    'goals' => (int) ($score['intHomeScore'] ?? 0),
                ],
                'away' => [
                    'id' => (string) ($score['idAwayTeam'] ?? ''),
                    'name' => $score['strAwayTeam'] ?? 'Away team',
                    'logo' => $score['strAwayTeamBadge'] ?? '',
                    'goals' => (int) ($score['intAwayScore'] ?? 0),
                ],
            ])
            ->values()
            ->all();
    }

    private function normalizeSportradarFixture(array $summary): array
    {
        $event = $summary['sport_event'];
        $status = $summary['sport_event_status'];
        $competitors = collect($event['competitors'] ?? []);
        $home = $competitors->firstWhere('qualifier', 'home') ?? $competitors->first() ?? [];
        $away = $competitors->firstWhere('qualifier', 'away') ?? $competitors->skip(1)->first() ?? [];
        $clock = Arr::get($status, 'clock.played', Arr::get($status, 'clock.match_time'));
        $coverage = Arr::get($event, 'coverage.sport_event_properties', []);

        return [
            'id' => $event['id'],
            'league' => [
                'id' => (string) Arr::get($event, 'sport_event_context.competition.id', ''),
                'name' => Arr::get($event, 'sport_event_context.competition.name', 'Football'),
                'country' => Arr::get($event, 'sport_event_context.category.name', ''),
            ],
            'status' => $status['match_status'] ?? $status['status'] ?? 'live',
            'minute' => $clock ? (int) explode(':', $clock)[0] : null,
            'venue' => Arr::get($event, 'venue.name'),
            'hasTimeline' => (bool) (
                ($coverage['basic_play_by_play'] ?? false) ||
                ($coverage['deeper_play_by_play'] ?? false) ||
                ($coverage['extended_play_by_play'] ?? false)
            ),
            'home' => [
                'id' => (string) ($home['id'] ?? ''),
                'name' => $home['name'] ?? 'Home team',
                'logo' => '',
                'goals' => (int) ($status['home_score'] ?? 0),
            ],
            'away' => [
                'id' => (string) ($away['id'] ?? ''),
                'name' => $away['name'] ?? 'Away team',
                'logo' => '',
                'goals' => (int) ($status['away_score'] ?? 0),
            ],
        ];
    }

    private function normalizeEvent(string $fixtureId, array $event, ?Fixture $fixture): array
    {
        $type = strtolower($event['type'] ?? 'event');
        $detail = $event['card_description'] ?? $event['description'] ?? $event['type'] ?? 'Event';
        $isCard = str_contains($type, 'card');
        $isRed = in_array($type, ['red_card', 'yellow_red_card'], true) ||
            str_contains(strtolower($detail), 'red');
        $canonical = implode(':', [
            $fixtureId,
            $event['id'] ?? '',
            $type,
            Arr::get($event, 'player.id', Arr::get($event, 'player.name', '')),
            $event['match_time'] ?? $event['time'] ?? '',
        ]);

        return [
            'fingerprint' => hash('sha256', $canonical),
            'fixtureId' => $fixtureId,
            'minute' => (int) ($event['match_time'] ?? 0),
            'extraMinute' => isset($event['stoppage_time']) ? (int) $event['stoppage_time'] : null,
            'type' => $isCard ? 'card' : ($event['type'] ?? 'event'),
            'detail' => $detail,
            'teamId' => (string) Arr::get($event, 'competitor.id', ''),
            'teamName' => Arr::get($event, 'competitor.name', 'Unknown team'),
            'playerId' => Arr::get($event, 'player.id'),
            'playerName' => Arr::get($event, 'player.name', 'Unknown player'),
            'comments' => $event['description'] ?? null,
            'isRedCard' => $isRed,
        ];
    }

    private function storeFixture(array $data): void
    {
        DB::transaction(function () use ($data): void {
            $league = League::updateOrCreate(
                ['provider' => str_starts_with($data['id'], 'tsdb:') ? 'thesportsdb' : 'sportradar', 'provider_id' => $data['league']['id']],
                ['name' => $data['league']['name'], 'country' => $data['league']['country']],
            );
            $home = $this->storeTeam($data['home']);
            $away = $this->storeTeam($data['away']);

            Fixture::updateOrCreate(
                ['provider_id' => $data['id']],
                [
                    'provider' => str_starts_with($data['id'], 'tsdb:') ? 'thesportsdb' : 'sportradar',
                    'league_id' => $league->id,
                    'home_team_id' => $home->id,
                    'away_team_id' => $away->id,
                    'status' => $data['status'],
                    'minute' => $data['minute'],
                    'venue' => $data['venue'],
                    'has_timeline' => $data['hasTimeline'],
                    'home_score' => $data['home']['goals'],
                    'away_score' => $data['away']['goals'],
                    'last_synced_at' => now(),
                ],
            );
        });
    }

    private function storeTeam(array $team): Team
    {
        $providerId = $team['id'] !== ''
            ? $team['id']
            : 'name:'.Str::slug($team['name']);

        return Team::updateOrCreate(
            ['provider' => 'sports-feed', 'provider_id' => $providerId],
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
                'provider_event_id' => null,
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
                'occurred_at' => now(),
            ],
        );
    }
}
