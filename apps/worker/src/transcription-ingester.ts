import type { SpeechmaticsClient } from "./speechmatics-batch-client";

export interface IngestionJob {
  id: string;
  provider_job_id: string;
  provider_reference: string;
  state: "processing" | "complete";
}

export interface TranscriptionIngestionStore {
  processingJob(providerJobID: string): Promise<IngestionJob | undefined>;
  job(jobID: string): Promise<IngestionJob | undefined>;
  complete(jobID: string, artifactKey: string, transcript: unknown): Promise<void>;
}

export interface PrivateTranscriptArtifactStore {
  putIfAbsent(key: string, contents: string): Promise<void>;
}

export class R2TranscriptArtifactStore implements PrivateTranscriptArtifactStore {
  constructor(private readonly bucket: R2Bucket) {}

  async putIfAbsent(key: string, contents: string): Promise<void> {
    const result = await this.bucket.put(key, contents, {
      onlyIf: { etagDoesNotMatch: "*" },
      httpMetadata: { contentType: "application/json" }
    });
    if (!result && !await this.bucket.head(key)) throw new Error("Could not preserve automatic transcript");
  }
}

export class TranscriptionIngester {
  constructor(private readonly dependencies: {
    jobs: TranscriptionIngestionStore;
    provider: SpeechmaticsClient;
    artifacts: PrivateTranscriptArtifactStore;
  }) {}

  async ingest(jobID: string): Promise<void> {
    const job = await this.dependencies.jobs.job(jobID);
    if (!job || job.state === "complete") return;

    const transcript = await this.dependencies.provider.transcript(job.provider_job_id);
    validateTranscript(transcript, job);
    const artifactKey = `automatic-transcripts/${job.id}.json`;
    await this.dependencies.artifacts.putIfAbsent(artifactKey, JSON.stringify(transcript));
    await this.dependencies.jobs.complete(job.id, artifactKey, transcript);
  }
}

function validateTranscript(transcript: unknown, job: IngestionJob): asserts transcript is Record<string, unknown> {
  if (!isRecord(transcript) || !isJSONv2(transcript.format) || !isRecord(transcript.job)
    || transcript.job.id !== job.provider_job_id || !isRecord(transcript.job.tracking)
    || transcript.job.tracking.reference !== job.provider_reference || !Array.isArray(transcript.results)) {
    throw new Error("Invalid provider transcript");
  }

  let wordCount = 0;
  for (const result of transcript.results) {
    if (!isRecord(result) || (result.type !== "word" && result.type !== "punctuation")) continue;
    const alternative = Array.isArray(result.alternatives) ? result.alternatives[0] : undefined;
    if (!isRecord(alternative) || typeof alternative.content !== "string" || !alternative.content
      || typeof alternative.speaker !== "string" || !alternative.speaker) {
      throw new Error("Invalid provider transcript");
    }
    if (result.type === "word") {
      if (!validTime(result.start_time) || !validTime(result.end_time) || result.end_time < result.start_time
        || typeof alternative.confidence !== "number" || alternative.confidence < 0 || alternative.confidence > 1
        || typeof alternative.language !== "string" || !alternative.language) {
        throw new Error("Invalid provider transcript");
      }
      wordCount += 1;
    }
  }
  if (!wordCount) throw new Error("Invalid provider transcript");
}

function isJSONv2(value: unknown): value is string { return typeof value === "string" && /^2\./.test(value); }
function validTime(value: unknown): value is number { return typeof value === "number" && Number.isFinite(value) && value >= 0; }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
