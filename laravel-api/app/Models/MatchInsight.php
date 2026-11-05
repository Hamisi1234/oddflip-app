<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MatchInsight extends Model
{
    protected $fillable = ['fixture_id', 'data', 'synced_at'];

    protected function casts(): array
    {
        return ['data' => 'array', 'synced_at' => 'datetime'];
    }
}
