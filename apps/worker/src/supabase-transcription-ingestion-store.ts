import type { IngestionJob, TranscriptionIngestionStore } from "./transcription-ingester";

type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class SupabaseTranscriptionIngestionStore implements TranscriptionIngestionStore {
  private readonly base: string;
  private readonly headers: HeadersInit;
  private readonly fetch: Fetch;

  constructor({ supabaseURL, serviceRoleKey, fetch = globalThis.fetch }: { supabaseURL: string; serviceRoleKey: string; fetch?: Fetch }) {
    this.base = supabaseURL.endsWith("/") ? supabaseURL : `${supabaseURL}/`;
    this.headers = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}`, "Content-Type": "application/json" };
    this.fetch = fetch;
  }

  async processingJob(providerJobID: string): Promise<IngestionJob | undefined> {
    return this.resolve({ provider_job_id: `eq.${providerJobID}`, state: "eq.processing" });
  }

  async job(jobID: string): Promise<IngestionJob | undefined> {
    return this.resolve({ id: `eq.${jobID}` });
  }

  private async resolve(filters: Record<string, string>): Promise<IngestionJob | undefined> {
    const url = new URL("rest/v1/transcription_jobs", this.base);
    url.search = new URLSearchParams({ ...filters, select: "id,provider_job_id,provider_reference,state,provider_cleanup_state" }).toString();
    const response = await this.fetch(url, { headers: this.headers });
    if (!response.ok) throw new Error("Could not resolve transcription ingestion");
    const rows: unknown = await response.json();
    if (!Array.isArray(rows) || rows.length > 1 || (rows.length === 1 && !isJob(rows[0]))) throw new Error("Invalid transcription ingestion record");
    return rows[0];
  }

  async complete(jobID: string, artifactKey: string, transcript: unknown): Promise<void> {
    const response = await this.fetch(new URL("rest/v1/rpc/complete_transcription_ingestion", this.base), {
      method: "POST",
      headers: this.headers,
      body: JSON.stringify({ p_job_id: jobID, p_artifact_key: artifactKey, p_transcript: transcript })
    });
    if (!response.ok) throw new Error("Could not complete transcription ingestion");
    const rows: unknown = await response.json();
    if (!Array.isArray(rows) || rows.length !== 1 || !isJob(rows[0])) throw new Error("Invalid transcription ingestion record");
  }
}

function isJob(value: unknown): value is IngestionJob {
  return isRecord(value) && typeof value.id === "string" && typeof value.provider_job_id === "string"
    && typeof value.provider_reference === "string" && (value.state === "processing" || value.state === "complete")
    && (value.provider_cleanup_state === "not_started" || value.provider_cleanup_state === "pending"
      || value.provider_cleanup_state === "complete" || value.provider_cleanup_state === "failed");
}
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
