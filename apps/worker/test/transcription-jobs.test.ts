import { describe, expect, it } from "vitest";
import { createWorker, type BackupStore, type StoredBackup, type TranscriptionJobQueue, type WorkerAuthenticator } from "../src/cloud-backup";
import type { MultipartGateway } from "../src/r2-multipart";
import { TranscriptionJobNotRetryableError, type TranscriptionJob, type TranscriptionJobStore } from "../src/supabase-transcription-job-store";

const ownerID = "11111111-1111-1111-1111-111111111111";
const backup: StoredBackup = {
  id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", owner_id: ownerID, local_audio_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  object_key: "original-audio/opaque", byte_count: 5, sha256: "a".repeat(64), state: "backed_up", r2_upload_id: null, r2_upload_claim: null, r2_upload_claimed_at: null
};

describe("verified backup transcription jobs", () => {
  it("creates or reuses one queued job and publishes its opaque ID", async () => {
    const jobs = new FakeJobStore();
    const queue = new FakeQueue();
    const worker = workerFor(jobs, queue);

    for (let index = 0; index < 2; index += 1) {
      const response = await worker.fetch!(new Request(`https://worker.example.test/v1/audio-backups/${backup.id}/complete`, { method: "POST" }), {} as Env, {} as ExecutionContext);
      expect(response.status).toBe(200);
    }

    expect(jobs.enqueuedBackupIDs).toEqual([backup.id, backup.id]);
    expect(jobs.jobs).toHaveLength(1);
    expect(queue.messages).toEqual([{ kind: "submit", transcription_job_id: jobs.jobs[0].id }, { kind: "submit", transcription_job_id: jobs.jobs[0].id }]);
  });

  it("retries an owner failed job without a new backup upload", async () => {
    const jobs = new FakeJobStore();
    await jobs.enqueue(backup);
    jobs.jobs[0].state = "failed";
    const queue = new FakeQueue();
    const response = await workerFor(jobs, queue).fetch!(new Request(`https://worker.example.test/v1/audio-backups/${backup.id}/transcription/retry`, { method: "POST" }), {} as Env, {} as ExecutionContext);
    expect(response.status).toBe(204);
    expect(queue.messages).toEqual([{ kind: "submit", transcription_job_id: jobs.jobs[0].id }]);
  });

  it("queues ingestion for an owner retry with an accepted provider job", async () => {
    const jobs = new FakeJobStore();
    await jobs.enqueue(backup);
    jobs.jobs[0].state = "failed";
    jobs.jobs[0].provider_job_id = "provider-job";
    const queue = new FakeQueue();

    const response = await workerFor(jobs, queue).fetch!(new Request(`https://worker.example.test/v1/audio-backups/${backup.id}/transcription/retry`, { method: "POST" }), {} as Env, {} as ExecutionContext);

    expect(response.status).toBe(204);
    expect(queue.messages).toEqual([{ kind: "ingest", transcription_job_id: jobs.jobs[0].id }]);
  });

  it("rejects a retry for a nonfailed owner job", async () => {
    const jobs = new FakeJobStore();
    await jobs.enqueue(backup);

    const response = await workerFor(jobs, new FakeQueue()).fetch!(new Request(`https://worker.example.test/v1/audio-backups/${backup.id}/transcription/retry`, { method: "POST" }), {} as Env, {} as ExecutionContext);

    expect(response.status).toBe(409);
  });

  it("returns not found when another owner retries a backup", async () => {
    const jobs = new FakeJobStore();
    await jobs.enqueue(backup);
    jobs.jobs[0].state = "failed";
    const worker = createWorker({ authentication: new FakeAuthenticator("22222222-2222-2222-2222-222222222222"), backups: new FakeBackupStore(), transcriptionJobs: jobs, transcriptionQueue: new FakeQueue(), multipart: {} as MultipartGateway });

    const response = await worker.fetch!(new Request(`https://worker.example.test/v1/audio-backups/${backup.id}/transcription/retry`, { method: "POST" }), {} as Env, {} as ExecutionContext);

    expect(response.status).toBe(404);
  });

  it("requires authentication to retry a transcription", async () => {
    const worker = createWorker({ authentication: { authenticate: async () => { throw new Error("unauthenticated"); } }, backups: new FakeBackupStore(), transcriptionJobs: new FakeJobStore(), transcriptionQueue: new FakeQueue(), multipart: {} as MultipartGateway });

    const response = await worker.fetch!(new Request(`https://worker.example.test/v1/audio-backups/${backup.id}/transcription/retry`, { method: "POST" }), {} as Env, {} as ExecutionContext);

    expect(response.status).toBe(401);
  });

  it("returns queued transcription state only to the owner", async () => {
    const jobs = new FakeJobStore();
    await jobs.enqueue(backup);
    const ownerResponse = await workerFor(jobs, new FakeQueue()).fetch!(new Request(`https://worker.example.test/v1/audio-backups/${backup.id}/transcription`), {} as Env, {} as ExecutionContext);
    expect(ownerResponse.status).toBe(200);
    await expect(ownerResponse.json()).resolves.toEqual({ state: "queued" });

    const otherResponse = await createWorker({ authentication: new FakeAuthenticator("22222222-2222-2222-2222-222222222222"), backups: new FakeBackupStore(), transcriptionJobs: jobs }).fetch!(new Request(`https://worker.example.test/v1/audio-backups/${backup.id}/transcription`), {} as Env, {} as ExecutionContext);
    expect(otherResponse.status).toBe(404);
  });
});

