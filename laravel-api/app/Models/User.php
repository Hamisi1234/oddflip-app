<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, Notifiable;

    protected $fillable = [
        'name',
        'email',
        'password',
        'role',
        'subscription_status',
        'trial_ends_at',
        'subscription_ends_at',
    ];

    protected $hidden = ['password', 'remember_token'];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'trial_ends_at' => 'datetime',
            'subscription_ends_at' => 'datetime',
        ];
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class);
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    public function mkariaChatConversations(): HasMany
    {
        return $this->hasMany(MkariaChatConversation::class);
    }

    public function isPremiumAccessActive(): bool
    {
        if ($this->role === 'admin') {
            return true;
        }

        if (in_array($this->subscription_status, ['disabled', 'disabled_by_admin'], true)) {
            return false;
        }

        if (in_array($this->subscription_status, ['active_paid', 'active'], true)) {
            return $this->subscription_ends_at?->isFuture() ?? false;
        }

        return $this->subscription_status === 'free_trial'
            && ($this->trial_ends_at?->isFuture() ?? false);
    }
}
