<?php

namespace App\Services;

use Illuminate\Support\Facades\RateLimiter;

class OpenAiQuota
{
    private const REQUESTS_PER_MINUTE = 8;

    private const REQUESTS_PER_DAY = 100;

    public function reserve(string $apiKey): void
    {
        $keyHash = hash('sha256', $apiKey);
        $limits = [
            ["openai:minute:$keyHash", self::REQUESTS_PER_MINUTE, 60],
            ["openai:day:$keyHash", self::REQUESTS_PER_DAY, 86400],
        ];

        foreach ($limits as [$key, $maximum]) {
            if (RateLimiter::tooManyAttempts($key, $maximum)) {
                throw new OpenAiApiException(
                    'OpenAI usage limit reached. Please try again later.',
                    429,
                );
            }
        }

        foreach ($limits as [$key, $maximum, $decaySeconds]) {
            RateLimiter::hit($key, $decaySeconds);
        }
    }
}
