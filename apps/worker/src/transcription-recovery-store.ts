import type { SpeechmaticsClient } from "./speechmatics-batch-client";

export interface ProviderCleanupClaim {
  transcription_job_id: string;
  provider_cleanup_claim: string;
  provider_job_id: string;
}

export interface TranscriptionRecoveryJob {
  id: string;
  state: "queued" | "processing" | "complete" | "failed";
  provider_job_id: string | null;
}

export interface TranscriptionRecoveryStore {
  failTranscriptionAttempt(jobID: string, phase: "submit" | "ingest"): Promise<TranscriptionRecoveryJob>;
  retryFailedTranscription(jobID: string): Promise<TranscriptionRecoveryJob>;
  claimProviderCleanup(jobID: string): Promise<ProviderCleanupClaim | undefined>;
  completeProviderCleanup(jobID: string, claimID: string): Promise<void>;
  failProviderCleanup(jobID: string, claimID: string): Promise<void>;
}

export class ProviderCleanupService {
  constructor(private readonly dependencies: {
    store: TranscriptionRecoveryStore;
    provider: Pick<SpeechmaticsClient, "deleteJob">;
  }) {}

  async cleanup(jobID: string): Promise<void> {
    const claim = await this.dependencies.store.claimProviderCleanup(jobID);
    if (!claim) return;
    try {
      await this.dependencies.provider.deleteJob(claim.provider_job_id);
      await this.dependencies.store.completeProviderCleanup(claim.transcription_job_id, claim.provider_cleanup_claim);
    } catch (error) {
      await this.dependencies.store.failProviderCleanup(claim.transcription_job_id, claim.provider_cleanup_claim);
      throw error;
    }
  }
}

type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export class SupabaseTranscriptionRecoveryStore implements TranscriptionRecoveryStore {
  private readonly base: string;
  private readonly headers: HeadersInit;
  private readonly fetch: Fetch;

  constructor({ supabaseURL, serviceRoleKey, fetch = globalThis.fetch }: { supabaseURL: string; serviceRoleKey: string; fetch?: Fetch }) {
    this.base = supabaseURL.endsWith("/") ? supabaseURL : `${supabaseURL}/`;
    this.headers = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}`, "Content-Type": "application/json" };
    this.fetch = fetch;
  }

  async failTranscriptionAttempt(jobID: string, phase: "submit" | "ingest"): Promise<TranscriptionRecoveryJob> {
    return this.job("fail_transcription_attempt", { p_job_id: jobID, p_phase: phase });
  }

  async retryFailedTranscription(jobID: string): Promise<TranscriptionRecoveryJob> {
    return this.job("retry_failed_transcription", { p_job_id: jobID });
  }

  async claimProviderCleanup(jobID: string): Promise<ProviderCleanupClaim | undefined> {
    const rows = await this.rpc("claim_provider_cleanup", { p_job_id: jobID });
    if (rows.length === 0) return undefined;
    if (rows.length !== 1 || !isClaim(rows[0])) throw new Error("Invalid provider cleanup claim");
    return rows[0];
  }

  async completeProviderCleanup(jobID: string, claimID: string): Promise<void> {
    await this.expectJob("complete_provider_cleanup", { p_job_id: jobID, p_claim: claimID });
  }

  async failProviderCleanup(jobID: string, claimID: string): Promise<void> {
    await this.expectJob("fail_provider_cleanup", { p_job_id: jobID, p_claim: claimID });
  }

  private async expectJob(name: string, body: object): Promise<void> {
    await this.job(name, body);
  }

  private async job(name: string, body: object): Promise<TranscriptionRecoveryJob> {
    const rows = await this.rpc(name, body);
    if (rows.length !== 1 || !isJob(rows[0])) throw new Error("Invalid transcription recovery record");
    return rows[0];
  }

  private async rpc(name: string, body: object): Promise<unknown[]> {
    const response = await this.fetch(new URL(`rest/v1/rpc/${name}`, this.base), {
      method: "POST", headers: this.headers, body: JSON.stringify(body)
    });
    if (!response.ok) throw new Error("Could not persist transcription recovery");
    const rows: unknown = await response.json();
    if (!Array.isArray(rows)) throw new Error("Invalid transcription recovery record");
    return rows;
  }
}

function isJob(value: unknown): value is TranscriptionRecoveryJob {
  return isRecord(value) && typeof value.id === "string"
    && (value.state === "queued" || value.state === "processing" || value.state === "complete" || value.state === "failed")
    && (typeof value.provider_job_id === "string" || value.provider_job_id === null);
}
function isClaim(value: unknown): value is ProviderCleanupClaim {
  return isRecord(value) && typeof value.transcription_job_id === "string"
    && typeof value.provider_cleanup_claim === "string" && typeof value.provider_job_id === "string";
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