function workerFor(jobs: TranscriptionJobStore, queue: TranscriptionJobQueue) {
  return createWorker({ authentication: new FakeAuthenticator(ownerID), backups: new FakeBackupStore(), transcriptionJobs: jobs, transcriptionQueue: queue, multipart: {} as MultipartGateway });
}

class FakeAuthenticator implements WorkerAuthenticator {
  constructor(private readonly userID: string) {}
  async authenticate(): Promise<{ userID: string }> { return { userID: this.userID }; }
}

class FakeBackupStore implements BackupStore {
  async get(owner: string, id: string): Promise<StoredBackup | undefined> { return owner === ownerID && id === backup.id ? backup : undefined; }
  async begin(): Promise<never> { throw new Error("unused"); }
  async claimMultipartUpload(): Promise<never> { throw new Error("unused"); }
  async assignUploadID(): Promise<never> { throw new Error("unused"); }
  async releaseMultipartUploadClaim(): Promise<never> { throw new Error("unused"); }
  async confirmedParts() { return []; }
  async confirmPart(): Promise<void> { throw new Error("unused"); }
  async cancel(): Promise<void> { throw new Error("unused"); }
  async markBackedUp(): Promise<void> { throw new Error("unused"); }
}

class FakeJobStore implements TranscriptionJobStore {
  jobs: TranscriptionJob[] = [];
  enqueuedBackupIDs: string[] = [];
  async enqueue(storedBackup: StoredBackup): Promise<TranscriptionJob> {
    this.enqueuedBackupIDs.push(storedBackup.id);
    let job = this.jobs.find((candidate) => candidate.backup_id === storedBackup.id);
    if (!job) {
      job = { id: "cccccccc-cccc-cccc-cccc-cccccccccccc", backup_id: storedBackup.id, owner_id: storedBackup.owner_id, state: "queued", provider_job_id: null };
      this.jobs.push(job);
    }
    return job;
  }
  async get(owner: string, backupID: string): Promise<TranscriptionJob | undefined> { return this.jobs.find((job) => job.owner_id === owner && job.backup_id === backupID); }
  async retryFailed(owner: string, backupID: string): Promise<TranscriptionJob | undefined> {
    const job = await this.get(owner, backupID);
    if (!job) return undefined;
    if (job.state !== "failed") throw new TranscriptionJobNotRetryableError();
    job.state = job.provider_job_id ? "processing" : "queued";
    return job;
  }
}

class FakeQueue implements TranscriptionJobQueue {
  messages: { kind: "submit" | "ingest"; transcription_job_id: string }[] = [];
  async send(message: { kind: "submit" | "ingest"; transcription_job_id: string }): Promise<void> { this.messages.push(message); }
}
