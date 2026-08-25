import { describe, expect, it } from "vitest";
import { BackupMetadataConflictError, SupabaseBackupStore, type BackupStoreFetch } from "../src/supabase-backup-store";

const request = { ownerID: "11111111-1111-1111-1111-111111111111", localAudioID: "22222222-2222-2222-2222-222222222222", byteCount: 1024, sha256: "a".repeat(64) };
const storedBackup = { id: "33333333-3333-3333-3333-333333333333", owner_id: request.ownerID, local_audio_id: request.localAudioID, byte_count: request.byteCount, sha256: request.sha256, object_key: "original-audio/opaque-random-key", r2_upload_id: null, r2_upload_claim: null, r2_upload_claimed_at: null, state: "uploading" };

describe("SupabaseBackupStore", () => {
  it("begins or resets an opaque, server-owned upload generation atomically", async () => {
    const fetch = new StubFetch([json([storedBackup])]);
    const store = new SupabaseBackupStore({ supabaseURL: "https://project.supabase.co", serviceRoleKey: "service-role-key", fetch: fetch.fetch });

    await expect(store.begin(request)).resolves.toEqual({ id: storedBackup.id, state: "uploading" });
    expect(fetch.requests).toHaveLength(1);
    expect(fetch.requests[0].url).toBe("https://project.supabase.co/rest/v1/rpc/begin_audio_backup");
    expect(JSON.parse(String(fetch.requests[0].init?.body))).toEqual({ p_owner_id: request.ownerID, p_local_audio_id: request.localAudioID, p_byte_count: request.byteCount, p_sha256: request.sha256 });
  });

  it("invokes its fetch dependency without a receiver", async () => {
    let receiver: unknown;
    const fetch: BackupStoreFetch = async function(this: unknown) {
      receiver = this;
      return json([storedBackup]);
    };
    const store = new SupabaseBackupStore({ supabaseURL: "https://project.supabase.co", serviceRoleKey: "service-role-key", fetch });

    await store.begin(request);

    expect(receiver).toBeUndefined();
  });

  it("rejects a conflicting source returned by the atomic begin function", async () => {
    const fetch = new StubFetch([json([{ ...storedBackup, sha256: "b".repeat(64) }])]);
    const store = new SupabaseBackupStore({ supabaseURL: "https://project.supabase.co", serviceRoleKey: "service-role-key", fetch: fetch.fetch });
    await expect(store.begin(request)).rejects.toBeInstanceOf(BackupMetadataConflictError);
  });

  it("allows only one caller to claim multipart creation", async () => {
    const fetch = new StubFetch([
      json([storedBackup]),
      json([]),
      json([{ ...storedBackup, r2_upload_claim: "another-claim", r2_upload_claimed_at: new Date().toISOString() }])
    ]);
    const store = new SupabaseBackupStore({ supabaseURL: "https://project.supabase.co", serviceRoleKey: "service-role-key", fetch: fetch.fetch });

    await expect(store.claimMultipartUpload(storedBackup)).resolves.toMatchObject({ kind: "claimed" });
    await expect(store.claimMultipartUpload(storedBackup)).resolves.toEqual({ kind: "inProgress" });
  });
});

class StubFetch {
  readonly requests: Array<{ url: string; init: RequestInit | undefined }> = [];
  constructor(private readonly responses: Response[]) {}
  fetch: BackupStoreFetch = async (input, init) => {
    this.requests.push({ url: String(input), init });
    const response = this.responses.shift();
    if (!response) throw new Error("Unexpected fetch request");
    return response;
  };
}
function json(value: unknown): Response { return Response.json(value); }
