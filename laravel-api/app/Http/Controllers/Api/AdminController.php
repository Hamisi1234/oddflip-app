<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Payment;
use App\Models\Subscription;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class AdminController extends Controller
{
    private const MONTHLY_PRICE = 5000;

    public function dashboard(): JsonResponse
    {
        $activePaidUsers = User::query()
            ->whereIn('subscription_status', ['active_paid', 'active'])
            ->where('subscription_ends_at', '>', now())
            ->count();

        return response()->json([
            'currency' => 'TZS',
            'monthly_price' => self::MONTHLY_PRICE,
            'total_revenue' => $activePaidUsers * self::MONTHLY_PRICE,
            'free_trial_users' => User::query()
                ->where('role', 'user')
                ->where('subscription_status', 'free_trial')
                ->count(),
            'active_paid_users' => $activePaidUsers,
            'expired_users' => User::query()
                ->where('subscription_status', 'expired')
                ->count(),
            'disabled_users' => User::query()
                ->whereIn('subscription_status', ['disabled', 'disabled_by_admin'])
                ->count(),
            'registered_users' => User::query()->count(),
        ]);
    }

    public function stats(): JsonResponse
    {
        $stats = $this->dashboard()->getData(true);

        return response()->json([
            'total_revenue' => $stats['total_revenue'],
            'currency' => $stats['currency'],
            'free_trial_users' => $stats['free_trial_users'],
            'active_paid_users' => $stats['active_paid_users'],
        ]);
    }

    public function users(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'search' => ['sometimes', 'nullable', 'string', 'max:100'],
            'status' => [
                'sometimes',
                'nullable',
                Rule::in([
                    'free_trial',
                    'active_paid',
                    'expired',
                    'disabled',
                    'active',
                    'disabled_by_admin',
                ]),
            ],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:100'],
        ]);

        $users = User::query()
            ->select([
                'id',
                'name',
                'email',
                'role',
                'subscription_status',
                'trial_ends_at',
                'subscription_ends_at',
                'created_at',
            ])
            ->addSelect(DB::raw(
                "CASE WHEN subscription_status IN ('active_paid', 'active') THEN 'monthly' ELSE 'free_trial' END AS plan",
            ))
            ->when(
                $validated['search'] ?? null,
                fn ($query, string $search) => $query->where(
                    fn ($query) => $query->where('name', 'like', "%$search%")
                        ->orWhere('email', 'like', "%$search%"),
                ),
            )
            ->when(
                $validated['status'] ?? null,
                fn ($query, string $status) => $query->where('subscription_status', $status),
            )
            ->orderByDesc('created_at')
            ->paginate($validated['per_page'] ?? 25);

        return response()->json($users);
    }

    public function showUser(User $user): JsonResponse
    {
        return response()->json([
            'user' => $user->only([
                'id',
                'name',
                'email',
                'role',
                'subscription_status',
                'trial_ends_at',
                'subscription_ends_at',
                'created_at',
            ]),
            'payments' => $user->payments()
                ->with('recordedBy:id,name,email')
                ->latest()
                ->get(),
            'subscriptions' => $user->subscriptions()
                ->latest('started_at')
                ->get(),
        ]);
    }

    public function updateSubscription(Request $request, User $user): JsonResponse
    {
        if ($user->role === 'admin') {
            return response()->json([
                'message' => 'Admin subscriptions cannot be changed through this endpoint.',
            ], 422);
        }

        $validated = $request->validate([
            'action' => ['required', Rule::in(['activate', 'disable'])],
            'reference' => [
                Rule::requiredIf($request->input('action') === 'activate'),
                'nullable',
                'string',
                'max:120',
                'unique:payments,reference',
            ],
            'payment_method' => ['sometimes', 'nullable', 'string', 'max:40'],
        ]);

        $user = DB::transaction(function () use ($request, $user, $validated): User {
            if ($validated['action'] === 'disable') {
                $user->forceFill([
                    'subscription_status' => 'disabled',
                ])->save();

                return $user->refresh();
            }

            $startedAt = now();
            $currentEnd = $user->subscription_ends_at;
            $startedAt = $currentEnd?->isFuture() ? $currentEnd : $startedAt;
            $expiresAt = $startedAt->copy()->addMonth();

            Payment::create([
                'user_id' => $user->id,
                'amount' => self::MONTHLY_PRICE,
                'currency' => 'TZS',
                'status' => 'paid',
                'reference' => $validated['reference'],
                'payment_method' => $validated['payment_method'] ?? 'manual_admin',
                'recorded_by' => $request->user()->id,
                'paid_at' => now(),
            ]);

            Subscription::create([
                'user_id' => $user->id,
                'plan' => 'monthly',
                'amount' => self::MONTHLY_PRICE,
                'currency' => 'TZS',
                'payment_method' => $validated['payment_method'] ?? 'manual_admin',
                'payment_reference' => $validated['reference'],
                'status' => 'active',
                'started_at' => $startedAt,
                'expires_at' => $expiresAt,
            ]);

            $user->forceFill([
                'subscription_status' => 'active_paid',
                'subscription_ends_at' => $expiresAt,
            ])->save();

            return $user->refresh();
        });

        return response()->json([
            'message' => $validated['action'] === 'activate'
                ? 'Subscription activated. Confirm the payment was received before using this action.'
                : 'Subscription disabled.',
            'user' => $user->only([
                'id',
                'name',
                'email',
                'role',
                'subscription_status',
                'trial_ends_at',
                'subscription_ends_at',
            ]),
        ]);
    }

    public function toggleStatus(Request $request, User $user): JsonResponse
    {
        $validated = $request->validate([
            'status' => ['required', Rule::in(['active_paid', 'disabled'])],
            'reference' => [
                Rule::requiredIf($request->input('status') === 'active_paid'),
                'nullable',
                'string',
                'max:120',
                'unique:payments,reference',
            ],
            'payment_method' => ['sometimes', 'nullable', 'string', 'max:40'],
        ]);

        $request->merge([
            'action' => $validated['status'] === 'active_paid' ? 'activate' : 'disable',
        ]);

        return $this->updateSubscription($request, $user);
    }
}
