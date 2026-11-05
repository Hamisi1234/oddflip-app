<?php

return [
    'apifootball' => [
        'key' => env('API_FOOTBALL_KEY'),
        'base_url' => env('API_FOOTBALL_BASE_URL', 'https://v3.football.api-sports.io'),
    ],
    'openai' => [
        'key' => env('OPENAI_API_KEY'),
    ],
];
