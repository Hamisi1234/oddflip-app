<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use JsonException;
use stdClass;

class OpenAiApiService
{
    private const DEFAULT_MODEL = 'gpt-4o-mini';

    private const ENDPOINT = 'https://api.openai.com/v1/chat/completions';

    public function __construct(private readonly OpenAiQuota $quota) {}

    /**
     * @param  array<int, array{role: string, content: string}>  $messages
     * @return array<string, mixed>
     */
    public function complete(array $messages, int $maxTokens = 700): array
    {
        $key = config('services.openai.key');
        if (! is_string($key) || trim($key) === '') {
            throw new OpenAiApiException(
                'OpenAI is not configured. Set OPENAI_API_KEY in the Laravel .env file.',
                503,
            );
        }
        $key = trim($key);

        foreach ($messages as $message) {
            if (! isset($message['role'], $message['content'])
                || ! is_string($message['role'])
                || ! in_array($message['role'], ['system', 'user', 'assistant'], true)
                || ! is_string($message['content'])) {
                throw new OpenAiApiException('Could not prepare the OpenAI request.', 500);
            }
        }

        if ($messages === []) {
            throw new OpenAiApiException('Could not prepare the OpenAI request.', 500);
        }

        $this->quota->reserve($key);

        try {
            $response = Http::acceptJson()
                ->withToken($key)
                ->connectTimeout(5)
                ->timeout(30)
                ->post(self::ENDPOINT, [
                    'model' => self::DEFAULT_MODEL,
                    'messages' => array_values($messages),
                    'temperature' => 0.3,
                    'max_tokens' => $maxTokens,
                    'response_format' => ['type' => 'json_object'],
                ]);
        } catch (ConnectionException $error) {
            report($error);
            $isTimeout = str_contains(strtolower($error->getMessage()), 'timeout')
                || str_contains(strtolower($error->getMessage()), 'timed out');

            throw new OpenAiApiException(
                $isTimeout
                    ? 'OpenAI took too long to respond. Please try again shortly.'
                    : 'OpenAI is temporarily unavailable. Please try again later.',
                $isTimeout ? 504 : 503,
            );
        }

        if (! $response->successful()) {
            $status = $response->status();
            $providerMessage = $response->json('error.message');
            $detail = is_string($providerMessage)
                ? mb_substr(str_replace($key, '[redacted]', trim($providerMessage)), 0, 400)
                : 'No additional error details were provided.';

            Log::error('OpenAI chat completion request failed.', [
                'status' => $status,
                'message' => $detail,
            ]);

            [$message, $appStatus] = match ($status) {
                400 => [
                    'OpenAI rejected the chat completion request. Check the model and JSON response settings.',
                    502,
                ],
                401, 403 => [
                    'OpenAI rejected OPENAI_API_KEY. Check the Laravel server configuration.',
                    503,
                ],
                404 => [
                    'OpenAI could not find model gpt-4o-mini. Check model access for this API project.',
                    503,
                ],
                429 => [
                    'OpenAI quota or rate limit reached. Please try again later.',
                    429,
                ],
                408 => [
                    'OpenAI took too long to respond. Please try again shortly.',
                    504,
                ],
                default => [
                    'OpenAI is temporarily unavailable (HTTP '.$status.'). Please try again later.',
                    $status >= 500 ? 502 : 503,
                ],
            };

            throw new OpenAiApiException($message, $appStatus);
        }

        $content = $response->json('choices.0.message.content');
        if (! is_string($content) || trim($content) === '') {
            throw new OpenAiApiException('OpenAI returned an empty response. Please try again.', 502);
        }

        try {
            $decodedObject = json_decode($content, false, 512, JSON_THROW_ON_ERROR);
            $data = json_decode($content, true, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException $error) {
            report($error);
            throw new OpenAiApiException('OpenAI returned an unreadable response. Please try again.', 502);
        }

        $betslip = is_array($data) ? ($data['betslip'] ?? null) : null;
        if (! ($decodedObject instanceof stdClass)
            || ! is_array($data)
            || count($data) !== 2
            || ! array_key_exists('reply', $data)
            || ! is_string($data['reply'])
            || trim($data['reply']) === ''
            || ! array_key_exists('betslip', $data)
            || ($betslip !== null
                && (! is_array($betslip)
                    || array_is_list($betslip)
                    || ! is_array($betslip['picks'] ?? null)
                    || ! array_is_list($betslip['picks'])))) {
            throw new OpenAiApiException('OpenAI returned an invalid response. Please try again.', 502);
        }

        return $data;
    }
}
