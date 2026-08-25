import { describe, expect, it } from "vitest";
import { TranscriptionSubmitter } from "../src/transcription-submitter";

const job = { id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", backup_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", owner_id: "cccccccc-cccc-cccc-cccc-cccccccccccc", state: "queued" as const, transcription_language: "spanish_english" as const, provider_reference: "dddddddd-dddd-dddd-dddd-dddddddddddd", provider_job_id: null, submission_claim: null };

describe("TranscriptionSubmitter", () => {
  it("submits one scoped URL and persists processing before a duplicate delivery", async () => {
    const jobs = new FakeJobs();
    const source = new FakeSource();
    const provider = new FakeProvider();
    const submitter = new TranscriptionSubmitter({ jobs, source, provider, callbackBaseURL: "https://worker.example.test", claimID: () => "claim-1" });

    await submitter.submit(job.id);
    await submitter.submit(job.id);

    expect(source.keys).toEqual(["original-audio/opaque"]);
    expect(provider.submissions).toEqual([{ sourceURL: "https://r2.example.test/scoped", callbackURL: "https://worker.example.test/v1/transcription-callbacks/dddddddd-dddd-dddd-dddd-dddddddddddd", language: "spanish_english", reference: job.provider_reference }]);
    expect(jobs.recorded).toEqual(["provider-job"]);
  });

  it("records an existing provider job without signing the audio URL or submitting again", async () => {
    const jobs = new FakeJobs();
    const source = new FakeSource();
    const provider = new FakeProvider("existing-provider-job");
    const submitter = new TranscriptionSubmitter({ jobs, source, provider, callbackBaseURL: "https://worker.example.test", claimID: () => "claim-1" });

    await submitter.submit(job.id);

    expect(source.keys).toEqual([]);
    expect(provider.submissions).toEqual([]);
    expect(jobs.recorded).toEqual(["existing-provider-job"]);
  });

  it("does not submit when another delivery owns the unresolved provider request", async () => {
    const jobs = new FakeJobs({ ...job, submission_claim: "another-claim" });
    const provider = new FakeProvider();
    const submitter = new TranscriptionSubmitter({ jobs, source: new FakeSource(), provider, callbackBaseURL: "https://worker.example.test", claimID: () => "claim-1" });

    await expect(submitter.submit(job.id)).rejects.toThrow("unresolved");
    expect(provider.submissions).toEqual([]);
  });

  it("does not submit when the verified audio backup is missing", async () => {
    const jobs = new FakeJobs();
    const provider = new FakeProvider();
    const submitter = new TranscriptionSubmitter({ jobs, source: new FakeSource(), provider, callbackBaseURL: "https://worker.example.test", claimID: () => "claim-1" });
    jobs.backupResult = undefined;

    await expect(submitter.submit(job.id)).rejects.toThrow("Verified audio backup was not found");
    expect(provider.submissions).toEqual([]);
  });

  it("does not record a provider job when submission fails", async () => {
    const jobs = new FakeJobs();
    const provider = new FakeProvider();
    provider.error = new Error("provider unavailable");
    const submitter = new TranscriptionSubmitter({ jobs, source: new FakeSource(), provider, callbackBaseURL: "https://worker.example.test", claimID: () => "claim-1" });

    await expect(submitter.submit(job.id)).rejects.toThrow("provider unavailable");
    expect(jobs.recorded).toEqual([]);
  });
});

class FakeJobs {
  private current: typeof job;
  recorded: string[] = [];
  backupResult: { object_key: string } | undefined = { object_key: "original-audio/opaque" };
  constructor(initial = job) { this.current = { ...initial }; }
  async claimSubmission(_id: string, claimID: string) {
    if (!this.current.submission_claim) this.current = { ...this.current, submission_claim: claimID };
    return this.current;
  }
  async recordSubmission(_id: string, providerJobID: string) { this.recorded.push(providerJobID); this.current = { ...this.current, provider_job_id: providerJobID, state: "processing", submission_claim: null }; return this.current; }
  async releaseSubmissionClaim(_id: string, claimID: string) { if (this.current.submission_claim === claimID) this.current = { ...this.current, submission_claim: null }; }
  async backup() { return this.backupResult; }
}
class FakeSource { keys: string[] = []; async signedReadURL(key: string) { this.keys.push(key); return "https://r2.example.test/scoped"; } }
class FakeProvider {
  submissions: unknown[] = [];
  error: Error | undefined;
  constructor(private readonly existingJobID: string | undefined = undefined) {}
  async findByReference() { return this.existingJobID; }
  async submit(value: unknown) { this.submissions.push(value); if (this.error) throw this.error; return "provider-job"; }
}
