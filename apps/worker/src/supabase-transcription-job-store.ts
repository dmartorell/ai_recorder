import type { StoredBackup } from "./cloud-backup";

const transcriptionJobsPath = "rest/v1/transcription_jobs";
const enqueueTranscriptionJobPath = "rest/v1/rpc/enqueue_transcription_job";
const selectedColumns = "id,backup_id,owner_id,state,provider_job_id";

export class TranscriptionJobNotRetryableError extends Error {}

export interface TranscriptionJob {
  id: string;
  backup_id: string;
  owner_id: string;
  state: "queued" | "processing" | "complete" | "failed";
  provider_job_id: string | null;
}

export interface TranscriptionJobStore {
  enqueue(backup: StoredBackup): Promise<TranscriptionJob>;
  get(ownerID: string, backupID: string): Promise<TranscriptionJob | undefined>;
  retryFailed(ownerID: string, backupID: string): Promise<TranscriptionJob | undefined>;
}

type StoreFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class SupabaseTranscriptionJobStore implements TranscriptionJobStore {
  private readonly endpoint: URL;
  private readonly enqueueEndpoint: URL;
  private readonly fetch: StoreFetch;
  private readonly headers: HeadersInit;

  constructor({ supabaseURL, serviceRoleKey, fetch = (input, init) => globalThis.fetch(input, init) }: { supabaseURL: string; serviceRoleKey: string; fetch?: StoreFetch }) {
    this.endpoint = new URL(transcriptionJobsPath, withTrailingSlash(supabaseURL));
    this.enqueueEndpoint = new URL(enqueueTranscriptionJobPath, withTrailingSlash(supabaseURL));
    this.fetch = fetch;
    this.headers = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` };
  }

  async enqueue(backup: StoredBackup): Promise<TranscriptionJob> {
    const response = await this.fetch(this.enqueueEndpoint, {
      method: "POST",
      headers: { ...this.headers, "Content-Type": "application/json" },
      body: JSON.stringify({ p_backup_id: backup.id })
    });
    if (!response.ok) throw new Error("Could not enqueue transcription job");
    return oneJob(await response.json());
  }

  async retryFailed(ownerID: string, backupID: string): Promise<TranscriptionJob | undefined> {
    const job = await this.get(ownerID, backupID);
    if (!job) return undefined;
    if (job.state !== "failed") throw new TranscriptionJobNotRetryableError();
    const endpoint = new URL("rpc/retry_failed_transcription", this.endpoint);
    const response = await this.fetch(endpoint, { method: "POST", headers: { ...this.headers, "Content-Type": "application/json" }, body: JSON.stringify({ p_job_id: job.id }) });
    if (!response.ok) throw new Error("Could not retry transcription job");
    return oneJob(await response.json());
  }

  async get(ownerID: string, backupID: string): Promise<TranscriptionJob | undefined> {
    const url = new URL(this.endpoint);
    url.search = new URLSearchParams({ owner_id: `eq.${ownerID}`, backup_id: `eq.${backupID}`, select: selectedColumns }).toString();
    const response = await this.fetch(url, { headers: this.headers });
    if (!response.ok) throw new Error("Could not read transcription job");
    const rows: unknown = await response.json();
    if (!Array.isArray(rows) || rows.length > 1 || (rows.length === 1 && !isJob(rows[0]))) throw new Error("Transcription job persistence returned an invalid record");
    return rows[0];
  }
}

function oneJob(rows: unknown): TranscriptionJob {
  if (!Array.isArray(rows) || rows.length !== 1 || !isJob(rows[0])) throw new Error("Transcription job persistence returned an invalid record");
  return rows[0];
}

function isJob(value: unknown): value is TranscriptionJob {
  return isRecord(value)
    && typeof value.id === "string"
    && typeof value.backup_id === "string"
    && typeof value.owner_id === "string"
    && (value.state === "queued" || value.state === "processing" || value.state === "complete" || value.state === "failed")
    && (typeof value.provider_job_id === "string" || value.provider_job_id === null);
}

function withTrailingSlash(url: string): string { return url.endsWith("/") ? url : `${url}/`; }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
