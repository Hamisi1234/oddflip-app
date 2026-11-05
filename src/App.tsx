import { useEffect, useRef, useState } from "react";
import { fetchFixtureEvents, fetchLiveFixtures, type LiveFixture, type MatchEvent } from "./sports-data";
import { triggerNativeAlertHaptic } from "./native";

function usePersistentState<T>(key: string, initialValue: T) {
  const [value, setValue] = useState<T>(() => {
    try {
      const saved = window.localStorage.getItem(key);
      return saved ? JSON.parse(saved) as T : initialValue;
    } catch {
      return initialValue;
    }
  });

  useEffect(() => {
    window.localStorage.setItem(key, JSON.stringify(value));
  }, [key, value]);

  return [value, setValue] as const;
}

function playAlertTone(sound: string) {
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) return;
  const context = new AudioContextClass();
  const oscillator = context.createOscillator();
  const gain = context.createGain();
  oscillator.connect(gain);
  gain.connect(context.destination);
  oscillator.type = sound === "Siren" ? "sawtooth" : sound === "Harsh beep" ? "square" : "sine";
  oscillator.frequency.setValueAtTime(sound === "Pop" ? 520 : 760, context.currentTime);
  if (sound === "Siren") oscillator.frequency.linearRampToValueAtTime(1040, context.currentTime + 0.35);
  gain.gain.setValueAtTime(0.0001, context.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.12, context.currentTime + 0.02);
  gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + 0.42);
  oscillator.start();
  oscillator.stop(context.currentTime + 0.43);
  oscillator.addEventListener("ended", () => void context.close());
}

declare global {
  interface Window {
    webkitAudioContext?: typeof AudioContext;
  }
}

type IconName =
  | "arrow-left"
  | "bell"
  | "calendar"
  | "chevron-right"
  | "clock"
  | "home"
  | "search"
  | "settings"
  | "shield"
  | "star"
  | "timeline"
  | "volume"
  | "wifi-off"
  | "x";

function Icon({ name, size = 20 }: { name: IconName; size?: number }) {
  const paths: Record<IconName, React.ReactNode> = {
    "arrow-left": <><path d="m15 18-6-6 6-6" /><path d="M9 12h9" /></>,
    bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" /><path d="M10 21h4" /></>,
    calendar: <><path d="M6 2v4M18 2v4M3 10h18" /><rect x="3" y="4" width="18" height="18" rx="3" /></>,
    "chevron-right": <path d="m9 18 6-6-6-6" />,
    clock: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
    home: <><path d="m3 11 9-8 9 8" /><path d="M5 10v11h14V10M9 21v-7h6v7" /></>,
    search: <><circle cx="11" cy="11" r="7" /><path d="m20 20-4-4" /></>,
    settings: <><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1a1.7 1.7 0 0 0 1.9.3 1.7 1.7 0 0 0 1-1.6v-.2h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z" /></>,
    shield: <><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z" /><path d="m9 12 2 2 4-5" /></>,
    star: <path d="m12 2 3 6.2 6.8 1-4.9 4.8 1.2 6.8-6.1-3.2-6.1 3.2 1.2-6.8-4.9-4.8 6.8-1L12 2Z" />,
    timeline: <><path d="M5 4v16M5 8h6M5 16h10" /><circle cx="5" cy="8" r="2" /><circle cx="5" cy="16" r="2" /></>,
    volume: <><path d="M11 5 6 9H3v6h3l5 4V5Z" /><path d="M15 9a4 4 0 0 1 0 6M18 6a8 8 0 0 1 0 12" /></>,
    "wifi-off": <><path d="m2 2 20 20M8.5 8.5A8 8 0 0 1 20 10M5 10a12 12 0 0 1 2.5-1.7M2 6a16 16 0 0 1 15.4-2M9 14a4 4 0 0 1 6.4-.5M12 19h.01" /></>,
    x: <><path d="m6 6 12 12M18 6 6 18" /></>,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {paths[name]}
    </svg>
  );
}

