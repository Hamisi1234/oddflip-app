<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class AccountController extends Controller
{
    public function profile(Request $request): JsonResponse
    {
        $user = $request->user();
        $subscription = in_array($user->subscription_status, ['active_paid', 'active'], true)
            ? $user->subscriptions()
                ->where('status', 'active')
                ->where('expires_at', '>', now())
                ->latest('expires_at')
                ->first()
            : null;
        $deviceToken = DB::table('device_tokens')
            ->where('user_id', $user->id)
            ->whereNull('revoked_at')
            ->orderByDesc('last_seen_at')
            ->value('token');

        return response()->json([
            'user' => $user->only([
                'id',
                'name',
                'email',
                'role',
                'subscription_status',
                'trial_ends_at',
                'subscription_ends_at',
            ]),
            'device_token' => $deviceToken,
            'subscription' => $subscription?->only([
                'id', 'plan', 'amount', 'currency', 'payment_method', 'status',
                'started_at', 'expires_at',
            ]),
            'is_pro' => in_array($user->subscription_status, ['active_paid', 'active'], true)
                && $subscription !== null,
        ]);
    }

    public function subscriptionStatus(Request $request): JsonResponse
    {
        $user = $request->user();
        $hasAccess = $user->isPremiumAccessActive();
        if (! $hasAccess && ! in_array($user->subscription_status, ['disabled', 'disabled_by_admin'], true)) {
            $user->forceFill(['subscription_status' => 'expired'])->save();
        }

        return response()->json([
            'status' => $user->subscription_status,
            'role' => $user->role,
            'trial_ends_at' => $user->trial_ends_at,
            'subscription_ends_at' => $user->subscription_ends_at,
            'has_premium_access' => $hasAccess,
            'monthly_price' => 5000,
            'currency' => 'TZS',
        ]);
    }

    public function paymentHistory(Request $request): JsonResponse
    {
        return response()->json([
            'data' => $request->user()->payments()
                ->latest()
                ->paginate(20),
        ]);
    }

    public function updateProfile(Request $request): JsonResponse
    {
        $user = $request->user();
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => [
                'required',
                'string',
                'email',
                'max:255',
                Rule::unique('users', 'email')->ignore($user->id),
            ],
        ]);
        $user->fill($validated)->save();

        return response()->json(['user' => $user->only([
            'id',
            'name',
            'email',
            'role',
            'subscription_status',
            'trial_ends_at',
            'subscription_ends_at',
        ])]);
    }

    public function updatePassword(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'current_password' => ['required', 'current_password:sanctum'],
            'password' => ['required', 'confirmed', Password::min(8)],
        ]);
        $request->user()->update(['password' => Hash::make($validated['password'])]);

        return response()->json(['message' => 'Password updated.']);
    }
}
