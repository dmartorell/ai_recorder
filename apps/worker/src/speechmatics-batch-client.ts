export type TranscriptionLanguage = "spanish" | "english" | "spanish_english";

export interface SpeechmaticsSubmission {
  sourceURL: string;
  language: TranscriptionLanguage;
  reference: string;
  notification?: { url: string; bearerToken: string };
}

export interface SpeechmaticsClient {
  submit(submission: SpeechmaticsSubmission): Promise<string>;
  findByReference(reference: string): Promise<string | undefined>;
  transcript(providerJobID: string): Promise<unknown>;
  deleteJob(providerJobID: string): Promise<"deleted" | "already_deleted">;
}

type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class SpeechmaticsBatchClient implements SpeechmaticsClient {
  private readonly fetch: Fetch;
  private readonly headers: HeadersInit;

  constructor({ apiKey, fetch = globalThis.fetch }: { apiKey: string; fetch?: Fetch }) {
    this.fetch = fetch;
    this.headers = { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" };
  }

  async submit(submission: SpeechmaticsSubmission): Promise<string> {
    const response = await this.fetch("https://asr.api.speechmatics.com/v2/jobs", {
      method: "POST",
      headers: this.headers,
      body: JSON.stringify({
        type: "transcription",
        fetch_data: { url: submission.sourceURL },
        transcription_config: transcriptionConfig(submission.language),
        tracking: { reference: submission.reference },
        ...(submission.notification ? {
          notification_config: [{
            url: submission.notification.url,
            auth_headers: [`Authorization: Bearer ${submission.notification.bearerToken}`]
          }]
        } : {})
      })
    });
    if (!response.ok) throw new Error("Speechmatics job submission failed");
    const body: unknown = await response.json();
    if (!isRecord(body) || typeof body.id !== "string" || !body.id) throw new Error("Speechmatics job submission returned an invalid response");
    return body.id;
  }

  async transcript(providerJobID: string): Promise<unknown> {
    const response = await this.fetch(`https://asr.api.speechmatics.com/v2/jobs/${encodeURIComponent(providerJobID)}/transcript`, { headers: this.headers });
    if (!response.ok) throw new Error("Speechmatics transcript retrieval failed");
    return response.json();
  }

  async deleteJob(providerJobID: string): Promise<"deleted" | "already_deleted"> {
    const response = await this.fetch(`https://asr.api.speechmatics.com/v2/jobs/${encodeURIComponent(providerJobID)}`, {
      method: "DELETE",
      headers: this.headers
    });
    if (response.status === 404 || response.status === 410) return "already_deleted";
    if (!response.ok) throw new Error("Speechmatics job deletion failed");
    return "deleted";
  }

  async findByReference(reference: string): Promise<string | undefined> {
    const response = await this.fetch("https://asr.api.speechmatics.com/v2/jobs", { headers: this.headers });
    if (!response.ok) throw new Error("Speechmatics job reconciliation failed");
    const body: unknown = await response.json();
    const jobs = isRecord(body) && Array.isArray(body.jobs) ? body.jobs : Array.isArray(body) ? body : undefined;
    if (!jobs) throw new Error("Speechmatics job reconciliation returned an invalid response");
    const matches = jobs.filter((job): job is Record<string, unknown> => isRecord(job) && jobReference(job) === reference && typeof job.id === "string" && job.id.length > 0);
    if (matches.length > 1) throw new Error("Speechmatics reconciliation found duplicate provider jobs");
    const match = matches[0];
    return match && typeof match.id === "string" ? match.id : undefined;
  }
}

function transcriptionConfig(language: TranscriptionLanguage) {
  const base = { model: "melia-1", diarization: "speaker" };
  switch (language) {
    case "spanish": return { ...base, language: "es" };
    case "english": return { ...base, language: "en" };
    case "spanish_english": return { ...base, language: "multi", language_hints: ["es", "en"] };
  }
}

function jobReference(job: Record<string, unknown>): string | undefined {
  const config = isRecord(job.config) ? job.config : undefined;
  const tracking = config && isRecord(config.tracking) ? config.tracking : undefined;
  return tracking && typeof tracking.reference === "string" ? tracking.reference : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
