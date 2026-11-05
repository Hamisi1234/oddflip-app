<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MatchEvent extends Model
{
    protected $fillable = [
        'fixture_id', 'provider_event_id', 'fingerprint', 'type', 'detail', 'minute',
        'extra_minute', 'team_provider_id', 'team_name', 'player_provider_id',
        'player_name', 'comments', 'is_red_card', 'occurred_at',
    ];

    protected function casts(): array
    {
        return ['is_red_card' => 'boolean', 'occurred_at' => 'datetime'];
    }
}
