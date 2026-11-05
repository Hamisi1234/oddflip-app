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
  home: TeamScore;
  away: TeamScore;
}

interface TeamScore {
  id: string;
  name: string;
  logo: string;
  goals: number;
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
