import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { SportsApiClient, SportsApiError } from "./sports-api.js";
import { EventStore } from "./event-store.js";
import { LiveMatchPoller } from "./poller.js";

const client = new SportsApiClient();
const port = Number(process.env.BACKEND_PORT ?? 8787);
const allowedOrigin = process.env.FRONTEND_ORIGIN ?? "http://localhost:8443";
const cache = new Map<string, { expiresAt: number; value: unknown }>();

const server = createServer(async (request, response) => {
  applyCors(response);
  if (request.method === "OPTIONS") {
    response.writeHead(204).end();
    return;
  }

  try {
    const url = new URL(request.url ?? "/", `http://${request.headers.host ?? "localhost"}`);
    if (request.method === "GET" && url.pathname === "/health") {
      sendJson(response, 200, { status: "ok", provider: "sportradar", providerConfigured: Boolean(process.env.SPORTRADAR_API_KEY) });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/fixtures/live") {
      const fixtures = await cached("live-fixtures", 10_000, () => client.getLiveFixtures());
      sendJson(response, 200, { data: fixtures, meta: { cachedForSeconds: 10 } });
      return;
    }

    const eventRoute = url.pathname.match(/^\/api\/fixtures\/(.+)\/events$/);
    if (request.method === "GET" && eventRoute) {
      const fixtureId = decodeURIComponent(eventRoute[1]);
      const events = await cached(`fixture-events:${fixtureId}`, 5_000, () => client.getFixtureEvents(fixtureId));
      sendJson(response, 200, { data: events });
      return;
    }

    sendJson(response, 404, { error: "Route not found" });
  } catch (error) {
    const status = error instanceof SportsApiError ? error.status : 500;
    sendJson(response, status, {
      error: error instanceof Error ? error.message : "Unexpected server error",
    });
  }
});

const poller = new LiveMatchPoller(client, new EventStore());
if (process.env.POLLING_ENABLED === "true") poller.start();

server.listen(port, () => {
  console.info(`[server] API listening on http://localhost:${port}`);
});

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    poller.stop();
    server.close(() => process.exit(0));
  });
}

function applyCors(response: ServerResponse) {
  response.setHeader("access-control-allow-origin", allowedOrigin);
  response.setHeader("access-control-allow-methods", "GET, OPTIONS");
  response.setHeader("access-control-allow-headers", "content-type");
  response.setHeader("vary", "origin");
}

function sendJson(response: ServerResponse, status: number, value: unknown) {
  response.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(value));
}

async function cached<T>(key: string, ttlMs: number, loader: () => Promise<T>): Promise<T> {
  const existing = cache.get(key);
  if (existing && existing.expiresAt > Date.now()) return existing.value as T;
  const value = await loader();
  cache.set(key, { expiresAt: Date.now() + ttlMs, value });
  return value;
}
