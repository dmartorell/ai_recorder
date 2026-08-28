import { describe, expect, it, vi } from "vitest";
import {
  type BackupStore,
  type CloudBackup,
  type WorkerAuthenticator,
  createWorker
} from "../src/cloud-backup";
import { BackupMetadataConflictError } from "../src/supabase-backup-store";

describe("GET /v1/audios/:audioID/playback", () => {
  const audioID = "a3f1799a-92ab-43d1-951d-8e1dac1b67d5";

  it("conceals absent, foreign, and non-backed-up Audio", async () => {
    const worker = createWorker({ authentication: new StubAuthenticator("journalist-id"), backups: new PlaybackStore() });
    for (const id of [audioID, "b3f1799a-92ab-43d1-951d-8e1dac1b67d5"]) {
      const response = await worker.fetch(new Request(`https://worker.example.test/v1/audios/${id}/playback`), {} as Env, {} as ExecutionContext);
      expect(response.status).toBe(404);
    }
  });

  it("requires authentication", async () => {
    const worker = createWorker({ authentication: new RejectingAuthenticator(), backups: new PlaybackStore() });
    const response = await worker.fetch(new Request(`https://worker.example.test/v1/audios/${audioID}/playback`), {} as Env, {} as ExecutionContext);
    expect(response.status).toBe(401);
  });

  it("returns a 900-second URL only for an owned verified backup", async () => {
    const signedReadURL = vi.fn().mockResolvedValue("https://r2.example.test/private");
    const worker = createWorker({ authentication: new StubAuthenticator("journalist-id"), backups: new PlaybackStore("original-audio/private"), multipart: { signedReadURL } as never });
    const response = await worker.fetch(new Request(`https://worker.example.test/v1/audios/${audioID}/playback`), {} as Env, {} as ExecutionContext);
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ url: "https://r2.example.test/private", expires_in: 900 });
    expect(signedReadURL).toHaveBeenCalledOnce();
    expect(signedReadURL).toHaveBeenCalledWith("original-audio/private");
  });
});

describe("POST /v1/audio-backups", () => {
  it("creates an upload owned by the authenticated user", async () => {
    const store = new StubBackupStore();
    const worker = createWorker({
      authentication: new StubAuthenticator("journalist-id"),
      backups: store
    });

    const response = await worker.fetch(
      new Request("https://worker.example.test/v1/audio-backups", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          local_audio_id: "b5f1799a-92ab-43d1-951d-8e1dac1b67d5",
          byte_count: 1024,
          sha256: "bf639d89a3de0c2e761d336fc7bf954cd615c5a65aad89915421e9e95179507e",
          title_snapshot: "Audio - Aug 28, 2026, 10:32 AM",
          capture_started_at: "2026-08-28T10:32:00Z",
          duration_milliseconds: 61_000
        })
      }),
      {} as Env,
      {} as ExecutionContext
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toEqual({ id: store.backup.id, state: "uploading" });
    expect(store.request).toEqual({
      ownerID: "journalist-id",
      localAudioID: "b5f1799a-92ab-43d1-951d-8e1dac1b67d5",
      byteCount: 1024,
      sha256: "bf639d89a3de0c2e761d336fc7bf954cd615c5a65aad89915421e9e95179507e",
      transcriptionLanguage: "spanish_english",
      titleSnapshot: "Audio - Aug 28, 2026, 10:32 AM",
      captureStartedAt: "2026-08-28T10:32:00Z",
      durationMilliseconds: 61_000
    });
  });

  it("rejects a request without a valid identity", async () => {
    const worker = createWorker({
      authentication: new RejectingAuthenticator(),
      backups: new StubBackupStore()
    });

    const response = await worker.fetch(
      new Request("https://worker.example.test/v1/audio-backups", { method: "POST" }),
      {} as Env,
      {} as ExecutionContext
    );

    expect(response.status).toBe(401);
  });

  it("rejects a conflicting retry without creating a second upload", async () => {
    const worker = createWorker({
      authentication: new StubAuthenticator("journalist-id"),
      backups: new ConflictingBackupStore()
    });

    const response = await worker.fetch(
      new Request("https://worker.example.test/v1/audio-backups", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          local_audio_id: "b5f1799a-92ab-43d1-951d-8e1dac1b67d5",
          byte_count: 1024,
          sha256: "bf639d89a3de0c2e761d336fc7bf954cd615c5a65aad89915421e9e95179507e",
          title_snapshot: "Audio - Aug 28, 2026, 10:32 AM",
          capture_started_at: "2026-08-28T10:32:00Z",
          duration_milliseconds: 61_000
        })
      }),
      {} as Env,
      {} as ExecutionContext
    );

    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toEqual({ error: "backup_metadata_conflict" });
  });

  it("rejects invalid backup metadata before creating an upload", async () => {
    const store = new StubBackupStore();
    const worker = createWorker({
      authentication: new StubAuthenticator("journalist-id"),
      backups: store
    });

    const response = await worker.fetch(
      new Request("https://worker.example.test/v1/audio-backups", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ local_audio_id: "not-a-uuid", byte_count: 0, sha256: "bad", title_snapshot: "", capture_started_at: "invalid", duration_milliseconds: -1 })
      }),
      {} as Env,
      {} as ExecutionContext
    );

    expect(response.status).toBe(400);
    expect(store.request).toBeUndefined();
  });
});

class StubAuthenticator implements WorkerAuthenticator {
  constructor(private readonly userID: string) {}

  async authenticate(): Promise<{ userID: string }> {
    return { userID: this.userID };
  }
}

class RejectingAuthenticator implements WorkerAuthenticator {
  async authenticate(): Promise<{ userID: string }> {
    throw new Error("invalid token");
  }
}

class ConflictingBackupStore implements BackupStore {
  async begin(): Promise<CloudBackup> {
    throw new BackupMetadataConflictError();
  }
}

class PlaybackStore {
  constructor(private readonly objectKey?: string) {}
  async findPlayback(): Promise<{ object_key: string } | undefined> { return this.objectKey ? { object_key: this.objectKey } : undefined; }
}

class StubBackupStore implements BackupStore {
  readonly backup: CloudBackup = { id: "d4814952-c8e8-4a4d-9a73-9fc0d16c3ba8", state: "uploading" };
  request: Parameters<BackupStore["begin"]>[0] | undefined;

  async begin(request: Parameters<BackupStore["begin"]>[0]): Promise<CloudBackup> {
    this.request = request;
    return this.backup;
  }

  async findPlayback(): Promise<undefined> { return undefined; }
}
