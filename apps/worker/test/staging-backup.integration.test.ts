import { createHash, randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";

const configuration = loadConfiguration();
const test = configuration ? it : it.skip;

const partSize = 8 * 1024 * 1024;
const part = Buffer.alloc(partSize, 0x5a);
const sha256 = createHash("sha256").update(part).digest("hex");

describe("staging private audio backup", () => {
  test("authorizes owners, confines RLS reads, and verifies a multipart Original Audio", async () => {
    const localAudioID = randomUUID();
    const backup = await begin(localAudioID, sha256);

    const repeated = await begin(localAudioID, sha256);
    expect(repeated.id === backup.id).toBe(true);
    expect(repeated.state).toBe("uploading");

    const conflicting = await request("/v1/audio-backups", {
      method: "POST",
      token: configuration!.ownerToken,
      body: {
        local_audio_id: localAudioID,
        byte_count: partSize,
        sha256: "0".repeat(64)
      }
    });
    expect(conflicting.status).toBe(409);

    const unauthenticated = await request(`/v1/audio-backups/${backup.id}`);
    expect(unauthenticated.status).toBe(401);

    const crossOwner = await request(`/v1/audio-backups/${backup.id}`, {
      token: configuration!.otherOwnerToken
    });
    expect(crossOwner.status).toBe(404);

    await expect(readBackupAs(configuration!.ownerToken, backup.id).then((rows) => rows.length > 0)).resolves.toBe(true);
    await expect(readBackupAs(configuration!.otherOwnerToken, backup.id).then((rows) => rows.length === 0)).resolves.toBe(true);

    const initiated = await request(`/v1/audio-backups/${backup.id}/multipart`, {
      method: "POST",
      token: configuration!.ownerToken
    });
    expect(initiated.status).toBe(200);

    const signedPart = await request(`/v1/audio-backups/${backup.id}/parts/1/url`, {
      method: "POST",
      token: configuration!.ownerToken,
      body: { sha256 }
    });
    expect(signedPart.status).toBe(200);
    const destination = await signedPart.json() as { url: string; expires_in: number };
    expect(destination.expires_in).toBe(900);

    const unsignedMethod = await fetch(destination.url, { method: "GET" });
    expect(unsignedMethod.ok).toBe(false);
    const unsignedPart = new URL(destination.url);
    unsignedPart.searchParams.set("partNumber", "2");
    const unsignedScope = await fetch(unsignedPart, { method: "PUT", body: part });
    expect(unsignedScope.ok).toBe(false);

    const upload = await fetch(destination.url, { method: "PUT", body: part });
    expect(upload.ok).toBe(true);
    const eTag = upload.headers.get("etag");
    expect(eTag).toBeTruthy();

    const confirmed = await request(`/v1/audio-backups/${backup.id}/parts/1/confirm`, {
      method: "POST",
      token: configuration!.ownerToken,
      body: { etag: eTag }
    });
    expect(confirmed.status).toBe(204);

    const completed = await request(`/v1/audio-backups/${backup.id}/complete`, {
      method: "POST",
      token: configuration!.ownerToken
    });
    expect(completed.status).toBe(200);
    const completedBody = await completed.json() as { state: string };
    expect(completedBody.state).toBe("backed_up");

    const status = await request(`/v1/audio-backups/${backup.id}`, { token: configuration!.ownerToken });
    expect(status.status).toBe(200);
    const statusBody = await status.json() as {
      state: string;
      confirmed_parts: Array<{ part_number: number; byte_count: number }>;
    };
    expect(statusBody.state).toBe("backed_up");
    expect(statusBody.confirmed_parts.length).toBe(1);
    expect(statusBody.confirmed_parts[0]?.part_number).toBe(1);
    expect(statusBody.confirmed_parts[0]?.byte_count).toBe(partSize);
  });
});

function loadConfiguration() {
  const workerURL = process.env.BACKUP_TEST_WORKER_URL;
  const supabaseURL = process.env.BACKUP_TEST_SUPABASE_URL;
  const publishableKey = process.env.BACKUP_TEST_SUPABASE_PUBLISHABLE_KEY;
  const ownerToken = process.env.BACKUP_TEST_OWNER_TOKEN;
  const otherOwnerToken = process.env.BACKUP_TEST_OTHER_OWNER_TOKEN;
  if (!workerURL || !supabaseURL || !publishableKey || !ownerToken || !otherOwnerToken) return undefined;
  return { workerURL: new URL(workerURL), supabaseURL: new URL(supabaseURL), publishableKey, ownerToken, otherOwnerToken };
}

async function begin(localAudioID: string, hash: string): Promise<{ id: string; state: string }> {
  const response = await request("/v1/audio-backups", {
    method: "POST",
    token: configuration!.ownerToken,
    body: { local_audio_id: localAudioID, byte_count: partSize, sha256: hash }
  });
  expect(response.status).toBe(201);
  return response.json() as Promise<{ id: string; state: string }>;
}

async function readBackupAs(token: string, backupID: string): Promise<unknown[]> {
  const url = new URL("rest/v1/audio_backups", configuration!.supabaseURL);
  url.search = new URLSearchParams({ id: `eq.${backupID}`, select: "id" }).toString();
  const response = await fetch(url, {
    headers: {
      apikey: configuration!.publishableKey,
      Authorization: `Bearer ${token}`
    }
  });
  expect(response.ok).toBe(true);
  return response.json() as Promise<unknown[]>;
}

function request(path: string, options: { method?: string; token?: string; body?: unknown } = {}) {
  const url = new URL(path, configuration!.workerURL);
  return fetch(url, {
    method: options.method,
    headers: {
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
      ...(options.body ? { "Content-Type": "application/json" } : {})
    },
    body: options.body ? JSON.stringify(options.body) : undefined
  });
}
