<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Team extends Model
{
    protected $fillable = ['provider', 'provider_id', 'name', 'country', 'logo_url'];
}
