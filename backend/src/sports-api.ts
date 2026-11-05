import { createHash } from "node:crypto";
import type { LiveFixture, MatchEvent } from "./types.js";

interface SportradarCompetitor {
  id: string;
  name: string;
  qualifier?: "home" | "away";
}

interface SportradarSummary {
  sport_event: {
    id: string;
    sport_event_context?: {
      competition?: { id: string; name: string };
      category?: { name: string };
    };
    competitors: SportradarCompetitor[];
    venue?: { name?: string };
    coverage?: {
      sport_event_properties?: {
        basic_play_by_play?: boolean;
        deeper_play_by_play?: boolean;
        extended_play_by_play?: boolean;
      };
    };
  };
  sport_event_status: {
    status?: string;
    match_status?: string;
    home_score?: number;
    away_score?: number;
    clock?: {
      played?: string;
      match_time?: string;
    };
  };
}

interface LiveSummariesPayload {
  summaries?: SportradarSummary[];
}

interface TheSportsDbLiveScore {
  idEvent?: string;
  idLiveScore?: string;
  idLeague?: string;
  strLeague?: string;
  idHomeTeam?: string;
  idAwayTeam?: string;
  strHomeTeam?: string;
  strAwayTeam?: string;
  strHomeTeamBadge?: string;
  strAwayTeamBadge?: string;
  intHomeScore?: string;
  intAwayScore?: string;
  strStatus?: string;
  strProgress?: string;
}

interface TheSportsDbLivePayload {
  livescore?: TheSportsDbLiveScore[] | null;
}

interface SportradarTimelineEvent {
  id?: number;
  type: string;
  time?: string;
  match_time?: number;
  stoppage_time?: number;
  competitor?: { id?: string; name?: string };
  player?: { id?: string; name?: string };
  card_description?: string;
  description?: string;
}

interface TimelinePayload {
  timeline?: SportradarTimelineEvent[];
}

export class SportsApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly retryAfter?: string,
  ) {
    super(message);
  }
}

export class SportsApiClient {
  private readonly apiKey = process.env.SPORTRADAR_API_KEY;
  private readonly baseUrl = process.env.SPORTRADAR_BASE_URL ?? "https://api.sportradar.com/soccer/trial/v4/en";
  private readonly fixtures = new Map<string, LiveFixture>();

  constructor() {
    if (!this.apiKey) {
      console.info("[sports-api] SPORTRADAR_API_KEY is missing; using the public live-score feed.");
    }
  }

  async getLiveFixtures(): Promise<LiveFixture[]> {
    let fixtures: LiveFixture[] = [];

    if (this.apiKey) {
      try {
        const payload = await this.get<LiveSummariesPayload>("/schedules/live/summaries.json");
        fixtures = (payload.summaries ?? [])
          .filter((summary) => summary.sport_event_status.status === "live")
          .map(normalizeFixture);
      } catch (error) {
        console.warn("[sportradar] Live feed failed; using the public live-score fallback.", error);
      }
    }

    if (fixtures.length === 0) {
      fixtures = await this.getPublicLiveFixtures();
    }

    fixtures.forEach((fixture) => this.fixtures.set(fixture.id, fixture));
    return fixtures;
  }

  async getFixtureEvents(fixtureId: string): Promise<MatchEvent[]> {
    const payload = await this.get<TimelinePayload>(`/sport_events/${encodeURIComponent(fixtureId)}/timeline.json`);
    const fixture = this.fixtures.get(fixtureId);
    return (payload.timeline ?? []).map((event) => normalizeTimelineEvent(fixtureId, event, fixture));
  }

  private async get<T>(path: string): Promise<T> {
    if (!this.apiKey) {
      throw new SportsApiError("SPORTRADAR_API_KEY is not configured", 503);
    }

    const url = new URL(`${this.baseUrl}${path}`);
    url.searchParams.set("api_key", this.apiKey);
    const response = await fetch(url, {
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(8_000),
    });

    if (!response.ok) {
      throw new SportsApiError(
        `Sportradar returned HTTP ${response.status}`,
        response.status,
        response.headers.get("retry-after") ?? undefined,
      );
    }

    return response.json() as Promise<T>;
  }