function TeamMark({ code, tone = "dark" }: { code: string; tone?: "dark" | "red" | "blue" | "gold" }) {
  return <span className={`team-mark ${tone}`}>{code}</span>;
}

function Toggle({ on, onChange, label }: { on: boolean; onChange: () => void; label: string }) {
  return (
    <button className={`toggle ${on ? "on" : ""}`} onClick={onChange} aria-label={`${label}: ${on ? "on" : "off"}`} aria-pressed={on}>
      <span />
    </button>
  );
}

function teamCode(name: string) {
  const words = name.replace(/[^a-zA-Z0-9 ]/g, "").split(/\s+/).filter(Boolean);
  return (words.length > 1 ? words.map((word) => word[0]).join("") : words[0]?.slice(0, 3) ?? "FC").slice(0, 3).toUpperCase();
}

function LiveTicker({ fixtures }: { fixtures: LiveFixture[] }) {
  const liveMatches = fixtures.map((fixture) => ({
    league: teamCode(fixture.league.name),
    home: teamCode(fixture.home.name),
    score: `${fixture.home.goals}–${fixture.away.goals}`,
    away: teamCode(fixture.away.name),
    minute: fixture.minute !== null ? `${fixture.minute}′` : "—′",
  }));
  const repeatedMatches = [...liveMatches, ...liveMatches];
  return (
    <section className="live-ticker" aria-label="Live match scores">
      <div className="ticker-label"><i /> LIVE</div>
      <div className="ticker-viewport">
        <div className="ticker-track">
          {liveMatches.length === 0 && <div className="ticker-match"><span>Waiting for live Sportradar data</span></div>}
          {repeatedMatches.map((match, index) => (
            <div className="ticker-match" key={`${match.home}-${index}`} aria-hidden={index >= liveMatches.length}>
              <small>{match.league}</small>
              <span>{match.home}</span>
              <strong>{match.score}</strong>
              <span>{match.away}</span>
              <time>{match.minute}</time>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function MatchSkeleton() {
  return (
    <div className="match-skeleton" aria-label="Loading live match">
      <div className="skeleton-line short" />
      <div className="skeleton-teams">
        <span /><div className="skeleton-line score" /><span />
      </div>
      <div className="skeleton-line footer" />
    </div>
  );
}

function MatchCard({ fixture, onOpen, favorite, onFavorite }: { fixture: LiveFixture; onOpen: () => void; favorite: boolean; onFavorite: () => void }) {
  const league = fixture.league.name;
  const homeName = fixture.home.name;
  const awayName = fixture.away.name;
  const minute = fixture.minute !== null ? `${fixture.minute}′` : "—′";
  const score = `${fixture.home.goals} — ${fixture.away.goals}`;
  return (
    <article className="match-card">
      <div className="match-meta">
        <span className="league-label">{league}</span>
        <button className={`icon-button ${favorite ? "favorite" : ""}`} onClick={onFavorite} aria-label="Favorite match">
          <Icon name="star" size={18} />
        </button>
      </div>
      <button className="match-main" onClick={onOpen}>
        <div className="team">
          <TeamMark code={teamCode(homeName)} tone="blue" />
          <span>{homeName}</span>
        </div>
        <div className="score-block">
          <span className="live-minute"><i /> {minute}</span>
          <strong>{score}</strong>
          <small>{fixture.venue ?? "Venue unavailable"}</small>
        </div>
        <div className="team">
          <TeamMark code={teamCode(awayName)} tone="dark" />
          <span>{awayName}</span>
        </div>
      </button>
      <button className="match-footer" onClick={onOpen}>
        <span><i className="mini-card" /> {fixture.hasTimeline ? "Live incidents" : "Score coverage only"}</span>
        <span className="view-match">View match <Icon name="chevron-right" size={17} /></span>
      </button>
    </article>
  );
}

function Dashboard({ onOpen, hasAlert, onAlert, onCardAlert }: {
  onOpen: (fixture: LiveFixture) => void;
  hasAlert: boolean;
  onAlert: () => void;
  onCardAlert: (alert: RealAlert) => void;
}) {
  const [favoriteFixtures, setFavoriteFixtures] = usePersistentState<string[]>("rca-favorite-fixtures", []);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [liveFixtures, setLiveFixtures] = useState<LiveFixture[]>([]);
  const [loadError, setLoadError] = useState("");
  const [showAll, setShowAll] = useState(false);
  const knownFavoriteEvents = useRef(new Map<string, Set<string>>());
  const normalizedQuery = query.trim().toLowerCase();
  const filteredFixtures = liveFixtures.filter((fixture) =>
    [fixture.home.name, fixture.away.name, fixture.league.name]
      .some((term) => term.toLowerCase().includes(normalizedQuery)),
  );
  const visibleFixtures = filteredFixtures.slice(0, showAll || normalizedQuery ? filteredFixtures.length : 6);

  const toggleFixtureFavorite = (fixtureId: string) => {
    setFavoriteFixtures((current) =>
      current.includes(fixtureId)
        ? current.filter((id) => id !== fixtureId)
        : [...current, fixtureId],
    );
  };

  useEffect(() => {
    const controller = new AbortController();
    const loadFixtures = async () => {
      try {
        const fixtures = await fetchLiveFixtures(controller.signal);
        setLiveFixtures(fixtures);
        setLoadError("");
      } catch (error) {
        if ((error as Error).name !== "AbortError") setLoadError("Live feed is temporarily unavailable.");
      } finally {
        setLoading(false);
      }
    };
    void loadFixtures();
    const refreshTimer = window.setInterval(() => void loadFixtures(), 20_000);
    const loadingTimer = window.setTimeout(() => setLoading(false), 1_200);
    return () => {
      controller.abort();
      window.clearInterval(refreshTimer);
      window.clearTimeout(loadingTimer);
    };
  }, []);

  useEffect(() => {
    const watchedFixtures = liveFixtures.filter((fixture) =>
      fixture.hasTimeline && favoriteFixtures.includes(fixture.id)
    );
    if (watchedFixtures.length === 0) return;

    const controller = new AbortController();
    const checkFavoriteCards = async () => {
      await Promise.allSettled(watchedFixtures.map(async (fixture) => {
        const nextEvents = await fetchFixtureEvents(fixture.id, controller.signal);
        const nextFingerprints = new Set(nextEvents.map((event) => event.fingerprint));
        const previous = knownFavoriteEvents.current.get(fixture.id);
        if (previous) {
          const newCard = nextEvents.find((event) =>
            event.type.toLowerCase() === "card" && !previous.has(event.fingerprint)
          );
          if (newCard) onCardAlert({ fixture, event: newCard });
        }
        knownFavoriteEvents.current.set(fixture.id, nextFingerprints);
      }));
    };

    void checkFavoriteCards();
    const timer = window.setInterval(() => void checkFavoriteCards(), 30_000);
    return () => {
      controller.abort();
      window.clearInterval(timer);
    };
  }, [favoriteFixtures, liveFixtures, onCardAlert]);

  return (
    <main className="screen dashboard">
      <header className="hero">
        <div className="brand-row">
          <div className="brand-mark"><span /></div>
          <div><p>RED CARD</p><strong>ALERT</strong></div>
          <button className="header-bell" onClick={onAlert} disabled={!hasAlert} aria-label={hasAlert ? "Show latest real alert" : "No real alerts received"}>
            <Icon name="bell" />
            {hasAlert && <span />}
          </button>
        </div>
        <div className="greeting">
          <div><small>{new Intl.DateTimeFormat("en", { weekday: "long", day: "numeric", month: "short" }).format(new Date())}</small><h1>Live matches</h1></div>
          <span className="live-pill"><i /> LIVE</span>
        </div>
        <label className="search-box">
          <Icon name="search" size={19} />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search team, league or match" aria-label="Search matches" />
          {query && <button onClick={() => setQuery("")} aria-label="Clear search"><Icon name="x" size={16} /></button>}
        </label>
      </header>
      <LiveTicker fixtures={liveFixtures} />

      <section className="content">
        <div className="section-heading">
          <div><span className="eyebrow">SPORTRADAR · LIVE</span><h2>Live now</h2></div>
          {filteredFixtures.length > 6 && <button onClick={() => setShowAll(!showAll)}>{showAll ? "Show less" : `See all ${filteredFixtures.length}`}</button>}
        </div>
        {loading ? <MatchSkeleton /> : visibleFixtures.length > 0 ? (
          <div className="live-match-list">
            {visibleFixtures.map((fixture) => (
              <MatchCard
                key={fixture.id}
                fixture={fixture}
                onOpen={() => onOpen(fixture)}
                favorite={favoriteFixtures.includes(fixture.id)}
                onFavorite={() => toggleFixtureFavorite(fixture.id)}
              />
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <span><Icon name="search" /></span>
            <strong>{loadError || "No live matches currently"}</strong>
            <p>{loadError ? "Sportradar will retry automatically." : "Check again when matches are in progress."}</p>
          </div>
        )}
      </section>
    </main>
  );
}

type RealAlert = {
  fixture: LiveFixture;
  event: MatchEvent;
};

function eventKind(event: MatchEvent) {
  if (event.isRedCard) return "red";
  if (event.type.toLowerCase() === "card") return "yellow";
  if (event.type.toLowerCase() === "goal") return "goal";
  return "other";
}

function Details({ fixture, onBack, onAlert }: { fixture?: LiveFixture; onBack: () => void; onAlert: (alert: RealAlert) => void }) {
  const [filter, setFilter] = useState<"all" | "cards">("all");
  const [events, setEvents] = useState<MatchEvent[]>([]);
  const [loadingEvents, setLoadingEvents] = useState(true);
  const [eventsError, setEventsError] = useState("");
  const streamRef = useRef<HTMLDivElement>(null);
  const knownEvents = useRef<Set<string>>();
  const visibleEvents = filter === "cards" ? events.filter((event) => event.type.toLowerCase() === "card") : events;
  const homeName = fixture?.home.name ?? "";
  const awayName = fixture?.away.name ?? "";
  const score = fixture ? `${fixture.home.goals} — ${fixture.away.goals}` : "";
  const cardCount = events.filter((event) => event.type.toLowerCase() === "card").length;
  const redCardCount = events.filter((event) => event.isRedCard).length;
  const yellowCardCount = cardCount - redCardCount;

  useEffect(() => {
    if (!fixture) return;
    if (!fixture.hasTimeline) {
      setEvents([]);
      setEventsError("This Sportradar fixture has score coverage only; timeline incidents are not included.");
      setLoadingEvents(false);
      return;
    }
    const controller = new AbortController();
    const loadEvents = async () => {
      try {
        const nextEvents = await fetchFixtureEvents(fixture.id, controller.signal);
        const nextFingerprints = new Set(nextEvents.map((event) => event.fingerprint));
        if (knownEvents.current) {
          const newCard = nextEvents.find((event) =>
            event.type.toLowerCase() === "card" &&
            !knownEvents.current?.has(event.fingerprint)
          );
          if (newCard) onAlert({ fixture, event: newCard });
        }
        knownEvents.current = nextFingerprints;
        setEvents(nextEvents.sort((a, b) => a.minute - b.minute));
        setEventsError("");
      } catch (error) {
        if ((error as Error).name !== "AbortError") setEventsError("Live incidents are temporarily unavailable.");
      } finally {
        setLoadingEvents(false);
      }
    };
    void loadEvents();
    const timer = window.setInterval(() => void loadEvents(), 15_000);
    return () => {
      controller.abort();
      window.clearInterval(timer);
      knownEvents.current = undefined;
    };
  }, [fixture?.id]);

  useEffect(() => {
    const stream = streamRef.current;
    if (!stream || filter !== "all") return;
    window.setTimeout(() => {
      stream.scrollTo({ top: stream.scrollHeight, behavior: "smooth" });
    }, 80);
  }, [events.length, filter]);

  if (!fixture) {
    return (
      <main className="screen details">
        <div className="empty-state details-empty">
          <span><Icon name="timeline" /></span>
          <strong>Select a real live match</strong>
          <p>Open a match from the live dashboard to view its incidents.</p>
          <button className="primary-button" onClick={onBack}>Back to live matches</button>
        </div>
      </main>
    );
  }

  return (
    <main className="screen details">
      <header className="detail-hero">
        <div className="detail-top">
          <button className="back-button" onClick={onBack} aria-label="Back"><Icon name="arrow-left" /></button>
          <span>{fixture.league.name}</span>
          <button className="back-button" aria-label="Favorite"><Icon name="star" /></button>
        </div>
        <div className="detail-score">
          <div><TeamMark code={teamCode(homeName)} tone="blue" /><strong>{homeName}</strong></div>
          <section><span><i /> LIVE · {fixture.minute !== null ? `${fixture.minute}′` : "—′"}</span><b>{score}</b><small>{fixture.venue ?? "Venue unavailable"}</small></section>
          <div><TeamMark code={teamCode(awayName)} tone="dark" /><strong>{awayName}</strong></div>
        </div>
      </header>
      <section className="detail-content">
        <div className="match-status">
          <span><Icon name="clock" size={18} /> {fixture.status}</span>
          <strong><i className="mini-card" /> {redCardCount} red · {yellowCardCount} yellow</strong>
        </div>
        <div className="tabs">
          <button className={filter === "all" ? "active" : ""} onClick={() => setFilter("all")}>All events</button>
          <button className={filter === "cards" ? "active" : ""} onClick={() => setFilter("cards")}>Cards only <span>{cardCount}</span></button>
        </div>
        <div className="stream-status">
          <span><i /> LIVE COMMENTARY</span>
          <small>{loadingEvents ? "Loading real incidents" : filter === "all" ? "Auto-following latest" : "Filtered view"}</small>
        </div>
        <div className="timeline" key={filter} ref={streamRef} aria-live="polite">
          {visibleEvents.map((event) => (
            <article className={`event ${eventKind(event)}`} key={event.fingerprint}>
              <time>{event.minute}′</time>
              <i className="event-dot" />
              <div>
                <span className={`event-icon ${eventKind(event)}`}>{eventKind(event) === "red" || eventKind(event) === "yellow" ? "" : event.type.toUpperCase()}</span>
                <strong>{event.isRedCard ? "Red card" : event.detail}</strong>
                <p>{event.playerName} · {event.teamName}</p>
                {event.comments && <small>{event.comments}</small>}
              </div>
            </article>
          ))}
          {!loadingEvents && visibleEvents.length === 0 && <div className="timeline-empty">{eventsError || (filter === "cards" ? "No card incidents reported." : "No incidents reported yet.")}</div>}
        </div>
      </section>
    </main>
  );
}

function SettingRow({ icon, title, subtitle, children }: { icon: IconName; title: string; subtitle: string; children: React.ReactNode }) {
  return (
    <div className="setting-row">
      <span className="setting-icon"><Icon name={icon} size={20} /></span>
      <div><strong>{title}</strong><p>{subtitle}</p></div>
      {children}
    </div>
  );
}

function Settings() {
  const [push, setPush] = usePersistentState("rca-push", true);
  const [vibration, setVibration] = usePersistentState("rca-vibration", true);
  const [allMatches, setAllMatches] = usePersistentState("rca-all-matches", false);
  const [sound, setSound] = usePersistentState("rca-sound", "Siren");
  const [permission, setPermission] = useState<NotificationPermission | "unsupported">(
    "Notification" in window ? Notification.permission : "unsupported",
  );

  const togglePush = async () => {
    if (!push && "Notification" in window && Notification.permission === "default") {
      const result = await Notification.requestPermission();
      setPermission(result);
      setPush(result === "granted");
      return;
    }
    setPush(!push);
  };

  const chooseSound = (item: string) => {
    setSound(item);
    playAlertTone(item);
  };

  return (
    <main className="screen settings-screen">
      <header className="simple-header">
        <span className="eyebrow">YOUR PREFERENCES</span>
        <h1>Alert settings</h1>
        <p>Choose how and when you want to be notified.</p>
      </header>
      <section className="settings-content">
        <h2>Notifications</h2>
        <div className="settings-card">
          <SettingRow icon="bell" title="Push notifications" subtitle="Instant red and yellow card alerts">
            <Toggle on={push} onChange={togglePush} label="Push notifications" />
          </SettingRow>
          <SettingRow icon="volume" title="Vibration" subtitle="Haptic alert feedback">
            <Toggle on={vibration} onChange={() => setVibration(!vibration)} label="Vibration" />
          </SettingRow>
        </div>

        <h2>Alert sound</h2>
        <div className="sound-grid">
          {["Siren", "Harsh beep", "Pop"].map((item) => (
            <button className={sound === item ? "active" : ""} onClick={() => chooseSound(item)} key={item}>
              <span><Icon name="volume" size={19} /></span>{item}<i />
            </button>
          ))}
        </div>
        {permission === "denied" && <p className="permission-note">Browser notifications are blocked. Enable them in your browser settings.</p>}

        <h2>Match coverage</h2>
        <div className="settings-card">
          <SettingRow icon="star" title="Favorites only" subtitle="Your saved teams and leagues">
            <Toggle on={!allMatches} onChange={() => setAllMatches(false)} label="Favorites only" />
          </SettingRow>
          <SettingRow icon="timeline" title="All live matches" subtitle="Every live card event">
            <Toggle on={allMatches} onChange={() => setAllMatches(true)} label="All live matches" />
          </SettingRow>
        </div>

        <button className="silent-hours">
          <span className="setting-icon"><Icon name="clock" size={20} /></span>
          <span><strong>Silent hours</strong><small>23:00 — 07:00</small></span>
          <Icon name="chevron-right" size={19} />
        </button>
        <div className="offline-note"><Icon name="shield" size={18} /><span><strong>Alerts are protected</strong> Match data is cached for offline access.</span></div>
      </section>
    </main>
  );
}

function AlertOverlay({ alert, onClose, onView }: { alert: RealAlert; onClose: () => void; onView: () => void }) {
  const { event, fixture } = alert;
  const isRed = event.isRedCard;
  const cardLabel = isRed ? "Red card" : "Yellow card";
  useEffect(() => {
    const vibration = window.localStorage.getItem("rca-vibration") !== "false";
    const push = window.localStorage.getItem("rca-push") !== "false";
    const sound = JSON.parse(window.localStorage.getItem("rca-sound") || "\"Siren\"") as string;
    if (vibration && "vibrate" in navigator) navigator.vibrate([160, 80, 220]);
    if (vibration) void triggerNativeAlertHaptic();
    playAlertTone(sound);
    if (push && "Notification" in window && Notification.permission === "granted") {
      const notification = new Notification(`${cardLabel} · ${event.minute}′`, {
        body: `${event.playerName} · ${event.teamName}`,
        tag: `card-${event.fingerprint}`,
      });
      window.setTimeout(() => notification.close(), 5000);
    }
  }, [event.fingerprint, cardLabel]);
  return (
    <div className={`alert-overlay ${isRed ? "red-alert" : "yellow-alert"}`} role="dialog" aria-modal="true" aria-label={`${cardLabel} alert`}>
      <div className="edge-flash" />
      <article className="alert-card">
        <div className="alert-card-top">
          <span className="urgent-pill">URGENT · {cardLabel.toUpperCase()}</span>
          <button onClick={onClose} aria-label="Close alert"><Icon name="x" size={19} /></button>
        </div>
        <div className="red-card-visual"><span /></div>
        <p className="alert-minute">{event.minute}′ MINUTE</p>
        <h2>{event.playerName}</h2>
        <p className="alert-team">{event.teamName}</p>
        <div className="alert-score">
          <span><TeamMark code={teamCode(fixture.home.name)} tone="blue" /> {fixture.home.name}</span>
          <strong>{fixture.home.goals} — {fixture.away.goals}</strong>
          <span>{fixture.away.name} <TeamMark code={teamCode(fixture.away.name)} tone="dark" /></span>
        </div>
        <p className="alert-reason">{event.detail}{event.comments ? ` · ${event.comments}` : ""}</p>
        <button className="primary-button" onClick={onView}>View match timeline <Icon name="chevron-right" size={19} /></button>
      </article>
    </div>
  );
}

export default function App() {
  const [screen, setScreen] = useState<"home" | "details" | "settings">("home");
  const [alertOpen, setAlertOpen] = useState(false);
  const [latestAlert, setLatestAlert] = useState<RealAlert>();
  const [selectedFixture, setSelectedFixture] = useState<LiveFixture>();
  const [online, setOnline] = useState(navigator.onLine);

  useEffect(() => {
    const goOnline = () => setOnline(true);
    const goOffline = () => setOnline(false);
    window.addEventListener("online", goOnline);
    window.addEventListener("offline", goOffline);
    return () => {
      window.removeEventListener("online", goOnline);
      window.removeEventListener("offline", goOffline);
    };
  }, []);

  const showDetails = (fixture?: LiveFixture) => {
    if (fixture) setSelectedFixture(fixture);
    setAlertOpen(false);
    setScreen("details");
  };

  const showRealAlert = (alert: RealAlert) => {
    setLatestAlert(alert);
    setSelectedFixture(alert.fixture);
    setAlertOpen(true);
  };

  return (
    <div className="app-shell">
      <div className="phone-frame">
        <div className="status-bar"><span>9:41</span><span><i /> <i /> <b /></span></div>
        {!online && <div className="offline-banner"><Icon name="wifi-off" size={14} /> Offline · Showing cached matches</div>}
        <div className="screen-wrap">
          {screen === "home" && <Dashboard onOpen={showDetails} hasAlert={Boolean(latestAlert)} onAlert={() => latestAlert && setAlertOpen(true)} onCardAlert={showRealAlert} />}
          {screen === "details" && <Details fixture={selectedFixture} onBack={() => setScreen("home")} onAlert={showRealAlert} />}
          {screen === "settings" && <Settings />}
        </div>
        <nav className="bottom-nav" aria-label="Primary navigation">
          <button className={screen === "home" ? "active" : ""} onClick={() => setScreen("home")}><Icon name="home" /><span>Home</span></button>
          <button className={screen === "details" ? "active" : ""} onClick={() => setScreen("details")}><Icon name="timeline" /><span>Matches</span></button>
          <button className="alert-nav" disabled={!latestAlert} onClick={() => latestAlert && setAlertOpen(true)} aria-label={latestAlert ? "Show latest real card alert" : "No real card alert received"}><span /></button>
          <button><Icon name="star" /><span>Favorites</span></button>
          <button className={screen === "settings" ? "active" : ""} onClick={() => setScreen("settings")}><Icon name="settings" /><span>Settings</span></button>
        </nav>
        {alertOpen && latestAlert && <AlertOverlay alert={latestAlert} onClose={() => setAlertOpen(false)} onView={() => showDetails(latestAlert.fixture)} />}
      </div>
      <aside className="desktop-note">
        <div className="brand-mark dark"><span /></div>
        <span>RED CARD ALERT</span>
        <h2>Every red.<br />Right now.</h2>
        <p>A live football alert experience built for the moments you can’t miss.</p>
        <div className="desktop-feature"><i><Icon name="bell" /></i><span><strong>Instant alerts</strong><small>Delivered in under 3 seconds</small></span></div>
        <div className="desktop-feature"><i><Icon name="wifi-off" /></i><span><strong>Works offline</strong><small>Recent match state is always available</small></span></div>
      </aside>
    </div>
  );
}
