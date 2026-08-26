import { describe, expect, it } from "vitest";
import { TranscriptionIngester, type IngestionJob } from "../src/transcription-ingester";

const job: IngestionJob = { id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", provider_job_id: "provider-job", provider_reference: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", state: "processing" };
const transcript = {
  format: "2.9", job: { id: job.provider_job_id, tracking: { reference: job.provider_reference } }, results: [
    { type: "word", start_time: 0, end_time: 0.4, alternatives: [{ content: "Hola", confidence: 0.98, language: "es", speaker: "S1" }] },
    { type: "word", start_time: 0.5, end_time: 0.9, alternatives: [{ content: "hello", confidence: 0.97, language: "en", speaker: "S2" }] }
  ]
};

describe("TranscriptionIngester", () => {
  it("preserves and completes a bilingual automatic transcript", async () => {
    const dependencies = new Fakes();
    await new TranscriptionIngester(dependencies).ingest(job.provider_job_id);
    expect(dependencies.artifacts.values).toHaveLength(1);
    expect(dependencies.completed).toEqual([{ jobID: job.id, key: `automatic-transcripts/${job.id}.json`, transcript }]);
  });

  it("does not preserve malformed or provider-mismatched results", async () => {
    const dependencies = new Fakes({ ...transcript, job: { ...transcript.job, id: "other" } });
    await expect(new TranscriptionIngester(dependencies).ingest(job.provider_job_id)).rejects.toThrow("Invalid provider transcript");
    expect(dependencies.artifacts.values).toEqual([]);
    expect(dependencies.completed).toEqual([]);
  });

  it("is safe for duplicate queue delivery", async () => {
    const dependencies = new Fakes();
    await new TranscriptionIngester(dependencies).ingest(job.provider_job_id);
    dependencies.job = { ...job, state: "complete" };
    await new TranscriptionIngester(dependencies).ingest(job.provider_job_id);
    expect(dependencies.artifacts.values).toHaveLength(1);
    expect(dependencies.completed).toHaveLength(1);
  });
});

class Fakes {
  job: IngestionJob | undefined = job;
  artifacts = { values: [] as { key: string; contents: string }[], putIfAbsent: async (key: string, contents: string) => { this.artifacts.values.push({ key, contents }); } };
  completed: { jobID: string; key: string; transcript: unknown }[] = [];
  provider: { transcript: (_id: string) => Promise<unknown> };
  jobs = { processingJob: async () => this.job, job: async () => this.job, complete: async (jobID: string, key: string, value: unknown) => { this.completed.push({ jobID, key, transcript: value }); } };
  constructor(value: unknown = transcript) { this.provider = { transcript: async () => value }; }
}