  private async getPublicLiveFixtures(): Promise<LiveFixture[]> {
    const url = process.env.FOOTBALL_LIVE_FALLBACK_URL ??
      "https://www.thesportsdb.com/api/v1/json/3/livescore.php?s=Soccer";
    const response = await fetch(url, {
      headers: { accept: "application/json" },
      signal: AbortSignal.timeout(8_000),
    });

    if (!response.ok) {
      throw new SportsApiError(`Live-score provider returned HTTP ${response.status}`, 502);
    }

    const payload = await response.json() as TheSportsDbLivePayload;
    return (payload.livescore ?? []).map(normalizePublicFixture);
  }
}

function normalizeFixture(summary: SportradarSummary): LiveFixture {
  const event = summary.sport_event;
  const status = summary.sport_event_status;
  const home = event.competitors.find((competitor) => competitor.qualifier === "home") ?? event.competitors[0];
  const away = event.competitors.find((competitor) => competitor.qualifier === "away") ?? event.competitors[1];
  const playedClock = status.clock?.played ?? status.clock?.match_time;
  const parsedMinute = playedClock ? Number.parseInt(playedClock.split(":")[0], 10) : null;
  const coverage = event.coverage?.sport_event_properties;

  return {
    id: event.id,
    league: {
      id: event.sport_event_context?.competition?.id ?? "",
      name: event.sport_event_context?.competition?.name ?? "Football",
      country: event.sport_event_context?.category?.name ?? "",
    },
    status: status.match_status ?? status.status ?? "live",
    minute: Number.isFinite(parsedMinute) ? parsedMinute : null,
    venue: event.venue?.name ?? null,
    hasTimeline: Boolean(
      coverage?.basic_play_by_play ||
      coverage?.deeper_play_by_play ||
      coverage?.extended_play_by_play
    ),
    home: {
      id: home?.id ?? "",
      name: home?.name ?? "Home team",
      logo: "",
      goals: status.home_score ?? 0,
    },
    away: {
      id: away?.id ?? "",
      name: away?.name ?? "Away team",
      logo: "",
      goals: status.away_score ?? 0,
    },
  };
}

function normalizePublicFixture(score: TheSportsDbLiveScore): LiveFixture {
  const parsedMinute = Number.parseInt(score.strProgress ?? "", 10);

  return {
    id: `tsdb:${score.idEvent ?? score.idLiveScore ?? "live"}`,
    league: {
      id: score.idLeague ?? "",
      name: score.strLeague ?? "Football",
      country: "",
    },
    status: score.strStatus ?? "live",
    minute: Number.isFinite(parsedMinute) ? parsedMinute : null,
    venue: null,
    hasTimeline: false,
    home: {
      id: score.idHomeTeam ?? "",
      name: score.strHomeTeam ?? "Home team",
      logo: score.strHomeTeamBadge ?? "",
      goals: parseScore(score.intHomeScore),
    },
    away: {
      id: score.idAwayTeam ?? "",
      name: score.strAwayTeam ?? "Away team",
      logo: score.strAwayTeamBadge ?? "",
      goals: parseScore(score.intAwayScore),
    },
  };
}

function parseScore(value?: string): number {
  const score = Number.parseInt(value ?? "", 10);
  return Number.isFinite(score) ? score : 0;
}

function normalizeTimelineEvent(
  fixtureId: string,
  event: SportradarTimelineEvent,
  fixture?: LiveFixture,
): MatchEvent {
  const normalizedType = event.type.toLowerCase();
  const detail = event.card_description ?? event.description ?? event.type;
  const isCard = normalizedType.includes("card");
  const isRedCard = normalizedType === "red_card" ||
    normalizedType === "yellow_red_card" ||
    detail.toLowerCase().includes("red");
  const knownTeam = [fixture?.home, fixture?.away].find((team) => team?.id === event.competitor?.id);
  const canonical = [
    fixtureId,
    event.id ?? "",
    event.type,
    event.player?.id ?? event.player?.name ?? "",
    event.match_time ?? event.time ?? "",
  ].join(":");

  return {
    fingerprint: createHash("sha256").update(canonical).digest("hex"),
    fixtureId,
    minute: event.match_time ?? 0,
    extraMinute: event.stoppage_time ?? null,
    type: isCard ? "card" : event.type,
    detail,
    teamId: event.competitor?.id ?? knownTeam?.id ?? "",
    teamName: event.competitor?.name ?? knownTeam?.name ?? "Unknown team",
    playerId: event.player?.id ?? null,
    playerName: event.player?.name ?? "Unknown player",
    comments: event.description ?? null,
    isRedCard,
  };
}
