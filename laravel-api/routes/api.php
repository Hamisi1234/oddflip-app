<?php

use App\Http\Controllers\Api\AccountController;
use App\Http\Controllers\Api\AdminController;
use App\Http\Controllers\Api\FixtureController;
use App\Http\Controllers\Api\MkariaChatController;
use App\Http\Controllers\AuthController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/health', fn () => [
    'status' => 'ok',
    'provider' => config('services.apifootball.key') ? 'api-football' : 'unconfigured',
]);

Route::get('/fixtures/live', [FixtureController::class, 'live']);
Route::get('/fixtures/upcoming', [FixtureController::class, 'upcoming']);
Route::post('/fixtures/{providerId}/ai-analysis', [FixtureController::class, 'aiAnalysis'])
    ->where('providerId', '[0-9]+')
    ->middleware(['auth:sanctum', 'premium.subscription', 'throttle:10,1']);
Route::get('/fixtures/{providerId}/events', [FixtureController::class, 'events'])
    ->where('providerId', '.*');
Route::get('/fixtures/{providerId}/insights', [FixtureController::class, 'insights'])
    ->where('providerId', '.*');

// Njia za Usajili na Kuingia (Authentication Routes)
Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/user/profile', [AccountController::class, 'profile']);
    Route::get('/subscription/status', [AccountController::class, 'subscriptionStatus']);
    Route::get('/subscription/payments', [AccountController::class, 'paymentHistory']);
    Route::put('/user/profile', [AccountController::class, 'updateProfile']);
    Route::put('/user/password', [AccountController::class, 'updatePassword']);
    Route::get('/user', function (Request $request) {
        return $request->user();
    });
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::post('/mkaria-chat', MkariaChatController::class)
        ->middleware(['premium.subscription', 'throttle:6,1']);
    Route::get('/mkaria-chats', [MkariaChatController::class, 'conversations'])
        ->middleware('premium.subscription');
    Route::get('/mkaria-chats/{conversationId}', [MkariaChatController::class, 'showConversation'])
        ->whereNumber('conversationId')
        ->middleware('premium.subscription');
});

Route::middleware(['auth:sanctum', 'admin'])->prefix('admin')->group(function () {
    Route::get('/stats', [AdminController::class, 'stats']);
    Route::get('/dashboard', [AdminController::class, 'dashboard']);
    Route::get('/users', [AdminController::class, 'users']);
    Route::get('/users/{user}', [AdminController::class, 'showUser'])
        ->whereNumber('user');
    Route::post('/users/{user}/toggle-status', [AdminController::class, 'toggleStatus'])
        ->whereNumber('user');
    Route::patch('/users/{user}/subscription', [AdminController::class, 'updateSubscription'])
        ->whereNumber('user');
});
