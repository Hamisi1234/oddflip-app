<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->string('role', 20)->default('user')->index();
            $table->string('subscription_status', 30)->default('free_trial')->index();
            $table->timestamp('trial_ends_at')->nullable()->index();
            $table->timestamp('subscription_ends_at')->nullable()->index();
        });

        DB::table('users')->orderBy('id')->each(function (object $user): void {
            DB::table('users')
                ->where('id', $user->id)
                ->update([
                    'trial_ends_at' => $user->created_at
                        ? date('Y-m-d H:i:s', strtotime($user->created_at.' +7 days'))
                        : now()->addDays(7),
                ]);
        });

        Schema::create('payments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->unsignedInteger('amount');
            $table->char('currency', 3)->default('TZS');
            $table->string('status', 20)->default('pending')->index();
            $table->string('reference', 120)->nullable()->unique();
            $table->string('payment_method', 40)->nullable();
            $table->foreignId('recorded_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('paid_at')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'status', 'paid_at']);
        });

        if (Schema::hasTable('subscriptions')) {
            DB::table('subscriptions')
                ->where('status', 'active')
                ->where('expires_at', '>', now())
                ->orderBy('user_id')
                ->orderByDesc('expires_at')
                ->get()
                ->unique('user_id')
                ->each(function (object $subscription): void {
                    DB::table('users')
                        ->where('id', $subscription->user_id)
                        ->update([
                            'subscription_status' => 'active',
                            'subscription_ends_at' => $subscription->expires_at,
                        ]);
                });

            DB::table('subscriptions')
                ->whereIn('status', ['active', 'expired'])
                ->orderBy('id')
                ->each(function (object $subscription): void {
                    DB::table('payments')->insert([
                        'user_id' => $subscription->user_id,
                        'amount' => $subscription->amount,
                        'currency' => $subscription->currency,
                        'status' => 'paid',
                        'reference' => $subscription->payment_reference,
                        'payment_method' => $subscription->payment_method,
                        'recorded_by' => null,
                        'paid_at' => $subscription->started_at,
                        'created_at' => $subscription->created_at,
                        'updated_at' => $subscription->updated_at,
                    ]);
                });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('payments');

        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn([
                'role',
                'subscription_status',
                'trial_ends_at',
                'subscription_ends_at',
            ]);
        });
    }
};
