<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MkariaChatConversation;
use App\Models\MkariaChatMessage;
use App\Services\ApiFootballException;
use App\Services\ApiFootballService;
use App\Services\MkariaChatService;
use App\Services\OpenAiApiException;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

class MkariaChatController extends Controller
{
    public function __construct(
        private readonly ApiFootballService $sports,
        private readonly MkariaChatService $chat,
    ) {}

    public function __invoke(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'message' => ['required', 'string', 'min:1', 'max:1500'],
            'fixture_id' => ['sometimes', 'nullable', 'regex:/^[0-9]{1,20}$/'],
            'conversation_id' => ['sometimes', 'nullable', 'integer', 'min:1'],
            'filters' => ['sometimes', 'array'],
            'filters.date' => ['sometimes', 'date_format:Y-m-d'],
            'filters.time_from' => ['sometimes', 'date_format:H:i'],
            'filters.time_to' => ['sometimes', 'date_format:H:i'],
            'filters.league' => ['sometimes', 'string', 'max:120'],
            'filters.country' => ['sometimes', 'string', 'max:120'],
            'history' => ['sometimes', 'array', 'max:10'],
            'history.*.role' => ['required', 'in:user,assistant'],
            'history.*.content' => ['required', 'string', 'min:1', 'max:1200'],
        ]);
        if (isset($validated['filters']['time_from'], $validated['filters']['time_to'])
            && $validated['filters']['time_from'] > $validated['filters']['time_to']) {
            return response()->json([
                'message' => 'The time_from value must be before or equal to time_to.',
                'errors' => ['filters' => ['time_from' => ['Choose a valid time range.']]],
            ], 422);
        }

        try {
            $conversation = null;
            $history = $validated['history'] ?? [];
            $previouslySuggestedPicks = [];
            if (! empty($validated['conversation_id'])) {
                $conversation = $request->user()
                    ->mkariaChatConversations()
                    ->findOrFail($validated['conversation_id']);
                $storedMessages = $conversation->messages()
                    ->latest('id')
                    ->limit(20)
                    ->get()
                    ->reverse()
                    ->values();
                $history = $storedMessages
                    ->whereIn('role', ['user', 'assistant'])
                    ->take(-10)
                    ->map(fn (MkariaChatMessage $message): array => [
                        'role' => $message->role,
                        'content' => $message->content,
                    ])
                    ->values()
                    ->all();
                $previouslySuggestedPicks = $storedMessages
                    ->where('role', 'assistant')
                    ->flatMap(fn (MkariaChatMessage $message): array => $message->betslip['picks'] ?? [])
                    ->filter(fn ($pick): bool => is_array($pick) && is_string($pick['match'] ?? null))
                    ->map(fn (array $pick): array => [
                        'match' => $pick['match'],
                        'market' => $pick['market'] ?? null,
                    ])
                    ->unique(fn (array $pick): string => mb_strtolower($pick['match'].'|'.(string) $pick['market']))
                    ->values()
                    ->all();
            }
            $initialHistory = $conversation === null ? ($validated['history'] ?? []) : [];

            $fixtureId = $conversation?->fixture_id ?? ($validated['fixture_id'] ?? null);
            $message = trim($validated['message']);
            $betslipRequested = $this->requestsBetslip($message);
            $upcomingAnalysisRequested = $betslipRequested || $this->requestsUpcomingAnalysis($message);
            $context = $this->matchContext(
                $fixtureId,
                $validated['filters'] ?? [],
                $betslipRequested,
                $upcomingAnalysisRequested,
            );
            if ($betslipRequested && $previouslySuggestedPicks !== []) {
                $context['previouslySuggestedPicks'] = $previouslySuggestedPicks;
            }
            $result = $this->chat->reply(
                $message,
                $history,
                $context,
                $request->user()?->name,
            );

            $conversation = DB::transaction(function () use (
                $request,
                $conversation,
                $validated,
                $result,
                $fixtureId,
                $initialHistory,
            ): MkariaChatConversation {
                $message = trim($validated['message']);
                $isNewConversation = $conversation === null;
                $conversation ??= $request->user()->mkariaChatConversations()->create([
                    'title' => mb_substr($message, 0, 120),
                    'fixture_id' => $fixtureId,
                ]);
                if ($isNewConversation) {
                    foreach ($initialHistory as $turn) {
                        $conversation->messages()->create([
                            'role' => $turn['role'],
                            'content' => trim($turn['content']),
                        ]);
                    }
                }
                $conversation->messages()->create([
                    'role' => 'user',
                    'content' => $message,
                ]);
                $conversation->messages()->create([
                    'role' => 'assistant',
                    'content' => $result['reply'],
                    'betslip' => $result['betslip'],
                ]);
                $conversation->touch();

                return $conversation;
            });

            return response()->json([
                'data' => [...$result, 'conversation_id' => $conversation->id],
            ]);
        } catch (OpenAiApiException $error) {
            report($error);

            return response()->json(['message' => $error->getMessage()], $error->statusCode);
        }
    }

    public function conversations(Request $request): JsonResponse
    {
        $conversations = $request->user()
            ->mkariaChatConversations()
            ->with(['messages' => fn ($query) => $query->latest('id')->limit(1)])
            ->orderByDesc('updated_at')
            ->limit(100)
            ->get()
            ->map(fn (MkariaChatConversation $conversation): array => [
                'id' => $conversation->id,
                'title' => $conversation->title,
                'last_message' => $conversation->messages->first()?->content,
                'updated_at' => $conversation->updated_at?->toIso8601String(),
            ]);

        return response()->json(['data' => $conversations]);
    }

    public function showConversation(Request $request, int $conversationId): JsonResponse
    {
        $conversation = $request->user()
            ->mkariaChatConversations()
            ->with('messages')
            ->findOrFail($conversationId);

        return response()->json([
            'data' => [
                'id' => $conversation->id,
                'title' => $conversation->title,
                'messages' => $conversation->messages->map(fn (MkariaChatMessage $message): array => [
                    'role' => $message->role,
                    'content' => $message->content,
                    'betslip' => $message->betslip,
                    'created_at' => $message->created_at?->toIso8601String(),
                ]),
            ],
        ]);
    }

    private function matchContext(
        ?string $fixtureId,
        array $filters = [],
        bool $betslipRequested = false,
        bool $upcomingAnalysisRequested = false,
    ): array {
        $now = now();
        $upcomingDates = array_values(array_unique([
            $now->toDateString(),
            $now->copy()->addHours(6)->toDateString(),
        ]));
        $fetchUpcoming = function () use ($upcomingDates): array {
            $fixtures = [];
            foreach ($upcomingDates as $date) {
                $fixtures = array_merge(
                    $fixtures,
                    $this->sports->upcomingFixtures(['date' => $date]),
                );
            }

            return collect($fixtures)->unique('id')->values()->all();
        };
        $context = [
            'requestedFilters' => $filters,
            'betslipRequested' => $betslipRequested,
            'liveMatches' => $betslipRequested
                ? []
                : $this->fixtures('live', fn () => $this->sports->liveFixtures(), $filters),
            'upcomingMatches' => $this->fixtures('upcoming', $fetchUpcoming, $filters),
        ];

        if ($upcomingAnalysisRequested) {
            $candidates = collect($context['upcomingMatches']);
            if ($fixtureId !== null) {
                $candidates = $candidates->sortBy(
                    fn (array $fixture): int => (string) ($fixture['id'] ?? '') === $fixtureId ? 0 : 1,
                );
            }

            $context['upcomingMatchAnalysis'] = $candidates
                ->take(5)
                ->map(function (array $fixture): array {
                    try {
                        $insights = Cache::remember(
                            "fixtures.insights.{$fixture['id']}",
                            21600,
                            fn (): array => $this->sports->matchInsights((string) $fixture['id']),
                        );
                    } catch (ApiFootballException $error) {
                        report($error);
                        $insights = [
                            'fixtureId' => $fixture['id'],
                            'analysis' => ['available' => false],
                        ];
                    }

                    return [
                        'fixtureId' => $fixture['id'],
                        'match' => ($fixture['home']['name'] ?? 'Home')
                            .' v '.($fixture['away']['name'] ?? 'Away'),
                        'kickoff' => $fixture['startsAt'] ?? null,
                        'league' => $fixture['league'] ?? null,
                        'country' => $fixture['country'] ?? null,
                        'insights' => $insights,
                    ];
                })
                ->values()
                ->all();
        }

        if ($fixtureId !== null) {
            $eligibleMatches = array_merge($context['liveMatches'], $context['upcomingMatches']);
            $selectedMatch = collect($eligibleMatches)->first(
                fn (array $fixture): bool => (string) $fixture['id'] === $fixtureId,
            );
            if ($selectedMatch === null) {
                $context['selectedMatch'] = [
                    'fixtureId' => $fixtureId,
                    'available' => false,
                    'reason' => 'The fixture is not live or starting within the next six hours.',
                ];
            } else {
                $context['selectedMatch'] = $selectedMatch;
                try {
                    $context['selectedMatchInsights'] = Cache::remember(
                        "fixtures.insights.$fixtureId",
                        60,
                        fn (): array => $this->sports->matchInsights($fixtureId),
                    );
                } catch (ApiFootballException $error) {
                    report($error);
                    $context['selectedMatchInsights'] = [
                        'fixtureId' => $fixtureId,
                        'available' => false,
                    ];
                }
            }
        }

        return $context;
    }

    private function requestsBetslip(string $message): bool
    {
        return preg_match('/\b(?:bet(?:ting)?\s*slip|betlip|mkeka)\b/iu', $message) === 1;
    }

    private function requestsUpcomingAnalysis(string $message): bool
    {
        return preg_match(
            '/\b(?:upcoming|future|siku za usoni|mechi zijazo|mechi ijayo|mechi za kesho|michezo ya baadaye)\b/iu',
            $message,
        ) === 1;
    }

    private function fixtures(string $type, callable $fetch, array $filters): array
    {
        try {
            $cacheKey = $type === 'live'
                ? 'fixtures.mkaria.live'
                : 'fixtures.mkaria.upcoming.'.now()->toDateString();
            $fixtures = Cache::remember(
                $cacheKey,
                $type === 'live' ? 60 : 300,
                $fetch,
            );

            $now = now();
            $rangeEnd = $now->copy()->addHours(6);

            return collect($fixtures)
                ->filter(function (array $fixture) use ($type, $filters, $now, $rangeEnd): bool {
                    $status = strtoupper((string) ($fixture['status'] ?? ''));
                    $isLive = in_array($status, ['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'], true);
                    if ($type === 'live' && ! $isLive) {
                        return false;
                    }
                    if ($type === 'upcoming' && ! in_array($status, ['NS', 'TBD'], true)) {
                        return false;
                    }

                    if (empty($fixture['startsAt'])) {
                        return false;
                    }
                    $startsAt = Carbon::parse($fixture['startsAt'])
                        ->setTimezone($now->getTimezone());
                    if ($type === 'live') {
                        if ($startsAt->gt($now)) {
                            return false;
                        }
                    } elseif (! $startsAt->greaterThan($now) || $startsAt->greaterThan($rangeEnd)) {
                        return false;
                    }

                    $league = $fixture['league'] ?? [];
                    $leagueFilter = mb_strtolower($filters['league'] ?? '');
                    if ($leagueFilter !== ''
                        && $leagueFilter !== mb_strtolower((string) ($league['id'] ?? ''))
                        && $leagueFilter !== mb_strtolower((string) ($league['name'] ?? ''))) {
                        return false;
                    }
                    $countryFilter = mb_strtolower($filters['country'] ?? '');
                    if ($countryFilter !== ''
                        && $countryFilter !== mb_strtolower((string) ($league['country'] ?? ''))) {
                        return false;
                    }
                    if (isset($filters['date']) && $startsAt->toDateString() !== $filters['date']) {
                        return false;
                    }
                    $kickoffTime = $startsAt->format('H:i');
                    if (isset($filters['time_from']) && $kickoffTime < $filters['time_from']) {
                        return false;
                    }
                    if (isset($filters['time_to']) && $kickoffTime > $filters['time_to']) {
                        return false;
                    }

                    return true;
                })
                ->sort(function (array $left, array $right): int {
                    $leftPopular = ! empty($left['isPopular']) || ! empty($left['is_popular'])
                        || (int) ($left['priority'] ?? 0) > 0;
                    $rightPopular = ! empty($right['isPopular']) || ! empty($right['is_popular'])
                        || (int) ($right['priority'] ?? 0) > 0;
                    if ($leftPopular !== $rightPopular) {
                        return (int) $rightPopular <=> (int) $leftPopular;
                    }

                    return strtotime((string) $left['startsAt']) <=> strtotime((string) $right['startsAt']);
                })
                ->take(30)
                ->map(function (array $fixture): array {
                    $startsAt = Carbon::parse($fixture['startsAt'])
                        ->setTimezone(config('app.timezone', 'UTC'));

                    return [
                        'id' => $fixture['id'] ?? null,
                        'league' => $fixture['league']['name'] ?? null,
                        'leagueId' => $fixture['league']['id'] ?? null,
                        'country' => $fixture['league']['country'] ?? null,
                        'status' => $fixture['status'] ?? null,
                        'minute' => $fixture['minute'] ?? null,
                        'startsAt' => $startsAt->toIso8601String(),
                        'date' => $startsAt->toDateString(),
                        'time' => $startsAt->format('H:i'),
                        'isPopular' => $fixture['isPopular'] ?? $fixture['is_popular'] ?? false,
                        'priority' => $fixture['priority'] ?? 0,
                        'home' => [
                            'name' => $fixture['home']['name'] ?? null,
                            'goals' => $fixture['home']['goals'] ?? null,
                        ],
                        'away' => [
                            'name' => $fixture['away']['name'] ?? null,
                            'goals' => $fixture['away']['goals'] ?? null,
                        ],
                    ];
                })
                ->values()
                ->all();
        } catch (ApiFootballException $error) {
            report($error);

            return [];
        }
    }
}
