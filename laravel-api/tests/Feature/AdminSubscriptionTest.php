<?php

namespace Tests\Feature;

use App\Models\Payment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AdminSubscriptionTest extends TestCase
{
    use RefreshDatabase;

    public function test_registration_starts_a_seven_day_trial_without_user_selected_role(): void
    {
        $response = $this->postJson('/api/register', [
            'name' => 'Trial User',
            'email' => 'trial@example.test',
            'password' => 'password123',
            'role' => 'admin',
        ])->assertCreated()
            ->assertJsonPath('user.role', 'user')
            ->assertJsonPath('user.subscription_status', 'free_trial');

        $user = User::where('email', 'trial@example.test')->firstOrFail();
        $this->assertSame('user', $user->role);
        $this->assertTrue($user->trial_ends_at->between(
            now()->addDays(6)->subMinute(),
            now()->addDays(7)->addMinute(),
        ));
        $this->assertTrue($user->isPremiumAccessActive());
        $this->assertNotEmpty($response->json('access_token'));
    }

    public function test_admin_dashboard_and_user_management_require_admin_role(): void
    {
        $user = User::create([
            'name' => 'Regular User',
            'email' => 'user@example.test',
            'password' => 'password123',
        ]);
        $userToken = $user->createToken('user-test')->plainTextToken;
        $this->withToken($userToken)
            ->getJson('/api/admin/dashboard')
            ->assertForbidden();

        $admin = User::create([
            'name' => 'Admin User',
            'email' => 'admin@example.test',
            'password' => 'password123',
            'role' => 'admin',
        ]);
        $adminToken = $admin->createToken('admin-test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        $this->withToken($adminToken)
            ->getJson('/api/admin/stats')
            ->assertOk()
            ->assertJsonPath('total_revenue', 0)
            ->assertJsonPath('free_trial_users', 1)
            ->assertJsonPath('active_paid_users', 0);

        $this->app['auth']->forgetGuards();
        $usersResponse = $this->withToken($adminToken)
            ->getJson('/api/admin/users?search=Regular')
            ->assertOk()
            ->assertJsonPath('data.0.email', 'user@example.test');
        $this->assertSame('free_trial', $usersResponse->json('data.0.plan'));
    }

    public function test_admin_activation_records_a_payment_and_disabling_revokes_access(): void
    {
        $admin = User::create([
            'name' => 'Admin User',
            'email' => 'admin@example.test',
            'password' => 'password123',
            'role' => 'admin',
        ]);
        $user = User::create([
            'name' => 'Member',
            'email' => 'member@example.test',
            'password' => 'password123',
        ]);
        $token = $admin->createToken('admin-test')->plainTextToken;

        $this->withToken($token)
            ->postJson("/api/admin/users/$user->id/toggle-status", [
                'status' => 'active_paid',
                'reference' => 'verified-payment-001',
                'payment_method' => 'mobile_money',
            ])
            ->assertOk()
            ->assertJsonPath('user.subscription_status', 'active_paid');

        $this->assertDatabaseHas('payments', [
            'user_id' => $user->id,
            'amount' => 5000,
            'currency' => 'TZS',
            'status' => 'paid',
            'reference' => 'verified-payment-001',
            'recorded_by' => $admin->id,
        ]);
        $this->assertTrue($user->fresh()->isPremiumAccessActive());

        $this->app['auth']->forgetGuards();
        $this->withToken($token)
            ->getJson('/api/admin/dashboard')
            ->assertOk()
            ->assertJsonPath('total_revenue', 5000)
            ->assertJsonPath('active_paid_users', 1);

        $this->app['auth']->forgetGuards();
        $this->withToken($token)
            ->postJson("/api/admin/users/$user->id/toggle-status", [
                'status' => 'disabled',
            ])
            ->assertOk()
            ->assertJsonPath('user.subscription_status', 'disabled');

        $this->assertFalse($user->fresh()->isPremiumAccessActive());
        $this->assertSame(5000, Payment::sum('amount'));
    }

    public function test_ai_analysis_requires_a_current_trial_or_paid_subscription(): void
    {
        $expired = User::create([
            'name' => 'Expired Trial',
            'email' => 'expired@example.test',
            'password' => 'password123',
            'subscription_status' => 'expired',
            'trial_ends_at' => now()->subDay(),
        ]);
        $token = $expired->createToken('expired-test')->plainTextToken;

        $this->withToken($token)
            ->postJson('/api/fixtures/12345/ai-analysis')
            ->assertStatus(402)
            ->assertJsonPath('monthly_price', 5000)
            ->assertJsonPath('currency', 'TZS');
    }
}
