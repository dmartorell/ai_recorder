import { describe, expect, it } from "vitest";
import { createWorker, type BackupStore, type StoredBackup, type StoredPart, type WorkerAuthenticator } from "../src/cloud-backup";
import { multipartPartSize, type MultipartGateway } from "../src/r2-multipart";

const owner = "11111111-1111-1111-1111-111111111111";
const id = "22222222-2222-2222-2222-222222222222";
const sha256 = "a".repeat(64);

describe("multipart audio backup", () => {
  it("initiates, confirms R2-verified parts, and only marks a verified object backed up", async () => {
    const backups = new MemoryStore();
    const multipart = new StubMultipart();
    const worker = createWorker({ authentication: new Authenticator(), backups, multipart });
    await request(worker, `/${id}/multipart`, "POST");
    const url = await request(worker, `/${id}/parts/1/url`, "POST", { sha256 });
    expect(await url.json()).toMatchObject({ expires_in: 900, url: "https://r2.example.test/part" });
    await request(worker, `/${id}/parts/1/confirm`, "POST", { etag: '"r2-etag"' });
    const complete = await request(worker, `/${id}/complete`, "POST");
    expect(complete.status).toBe(200);
    await expect(complete.json()).resolves.toEqual({ id, state: "backed_up" });
    expect(backups.backup.state).toBe("backed_up");
  });

  it("creates one R2 multipart upload when initiation requests race", async () => {
    const backups = new MemoryStore();
    const multipart = new StubMultipart();
    const worker = createWorker({ authentication: new Authenticator(), backups, multipart });

    const responses = await Promise.all([
      request(worker, `/${id}/multipart`, "POST"),
      request(worker, `/${id}/multipart`, "POST")
    ]);

    expect(responses.map((response) => response.status).sort()).toEqual([200, 409]);
    expect(multipart.createCount).toBe(1);
  });

  it("releases the claim when R2 multipart creation fails", async () => {
    const backups = new MemoryStore();
    const multipart = new StubMultipart(true);
    const worker = createWorker({ authentication: new Authenticator(), backups, multipart });

    await expect(request(worker, `/${id}/multipart`, "POST")).rejects.toThrow("R2 unavailable");
    expect(backups.backup.r2_upload_claim).toBeNull();
  });

  it("aborts the new upload when persisting its ID fails", async () => {
    const backups = new MemoryStore();
    backups.failAssignment = true;
    const multipart = new StubMultipart();
    const worker = createWorker({ authentication: new Authenticator(), backups, multipart });

    await expect(request(worker, `/${id}/multipart`, "POST")).rejects.toThrow("database unavailable");
    expect(multipart.abortCount).toBe(1);
    expect(backups.backup.r2_upload_claim).toBeNull();
  });

  it("does not persist a part whose ETag R2 did not confirm", async () => {
    const backups = new MemoryStore();
    const worker = createWorker({ authentication: new Authenticator(), backups, multipart: new StubMultipart() });
    await request(worker, `/${id}/multipart`, "POST");
    const response = await request(worker, `/${id}/parts/1/confirm`, "POST", { etag: "wrong" });
    expect(response.status).toBe(400);
    expect(backups.parts).toEqual([]);
  });
});

async function request(worker: ReturnType<typeof createWorker>, path: string, method: string, body?: unknown) {
  return worker.fetch!(new Request(`https://worker.example.test/v1/audio-backups${path}`, { method, headers: body ? { "Content-Type": "application/json" } : undefined, body: body ? JSON.stringify(body) : undefined }), {} as Env, {} as ExecutionContext);
}
class Authenticator implements WorkerAuthenticator { async authenticate() { return { userID: owner }; } }
class MemoryStore implements BackupStore {
  backup: StoredBackup = { id, owner_id: owner, local_audio_id: "33333333-3333-3333-3333-333333333333", object_key: "original-audio/opaque", byte_count: multipartPartSize, sha256, state: "uploading", r2_upload_id: null, r2_upload_claim: null, r2_upload_claimed_at: null };
  parts: StoredPart[] = [];
  failAssignment = false;
  async begin() { return { id, state: "uploading" as const }; }
  async get(ownerID: string, backupID: string) { return ownerID === owner && backupID === id ? this.backup : undefined; }
  async claimMultipartUpload() {
    if (this.backup.r2_upload_id) return { kind: "existing" as const, uploadID: this.backup.r2_upload_id };
    if (this.backup.r2_upload_claim) return { kind: "inProgress" as const };
    this.backup.r2_upload_claim = "claim";
    return { kind: "claimed" as const, claimID: "claim" };
  }
  async assignUploadID(_: StoredBackup, claimID: string, uploadID: string) {
    if (this.failAssignment) throw new Error("database unavailable");
    if (this.backup.r2_upload_claim !== claimID) return false;
    this.backup.r2_upload_id = uploadID;
    this.backup.r2_upload_claim = null;
    return true;
  }
  async releaseMultipartUploadClaim(_: StoredBackup, claimID: string) { if (this.backup.r2_upload_claim === claimID) { this.backup.r2_upload_claim = null; } }
  async confirmedParts() { return this.parts; }
  async confirmPart(_: string, part: StoredPart) { this.parts = [part]; }
  async cancel() { this.backup.state = "cancelled"; }
  async markBackedUp() { this.backup.state = "backed_up"; }
}
class StubMultipart implements MultipartGateway {
  createCount = 0;
  abortCount = 0;
  constructor(private readonly failCreate = false) {}
  async create() {
    this.createCount += 1;
    if (this.failCreate) throw new Error("R2 unavailable");
    return { uploadID: "upload-id" };
  }
  async signedPartURL() { return "https://r2.example.test/part"; }
  async listParts() { return [{ partNumber: 1, etag: "r2-etag", byteCount: multipartPartSize }]; }
  async complete() { return { size: multipartPartSize, sha256 }; }
  async abort() { this.abortCount += 1; }
}
