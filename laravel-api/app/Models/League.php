<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class League extends Model
{
    protected $fillable = ['provider', 'provider_id', 'name', 'country', 'logo_url'];
}
