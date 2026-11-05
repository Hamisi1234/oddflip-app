<?php

namespace App\Services;

use RuntimeException;

class OpenAiApiException extends RuntimeException
{
    public function __construct(string $message, public readonly int $statusCode = 503)
    {
        parent::__construct($message);
    }
}
