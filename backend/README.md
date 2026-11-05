# Sportradar Soccer API backend

This service keeps the Sportradar API key outside the browser, exposes normalized
Soccer API v4 live summaries/timelines, and polls selected live events for unique
red-card incidents.

## Setup

1. Copy `backend/.env.example` to `backend/.env`.
2. Add the Soccer API v4 Trial key to `SPORTRADAR_API_KEY`.
3. Set `FRONTEND_ORIGIN` to the exact frontend origin.
4. Build and run:

```sh
pnpm backend:build
pnpm backend:start
```

The API listens on port `8787` by default.

## Endpoints

- `GET /health`
- `GET /api/fixtures/live`
- `GET /api/fixtures/:fixtureId/events`

Set `POLLING_ENABLED=true` to poll active fixtures. Unique red cards are
stored in `backend/data/seen-events.json`. Set `CARD_ALERT_WEBHOOK_URL` to
forward normalized yellow/red-card payloads to an FCM worker or another secure
service.

Polling is disabled by default to protect provider quota. When enabling it,
`MAX_POLLED_FIXTURES` limits incident requests per cycle. For production,
replace this limit with fixture IDs from user subscriptions.

Polling every 15–30 seconds cannot guarantee detection within three seconds of
the real-world event. It can only target sub-three-second dispatch after the
provider event has been detected.
