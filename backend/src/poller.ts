import { SportsApiClient, SportsApiError } from "./sports-api.js";
import { EventStore } from "./event-store.js";
import type { MatchEvent } from "./types.js";

export class LiveMatchPoller {
  private timer?: NodeJS.Timeout;
  private running = false;

  constructor(
    private readonly client: SportsApiClient,
    private readonly store: EventStore,
    private readonly intervalMs = Number(process.env.POLL_INTERVAL_SECONDS ?? 20) * 1000,
  ) {}

  start() {
    if (this.timer) return;
    console.info(`[poller] Polling active fixtures every ${this.intervalMs / 1000}s`);
    void this.poll();
    this.timer = setInterval(() => void this.poll(), this.intervalMs);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
  }

  private async poll() {
    if (this.running) return;
    this.running = true;

    try {
      const allFixtures = await this.client.getLiveFixtures();
      const maximumFixtures = Number(process.env.MAX_POLLED_FIXTURES ?? 10);
      const fixtures = allFixtures.slice(0, maximumFixtures);
      const results = await Promise.allSettled(
        fixtures.map(async (fixture) => {
          const events = await this.client.getFixtureEvents(fixture.id);
          for (const event of events.filter((item) => item.type.toLowerCase() === "card")) {
            if (await this.store.addIfNew(event)) {
              await this.handleCard(event);
            }
          }
        }),
      );

      const failures = results.filter((result) => result.status === "rejected");
      console.info(`[poller] fixtures=${fixtures.length}/${allFixtures.length} failures=${failures.length}`);
    } catch (error) {
      const retryAfter = error instanceof SportsApiError ? error.retryAfter : undefined;
      console.error("[poller] Poll failed", {
        message: error instanceof Error ? error.message : String(error),
        retryAfter,
      });
    } finally {
      this.running = false;
    }
  }

  private async handleCard(event: MatchEvent) {
    const payload = {
      eventType: event.isRedCard ? "red_card" : "yellow_card",
      eventId: event.fingerprint,
      fixtureId: String(event.fixtureId),
      teamId: String(event.teamId),
      teamName: event.teamName,
      playerName: event.playerName,
      minute: String(event.minute),
      detail: event.detail,
      detectedAt: new Date().toISOString(),
    };

    console.info("[card-alert] New event", payload);
    const webhookUrl = process.env.CARD_ALERT_WEBHOOK_URL ?? process.env.RED_CARD_WEBHOOK_URL;
    if (!webhookUrl) return;

    const response = await fetch(webhookUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) throw new Error(`Card-alert webhook returned HTTP ${response.status}`);
  }
}
