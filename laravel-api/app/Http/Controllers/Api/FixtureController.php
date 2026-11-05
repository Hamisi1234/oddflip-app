<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Fixture;
use App\Services\ApiFootballException;
use App\Services\ApiFootballService;
use App\Services\OpenAiAnalystService;
use App\Services\OpenAiApiException;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

class FixtureController extends Controller
{
    public function __construct(
        private readonly ApiFootballService $sports,
        private readonly OpenAiAnalystService $analyst,
    ) {}

    public function live(): JsonResponse
    {
        try {
            $fixtures = Cache::remember(
                'fixtures.live',
                60,
                function (): array {
                    $fixtures = $this->sports->liveFixtures();
                    Cache::put('fixtures.live.stale', $fixtures, now()->addMinutes(10));

                    return $fixtures;
                },
            );

            return response()->json([
                'data' => $fixtures,
                'meta' => ['cachedForSeconds' => 60, 'stale' => false],
            ]);
        } catch (ApiFootballException $error) {
            report($error);
            $cachedFixtures = Cache::get('fixtures.live.stale');
            if (is_array($cachedFixtures)) {
                return response()->json([
                    'data' => $cachedFixtures,
                    'meta' => ['cachedForSeconds' => 60, 'stale' => true],
                ]);
            }

            return response()->json([
                'message' => $error->getMessage(),
                'data' => [],
            ], $error->statusCode);
        }
    }

    public function upcoming(Request $request): JsonResponse
    {
        $dateFilter = $request->query('date');
        if (is_string($dateFilter)
            && (trim($dateFilter) === '' || strtolower(trim($dateFilter)) === 'all')) {
            $request->query->remove('date');
        }

        $filters = $request->validate([
            'date' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'time_from' => ['sometimes', 'date_format:H:i'],
            'time_to' => ['sometimes', 'date_format:H:i'],
            'league' => ['sometimes', 'string', 'max:120'],
            'country' => ['sometimes', 'string', 'max:120'],
            'season' => ['sometimes', 'integer', 'between:1900,2100'],
            'timezone' => ['sometimes', 'timezone'],
        ]);
        if (isset($filters['time_from'], $filters['time_to'])
            && $filters['time_from'] > $filters['time_to']) {
            return response()->json([
                'message' => 'The time_from value must be before or equal to time_to.',
                'errors' => ['time_from' => ['Choose a valid time range.']],
            ], 422);
        }

        $timezone = $filters['timezone'] ?? config('app.timezone', 'UTC');
        $today = now($timezone)->startOfDay();
        $rangeEnd = now($timezone)->addDays(3)->endOfDay();
        $filterCacheKey = hash('sha256', json_encode($filters, JSON_THROW_ON_ERROR));

        try {
            $fixtures = Cache::remember(
                'fixtures.upcoming.'.$today->toDateString().'.'.$filterCacheKey,
                300,
                function () use ($filters, $filterCacheKey): array {
                    $fixtures = $this->sports->upcomingFixtures($filters);
                    Cache::put('fixtures.upcoming.stale.'.$filterCacheKey, $fixtures, now()->addHour());

                    return $fixtures;
                },
            );
            $fixtures = $this->filterUpcoming($fixtures, $filters, $today, $rangeEnd);

            return response()->json([
                'data' => $fixtures,
                'meta' => ['cachedForSeconds' => 300, 'stale' => false],
            ]);
        } catch (ApiFootballException $error) {
            report($error);
            $cachedFixtures = Cache::get('fixtures.upcoming.stale.'.$filterCacheKey);
            if (is_array($cachedFixtures)) {
                return response()->json([
                    'data' => $this->filterUpcoming($cachedFixtures, $filters, $today, $rangeEnd),
                    'meta' => ['cachedForSeconds' => 300, 'stale' => true],
                ]);
            }

            return response()->json([
                'message' => $error->getMessage(),
                'data' => [],
            ], $error->statusCode);
        }
    }

    /**
     * @param  array<int, array<string, mixed>>  $fixtures
     * @param  array<string, string>  $filters
     * @return array<int, array<string, mixed>>
     */
    private function filterUpcoming(array $fixtures, array $filters, Carbon $today, Carbon $rangeEnd): array
    {
        return collect($fixtures)
            ->filter(function (array $fixture) use ($filters, $today, $rangeEnd): bool {
                if (empty($fixture['startsAt'])) {
                    return false;
                }

                $startsAt = Carbon::parse($fixture['startsAt'])
                    ->setTimezone($filters['timezone'] ?? config('app.timezone', 'UTC'));
                $league = $fixture['league'] ?? [];
                if (! $startsAt->betweenIncluded($today, $rangeEnd)
                    || $startsAt->isPast()) {
                    return false;
                }

                if (isset($filters['date']) && $startsAt->toDateString() !== $filters['date']) {
                    return false;
                }
                if (isset($filters['season'])
                    && (int) ($league['season'] ?? 0) !== (int) $filters['season']) {
                    return false;
                }

                $kickoffTime = $startsAt->format('H:i');
                if (isset($filters['time_from']) && $kickoffTime < $filters['time_from']) {
                    return false;
                }
                if (isset($filters['time_to']) && $kickoffTime > $filters['time_to']) {
                    return false;
                }
                $leagueFilter = mb_strtolower($filters['league'] ?? '');
                $leagueFilter = mb_strtolower($filters['league'] ?? '');
                if ($leagueFilter !== ''
                    && $leagueFilter !== mb_strtolower((string) ($league['id'] ?? ''))
                    && ! str_contains(mb_strtolower((string) ($league['name'] ?? '')), $leagueFilter)) {
                    return false;
                }

                $countryFilter = mb_strtolower($filters['country'] ?? '');
                if ($countryFilter !== ''
                    && ! str_contains(mb_strtolower((string) ($league['country'] ?? '')), $countryFilter)) {
                    return false;
                }

                return true;
            })
            ->sort(function (array $left, array $right): int {
                $leftPopular = $this->fixturePriority($left);
                $rightPopular = $this->fixturePriority($right);
                if ($leftPopular['popular'] !== $rightPopular['popular']) {
                    return $rightPopular['popular'] <=> $leftPopular['popular'];
                }
                if ($leftPopular['priority'] !== $rightPopular['priority']) {
                    return $rightPopular['priority'] <=> $leftPopular['priority'];
                }

                return Carbon::parse($left['startsAt'])->getTimestamp()
                    <=> Carbon::parse($right['startsAt'])->getTimestamp();
            })
            ->values()
            ->all();
    }

