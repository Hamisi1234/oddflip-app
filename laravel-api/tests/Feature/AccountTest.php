<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class AccountTest extends TestCase
{
    use RefreshDatabase;

    public function test_register_persists_user_and_profile_is_token_protected(): void
    {
        $response = $this->postJson('/api/register', [
            'name' => 'Amina Player',
            'email' => 'amina@example.test',
            'password' => 'password123',
        ])->assertCreated();

        $this->assertDatabaseHas('users', [
            'name' => 'Amina Player',
            'email' => 'amina@example.test',
        ]);
        $this->assertDatabaseMissing('users', [
            'email' => 'amina@example.test',
            'password' => 'password123',
        ]);

        $token = $response->json('access_token');
        $this->withToken($token)
            ->getJson('/api/user/profile')
            ->assertOk()
            ->assertJsonPath('user.name', 'Amina Player')
            ->assertJsonPath('user.email', 'amina@example.test')
            ->assertJsonPath('subscription', null)
            ->assertJsonPath('is_pro', false);
    }

    public function test_profile_uses_the_users_active_subscription(): void
    {
        $user = User::create([
            'name' => 'Pro Member',
            'email' => 'pro@example.test',
            'password' => Hash::make('password123'),
            'subscription_status' => 'active_paid',
            'subscription_ends_at' => now()->addMonth(),
        ]);
        $user->subscriptions()->create([
            'plan' => 'monthly',
            'amount' => 10000,
            'currency' => 'TZS',
            'payment_method' => 'mpesa',
            'payment_reference' => 'payment-123',
            'status' => 'active',
            'started_at' => now()->subDay(),
            'expires_at' => now()->addMonth(),
        ]);
        $token = $user->createToken('feature-test')->plainTextToken;

        $this->withToken($token)
            ->getJson('/api/user/profile')
            ->assertOk()
            ->assertJsonPath('subscription.plan', 'monthly')
            ->assertJsonPath('subscription.status', 'active')
            ->assertJsonPath('is_pro', true);
    }

    public function test_login_returns_a_database_backed_bearer_token(): void
    {
        User::create([
            'name' => 'Existing Member',
            'email' => 'member@example.test',
            'password' => 'password123',
        ]);

        $response = $this->postJson('/api/login', [
            'email' => 'member@example.test',
            'password' => 'password123',
        ])->assertOk()
            ->assertJsonPath('token_type', 'Bearer')
            ->assertJsonPath('user.email', 'member@example.test');

        $this->assertNotEmpty($response->json('access_token'));
        $this->withToken($response->json('access_token'))
            ->getJson('/api/user')
            ->assertOk()
            ->assertJsonPath('email', 'member@example.test');
    }

    public function test_api_cors_allows_flutter_web_preflight_requests(): void
    {
        $this->call('OPTIONS', '/api/register', [], [], [], [
            'HTTP_ORIGIN' => 'http://localhost:8443',
            'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
            'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'content-type,accept',
        ])->assertNoContent()
            ->assertHeader('Access-Control-Allow-Origin', '*');
    }

    public function test_subscription_purchase_endpoint_is_unavailable(): void
    {
        $user = User::create([
            'name' => 'Pro Member',
            'email' => 'pro@example.test',
            'password' => Hash::make('password123'),
        ]);
        $token = $user->createToken('feature-test')->plainTextToken;

        $this->withToken($token)
            ->postJson('/api/subscription', ['payment_method' => 'mpesa'])
            ->assertNotFound();

        $this->withToken($token)
            ->getJson('/api/user/profile')
            ->assertOk()
            ->assertJsonPath('is_pro', false)
            ->assertJsonPath('subscription', null);

        $this->assertDatabaseMissing('subscriptions', ['user_id' => $user->id]);
    }
}
