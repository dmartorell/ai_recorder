import { describe, expect, it } from "vitest";
import { SupabaseTranscriptionIngestionStore } from "../src/supabase-transcription-ingestion-store";

const job = { id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", provider_job_id: "provider-job", provider_reference: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", state: "processing" };

describe("SupabaseTranscriptionIngestionStore", () => {
  it("resolves one processing job without exposing provider output", async () => {
    let request: Request | undefined;
    const store = new SupabaseTranscriptionIngestionStore({
      supabaseURL: "https://project.supabase.co", serviceRoleKey: "service-role-key",
      fetch: async (input, init) => { request = new Request(input, init); return Response.json([job]); }
    });
    await expect(store.processingJob(job.provider_job_id)).resolves.toEqual(job);
    expect(new URL(request!.url).searchParams.get("provider_job_id")).toBe(`eq.${job.provider_job_id}`);
  });

  it("sends the raw provider result only to the service-role RPC", async () => {
    let request: Request | undefined;
    const store = new SupabaseTranscriptionIngestionStore({
      supabaseURL: "https://project.supabase.co", serviceRoleKey: "service-role-key",
      fetch: async (input, init) => { request = new Request(input, init); return Response.json([job]); }
    });
    await store.complete(job.id, `automatic-transcripts/${job.id}.json`, { format: "2.9" });
    expect(request?.url).toBe("https://project.supabase.co/rest/v1/rpc/complete_transcription_ingestion");
    await expect(request?.json()).resolves.toMatchObject({ p_job_id: job.id });
  });
});
