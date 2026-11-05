<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Fixture extends Model
{
    protected $fillable = [
        'provider', 'provider_id', 'league_id', 'home_team_id', 'away_team_id',
        'status', 'minute', 'venue', 'referee', 'season', 'has_timeline',
        'home_score', 'away_score', 'home_yellow_cards', 'away_yellow_cards',
        'home_red_cards', 'away_red_cards', 'home_shots', 'away_shots',
        'home_shots_on_target', 'away_shots_on_target', 'home_corners',
        'away_corners',
        'starts_at', 'last_synced_at',
    ];

    protected function casts(): array
    {
        return ['has_timeline' => 'boolean', 'starts_at' => 'datetime', 'last_synced_at' => 'datetime'];
    }

    public function homeTeam(): BelongsTo
    {
        return $this->belongsTo(Team::class, 'home_team_id');
    }

    public function awayTeam(): BelongsTo
    {
        return $this->belongsTo(Team::class, 'away_team_id');
    }

    public function league(): BelongsTo
    {
        return $this->belongsTo(League::class);
    }
}
