<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class MkariaChatMessage extends Model
{
    protected $fillable = ['conversation_id', 'role', 'content', 'betslip'];

    protected function casts(): array
    {
        return ['betslip' => 'array'];
    }

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(MkariaChatConversation::class, 'conversation_id');
    }
}
