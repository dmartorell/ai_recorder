export type TranscriptionLanguage = "spanish" | "english" | "spanish_english";

export interface SpeechmaticsSubmission {
  sourceURL: string;
  callbackURL: string;
  language: TranscriptionLanguage;
  reference: string;
}

export interface SpeechmaticsClient {
  submit(submission: SpeechmaticsSubmission): Promise<string>;
  findByReference(reference: string): Promise<string | undefined>;
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
        notification_config: [{ url: submission.callbackURL, contents: ["jobinfo"], method: "post" }],
        tracking: { reference: submission.reference }
      })
    });
    if (!response.ok) throw new Error("Speechmatics job submission failed");
    const body: unknown = await response.json();
    if (!isRecord(body) || typeof body.id !== "string" || !body.id) throw new Error("Speechmatics job submission returned an invalid response");
    return body.id;
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