    /**
     * @return array{popular: int, priority: int}
     */
    private function fixturePriority(array $fixture): array
    {
        $priority = data_get($fixture, 'priority', data_get($fixture, 'league.priority', 0));
        $priorityScore = is_numeric($priority)
            ? (int) $priority
            : (strtolower((string) $priority) === 'high' ? 1 : 0);
        $popular = filter_var(
            $fixture['isPopular'] ?? $fixture['is_popular'] ?? false,
            FILTER_VALIDATE_BOOLEAN,
        ) || $priorityScore > 0;

        return ['popular' => (int) $popular, 'priority' => $priorityScore];
    }

    public function events(string $providerId): JsonResponse
    {
        return $this->respond(fn (): JsonResponse => response()->json([
            'data' => Cache::remember(
                "fixtures.events.$providerId",
                60,
                fn (): array => $this->sports->fixtureEvents($providerId),
            ),
        ]), []);
    }

    public function insights(string $providerId): JsonResponse
    {
        return $this->respond(fn (): JsonResponse => response()->json([
            'data' => Cache::remember(
                "fixtures.insights.$providerId",
                60,
                fn (): array => $this->sports->matchInsights($providerId),
            ),
        ]), null);
    }

    public function aiAnalysis(string $providerId): JsonResponse
    {
        try {
            $fixture = Fixture::with('league')
                ->where('provider', 'api-football')
                ->where('provider_id', $providerId)
                ->first();
            $status = strtoupper((string) $fixture?->status);
            $startsAt = $fixture?->starts_at;
            $isLive = in_array($status, ['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'], true)
                && $startsAt?->lte(now());
            $isUpcoming = in_array($status, ['NS', 'TBD'], true)
                && $startsAt?->betweenIncluded(now(), now()->addDays(3)->endOfDay());
            if (! $fixture || (! $isLive && ! $isUpcoming)) {
                return response()->json([
                    'message' => 'AI analysis is available only for live matches or upcoming fixtures within three days.',
                ], 422);
            }

            $insights = $this->sports->matchInsights($providerId);
            $insights['fixture'] = [
                'id' => $fixture->provider_id,
                'status' => $fixture->status,
                'minute' => $fixture->minute,
                'startsAt' => $startsAt?->toIso8601String(),
                'date' => $startsAt?->toDateString(),
                'time' => $startsAt?->format('H:i'),
                'league' => $fixture->league?->name,
                'country' => $fixture->league?->country,
                'homeGoals' => $fixture->home_score,
                'awayGoals' => $fixture->away_score,
            ];
            $user = request()->user();
            $analysisKey = hash('sha256', json_encode([
                'insights' => $insights,
                'userId' => $user?->getAuthIdentifier(),
            ], JSON_THROW_ON_ERROR));
            $analysis = Cache::remember(
                "fixtures.ai-analysis.openai.$providerId.$analysisKey",
                21600,
                fn (): array => $this->analyst->analyze($insights, $user?->name),
            );

            return response()->json(['data' => $analysis]);
        } catch (ApiFootballException $error) {
            report($error);

            return response()->json([
                'message' => $error->getMessage(),
                'data' => null,
            ], $error->statusCode);
        } catch (OpenAiApiException $error) {
            report($error);

            return response()->json([
                'message' => $error->getMessage(),
                'data' => null,
            ], $error->statusCode);
        } catch (\JsonException $error) {
            report($error);

            return response()->json([
                'message' => 'Could not prepare match data for AI analysis.',
                'data' => null,
            ], 500);
        } catch (\Throwable $error) {
            report($error);

            return response()->json([
                'message' => 'AI analysis could not be completed. Please try again later.',
                'data' => null,
            ], 500);
        }
    }

    private function respond(callable $action, mixed $fallback): JsonResponse
    {
        try {
            return $action();
        } catch (ApiFootballException $error) {
            report($error);

            return response()->json([
                'message' => $error->getMessage(),
                'data' => $fallback,
            ], $error->statusCode);
        }
    }
}
