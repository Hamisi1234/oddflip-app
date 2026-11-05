export interface LiveFixture {
  id: string;
  league: {
    id: string;
    name: string;
    country: string;
  };
  status: string;
  minute: number | null;
  venue: string | null;
  hasTimeline: boolean;
  home: {
    id: string;
    name: string;
    logo: string;
    goals: number;
  };
  away: {
    id: string;
    name: string;
    logo: string;
    goals: number;
  };
}

export interface MatchEvent {
  fingerprint: string;
  fixtureId: string;
  minute: number;
  extraMinute: number | null;
  type: string;
  detail: string;
  teamId: string;
  teamName: string;
  playerId: string | null;
  playerName: string;
  comments: string | null;
  isRedCard: boolean;
}

interface ApiResponse<T> {
  data: T;
}

interface PublicLiveScore {
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

interface PublicLivePayload {
  livescore?: PublicLiveScore[] | null;
}

const baseUrl = import.meta.env.VITE_API_BASE_URL ?? "";
const publicLiveUrl = "https://www.thesportsdb.com/api/v1/json/3/livescore.php?s=Soccer";

export async function fetchLiveFixtures(signal?: AbortSignal): Promise<LiveFixture[]> {
  try {
    const response = await fetch(`${baseUrl}/api/fixtures/live`, { signal });
    if (!response.ok) {
      throw new Error(`Live fixtures request failed with HTTP ${response.status}`);
    }

    const payload = await response.json() as ApiResponse<LiveFixture[]>;
    if (!Array.isArray(payload.data)) throw new Error("Live fixtures response is invalid");
    return payload.data;
  } catch (error) {
    if (signal?.aborted) throw error;
    return fetchPublicLiveFixtures(signal);
  }
}

export async function fetchFixtureEvents(fixtureId: string, signal?: AbortSignal): Promise<MatchEvent[]> {
  const response = await fetch(`${baseUrl}/api/fixtures/${encodeURIComponent(fixtureId)}/events`, { signal });
  if (!response.ok) {
    throw new Error(`Fixture events request failed with HTTP ${response.status}`);
  }

  const payload = await response.json() as ApiResponse<MatchEvent[]>;
  return payload.data;
}

async function fetchPublicLiveFixtures(signal?: AbortSignal): Promise<LiveFixture[]> {
  const response = await fetch(publicLiveUrl, { signal });
  if (!response.ok) {
    throw new Error(`Public live fixtures request failed with HTTP ${response.status}`);
  }

  const payload = await response.json() as PublicLivePayload;
  return (payload.livescore ?? []).map(normalizePublicFixture);
}

function normalizePublicFixture(score: PublicLiveScore): LiveFixture {
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
