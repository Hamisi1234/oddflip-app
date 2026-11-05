<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rules\Password;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'string', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', Password::min(8)],
        ]);

        $user = User::create([
            ...$validated,
            'role' => 'user',
            'subscription_status' => 'free_trial',
            'trial_ends_at' => now()->addDays(7),
        ]);

        return $this->tokenResponse($user, 201, 'Registration successful.');
    }

    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email'],
            'password' => ['required', 'string'],
        ]);

        $user = User::where('email', $validated['email'])->first();
        if (! $user || ! Hash::check($validated['password'], $user->password)) {
            return response()->json(['message' => 'The provided credentials are incorrect.'], 401);
        }

        return $this->tokenResponse($user, 200, 'Login successful.');
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()?->delete();

        return response()->json([
            'message' => 'Logged out successfully.',
        ]);
    }

    private function tokenResponse(User $user, int $status, string $message): JsonResponse
    {
        $token = $user->createToken('auth_token')->plainTextToken;

        return response()->json([
            'message' => $message,
            'access_token' => $token,
            'token_type' => 'Bearer',
            'user' => $user->only([
                'id',
                'name',
                'email',
                'role',
                'subscription_status',
                'trial_ends_at',
                'subscription_ends_at',
            ]),
        ], $status);
    }
}
