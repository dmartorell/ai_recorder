import type { SubmissionJob, SubmissionJobStore } from "./transcription-submitter";

type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class SupabaseTranscriptionSubmissionStore implements SubmissionJobStore {
  private readonly base: string;
  private readonly headers: HeadersInit;
  private readonly fetch: Fetch;
  constructor({ supabaseURL, serviceRoleKey, fetch = globalThis.fetch }: { supabaseURL: string; serviceRoleKey: string; fetch?: Fetch }) {
    this.base = supabaseURL.endsWith("/") ? supabaseURL : `${supabaseURL}/`;
    this.headers = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}`, "Content-Type": "application/json" };
    this.fetch = fetch;
  }
  async claimSubmission(jobID: string, claimID: string): Promise<SubmissionJob> { return this.rpc("claim_transcription_submission", { p_job_id: jobID, p_submission_claim: claimID }); }
  async recordSubmission(jobID: string, providerJobID: string): Promise<SubmissionJob> { return this.rpc("record_transcription_submission", { p_job_id: jobID, p_provider_job_id: providerJobID }); }
  async releaseSubmissionClaim(jobID: string, claimID: string): Promise<void> { await this.rpc("release_transcription_submission_claim", { p_job_id: jobID, p_submission_claim: claimID }); }
  async backup(ownerID: string, backupID: string): Promise<{ object_key: string } | undefined> {
    const url = new URL("rest/v1/audio_backups", this.base);
    url.search = new URLSearchParams({ id: `eq.${backupID}`, owner_id: `eq.${ownerID}`, select: "object_key" }).toString();
    const response = await this.fetch(url, { headers: this.headers });
    if (!response.ok) throw new Error("Could not read verified audio backup");
    const rows: unknown = await response.json();
    return Array.isArray(rows) && rows.length === 1 && isRecord(rows[0]) && typeof rows[0].object_key === "string" ? { object_key: rows[0].object_key } : undefined;
  }
  private async rpc(name: string, body: object): Promise<SubmissionJob> {
    const response = await this.fetch(new URL(`rest/v1/rpc/${name}`, this.base), { method: "POST", headers: this.headers, body: JSON.stringify(body) });
    if (!response.ok) throw new Error("Could not persist transcription submission");
    const rows: unknown = await response.json();
    if (!Array.isArray(rows) || rows.length !== 1 || !isJob(rows[0])) throw new Error("Transcription submission persistence returned an invalid record");
    return rows[0];
  }
}
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
function isJob(value: unknown): value is SubmissionJob { return isRecord(value) && typeof value.id === "string" && typeof value.backup_id === "string" && typeof value.owner_id === "string" && (value.state === "queued" || value.state === "processing" || value.state === "complete" || value.state === "failed") && (value.transcription_language === "spanish" || value.transcription_language === "english" || value.transcription_language === "spanish_english") && typeof value.provider_reference === "string" && (typeof value.provider_job_id === "string" || value.provider_job_id === null) && (typeof value.submission_claim === "string" || value.submission_claim === null); }
