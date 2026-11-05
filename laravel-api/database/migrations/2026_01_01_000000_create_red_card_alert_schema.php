<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table): void {
            $table->id();
            $table->string('name');
            $table->string('email')->unique();
            $table->timestamp('email_verified_at')->nullable();
            $table->string('password');
            $table->rememberToken();
            $table->timestamps();
        });

        Schema::create('personal_access_tokens', function (Blueprint $table): void {
            $table->id();
            $table->morphs('tokenable');
            $table->text('name');
            $table->string('token', 64)->unique();
            $table->text('abilities')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable()->index();
            $table->timestamps();
        });

        Schema::create('leagues', function (Blueprint $table): void {
            $table->id();
            $table->string('provider', 30);
            $table->string('provider_id', 120);
            $table->string('name');
            $table->string('country', 120)->nullable();
            $table->text('logo_url')->nullable();
            $table->timestamps();
            $table->unique(['provider', 'provider_id']);
        });

        Schema::create('teams', function (Blueprint $table): void {
            $table->id();
            $table->string('provider', 30);
            $table->string('provider_id', 120);
            $table->string('name');
            $table->string('country', 120)->nullable();
            $table->text('logo_url')->nullable();
            $table->timestamps();
            $table->unique(['provider', 'provider_id']);
        });

        Schema::create('fixtures', function (Blueprint $table): void {
            $table->id();
            $table->string('provider', 30);
            $table->string('provider_id', 160)->unique();
            $table->foreignId('league_id')->constrained()->cascadeOnUpdate()->restrictOnDelete();
            $table->foreignId('home_team_id')->constrained('teams')->cascadeOnUpdate()->restrictOnDelete();
            $table->foreignId('away_team_id')->constrained('teams')->cascadeOnUpdate()->restrictOnDelete();
            $table->string('status', 60)->index();
            $table->unsignedSmallInteger('minute')->nullable();
            $table->string('venue')->nullable();
            $table->boolean('has_timeline')->default(false);
            $table->unsignedSmallInteger('home_score')->default(0);
            $table->unsignedSmallInteger('away_score')->default(0);
            $table->timestamp('starts_at')->nullable()->index();
            $table->timestamp('last_synced_at')->nullable();
            $table->timestamps();
        });

        Schema::create('match_events', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('fixture_id')->constrained()->cascadeOnDelete();
            $table->string('provider_event_id', 160)->nullable();
            $table->char('fingerprint', 64)->unique();
            $table->string('type', 60)->index();
            $table->string('detail');
            $table->unsignedSmallInteger('minute')->default(0);
            $table->unsignedSmallInteger('extra_minute')->nullable();
            $table->string('team_provider_id', 120)->nullable();
            $table->string('team_name')->nullable();
            $table->string('player_provider_id', 120)->nullable();
            $table->string('player_name')->nullable();
            $table->text('comments')->nullable();
            $table->boolean('is_red_card')->default(false)->index();
            $table->timestamp('occurred_at')->nullable()->index();
            $table->timestamps();
        });

        Schema::create('favorite_teams', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('team_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['user_id', 'team_id']);
        });

        Schema::create('favorite_leagues', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('league_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['user_id', 'league_id']);
        });

        Schema::create('favorite_fixtures', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('fixture_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['user_id', 'fixture_id']);
        });

        Schema::create('alert_settings', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->boolean('push_enabled')->default(true);
            $table->boolean('vibration_enabled')->default(true);
            $table->boolean('red_cards_enabled')->default(true);
            $table->boolean('yellow_cards_enabled')->default(true);
            $table->boolean('all_matches')->default(false);
            $table->string('sound', 40)->default('Siren');
            $table->time('silent_from')->nullable();
            $table->time('silent_until')->nullable();
            $table->string('timezone', 64)->default('UTC');
            $table->timestamps();
        });

        Schema::create('device_tokens', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('token', 512)->unique();
            $table->enum('platform', ['android', 'ios', 'web']);
            $table->string('device_name')->nullable();
            $table->string('app_version', 30)->nullable();
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamp('revoked_at')->nullable();
            $table->timestamps();
        });

        Schema::create('alert_deliveries', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('match_event_id')->constrained()->cascadeOnDelete();
            $table->foreignId('device_token_id')->constrained()->cascadeOnDelete();
            $table->enum('status', ['pending', 'sent', 'delivered', 'failed'])->default('pending')->index();
            $table->string('provider_message_id')->nullable();
            $table->text('error_message')->nullable();
            $table->timestamp('sent_at')->nullable();
            $table->timestamp('delivered_at')->nullable();
            $table->timestamps();
            $table->unique(['match_event_id', 'device_token_id']);
        });

        Schema::create('sync_runs', function (Blueprint $table): void {
            $table->id();
            $table->string('provider', 30);
            $table->enum('status', ['running', 'success', 'failed']);
            $table->unsignedInteger('fixtures_count')->default(0);
            $table->unsignedInteger('events_count')->default(0);
            $table->text('error_message')->nullable();
            $table->timestamp('started_at');
            $table->timestamp('finished_at')->nullable();
            $table->timestamps();
        });

        Schema::create('cache', function (Blueprint $table): void {
            $table->string('key')->primary();
            $table->mediumText('value');
            $table->integer('expiration');
        });

        Schema::create('cache_locks', function (Blueprint $table): void {
            $table->string('key')->primary();
            $table->string('owner');
            $table->integer('expiration');
        });

        Schema::create('jobs', function (Blueprint $table): void {
            $table->id();
            $table->string('queue')->index();
            $table->longText('payload');
            $table->unsignedTinyInteger('attempts');
            $table->unsignedInteger('reserved_at')->nullable();
            $table->unsignedInteger('available_at');
            $table->unsignedInteger('created_at');
        });

        Schema::create('job_batches', function (Blueprint $table): void {
            $table->string('id')->primary();
            $table->string('name');
            $table->integer('total_jobs');
            $table->integer('pending_jobs');
            $table->integer('failed_jobs');
            $table->longText('failed_job_ids');
            $table->mediumText('options')->nullable();
            $table->integer('cancelled_at')->nullable();
            $table->integer('created_at');
            $table->integer('finished_at')->nullable();
        });

        Schema::create('failed_jobs', function (Blueprint $table): void {
            $table->id();
            $table->string('uuid')->unique();
            $table->text('connection');
            $table->text('queue');
            $table->longText('payload');
            $table->longText('exception');
            $table->timestamp('failed_at')->useCurrent();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('failed_jobs');
        Schema::dropIfExists('job_batches');
        Schema::dropIfExists('jobs');
        Schema::dropIfExists('cache_locks');
        Schema::dropIfExists('cache');
        Schema::dropIfExists('sync_runs');
        Schema::dropIfExists('alert_deliveries');
        Schema::dropIfExists('device_tokens');
        Schema::dropIfExists('alert_settings');
        Schema::dropIfExists('favorite_fixtures');
        Schema::dropIfExists('favorite_leagues');
        Schema::dropIfExists('favorite_teams');
        Schema::dropIfExists('match_events');
        Schema::dropIfExists('fixtures');
        Schema::dropIfExists('teams');
        Schema::dropIfExists('leagues');
        Schema::dropIfExists('personal_access_tokens');
        Schema::dropIfExists('users');
    }
};
