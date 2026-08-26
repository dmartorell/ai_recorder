import { describe, expect, it } from "vitest";
import { ProviderCleanupService, SupabaseTranscriptionRecoveryStore } from "../src/transcription-recovery-store";

const claim = {
  transcription_job_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  provider_cleanup_claim: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  provider_job_id: "provider-job"
};

describe("ProviderCleanupService", () => {
  it("deletes a claimed provider job then completes its claim", async () => {
    const store = new CleanupStore(claim);
    const provider = { deleted: [] as string[], deleteJob: async (id: string) => { provider.deleted.push(id); return "deleted" as const; } };

    await new ProviderCleanupService({ store, provider }).cleanup(claim.transcription_job_id);

    expect(provider.deleted).toEqual([claim.provider_job_id]);
    expect(store.completedClaims).toEqual([claim.provider_cleanup_claim]);
  });

  it("does nothing when cleanup was already claimed or completed", async () => {
    const store = new CleanupStore(undefined);
    const provider = { deleteJob: async () => "deleted" as const };
    await new ProviderCleanupService({ store, provider }).cleanup(claim.transcription_job_id);
    expect(store.completedClaims).toEqual([]);
  });
});

describe("SupabaseTranscriptionRecoveryStore", () => {
  it("sends only opaque cleanup claim values to service-role RPCs", async () => {
    let request: Request | undefined;
    const store = new SupabaseTranscriptionRecoveryStore({
      supabaseURL: "https://project.supabase.co", serviceRoleKey: "service-role-key",
      fetch: async (input, init) => { request = new Request(input, init); return Response.json([claim]); }
    });

    await expect(store.claimProviderCleanup(claim.transcription_job_id)).resolves.toEqual(claim);
    expect(request?.url).toBe("https://project.supabase.co/rest/v1/rpc/claim_provider_cleanup");
    await expect(request?.json()).resolves.toEqual({ p_job_id: claim.transcription_job_id });
  });
});

class CleanupStore {
  completedClaims: string[] = [];
  constructor(private readonly claim: typeof claim | undefined) {}
  async failTranscriptionAttempt() { return { id: claim.transcription_job_id, state: "failed" as const, provider_job_id: null }; }
  async retryFailedTranscription() { return { id: claim.transcription_job_id, state: "queued" as const, provider_job_id: null }; }
  async claimProviderCleanup() { return this.claim; }
  async completeProviderCleanup(_jobID: string, claimID: string) { this.completedClaims.push(claimID); }
  async failProviderCleanup() {}
}
