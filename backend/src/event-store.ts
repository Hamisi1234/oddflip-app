import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import type { MatchEvent } from "./types.js";

interface StoredEvents {
  fingerprints: Record<string, string>;
}

export class EventStore {
  private data: StoredEvents = { fingerprints: {} };
  private initialized = false;

  constructor(private readonly filePath = "backend/data/seen-events.json") {}

  async addIfNew(event: MatchEvent): Promise<boolean> {
    await this.initialize();
    if (this.data.fingerprints[event.fingerprint]) return false;

    this.data.fingerprints[event.fingerprint] = new Date().toISOString();
    await this.persist();
    return true;
  }

  private async initialize() {
    if (this.initialized) return;
    this.initialized = true;
    try {
      this.data = JSON.parse(await readFile(this.filePath, "utf8")) as StoredEvents;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
  }

  private async persist() {
    await mkdir(dirname(this.filePath), { recursive: true });
    const temporaryPath = `${this.filePath}.tmp`;
    await writeFile(temporaryPath, JSON.stringify(this.data, null, 2));
    await rename(temporaryPath, this.filePath);
  }
}
