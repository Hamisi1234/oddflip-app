<?php

use App\Models\User;
use App\Services\ApiFootballService;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Schedule::call(fn () => app(ApiFootballService::class)->syncLiveData())
    ->everyFiveMinutes()
    ->name('sync-api-football-live-data')
    ->withoutOverlapping();

Artisan::command('app:promote-admin {email}', function (string $email): int {
    $user = User::where('email', $email)->first();
    if (! $user) {
        $this->error('No registered user exists with that email.');

        return self::FAILURE;
    }

    $user->forceFill(['role' => 'admin'])->save();
    $this->info("Admin role granted to {$user->email}.");

    return self::SUCCESS;
})->purpose('Grant administrator access to an existing account');
