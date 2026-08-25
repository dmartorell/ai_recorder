import { describe, expect, it } from "vitest";
import { SupabaseTranscriptionSubmissionStore } from "../src/supabase-transcription-submission-store";

const job = {
  id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
  backup_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
  owner_id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
  state: "queued",
  transcription_language: "spanish_english",
  provider_reference: "dddddddd-dddd-dddd-dddd-dddddddddddd",
  provider_job_id: null,
  submission_claim: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
};

describe("SupabaseTranscriptionSubmissionStore", () => {
  it("claims a submission with its opaque claim identifier", async () => {
    let request: Request | undefined;
    const store = new SupabaseTranscriptionSubmissionStore({
      supabaseURL: "https://project.supabase.co",
      serviceRoleKey: "service-role-key",
      fetch: async (input, init) => {
        request = new Request(input, init);
        return Response.json([job]);
      }
    });

    await expect(store.claimSubmission(job.id, job.submission_claim)).resolves.toEqual(job);
    expect(request?.url).toBe("https://project.supabase.co/rest/v1/rpc/claim_transcription_submission");
    await expect(request?.json()).resolves.toEqual({ p_job_id: job.id, p_submission_claim: job.submission_claim });
  });

  it("rejects malformed RPC results", async () => {
    const store = new SupabaseTranscriptionSubmissionStore({
      supabaseURL: "https://project.supabase.co",
      serviceRoleKey: "service-role-key",
      fetch: async () => Response.json([{ ...job, submission_claim: 1 }])
    });

    await expect(store.claimSubmission(job.id, job.submission_claim)).rejects.toThrow("invalid record");
  });

  it("reads only one owned backup object key", async () => {
    let request: Request | undefined;
    const store = new SupabaseTranscriptionSubmissionStore({
      supabaseURL: "https://project.supabase.co",
      serviceRoleKey: "service-role-key",
      fetch: async (input, init) => {
        request = new Request(input, init);
        return Response.json([{ object_key: "original-audio/opaque" }]);
      }
    });

    await expect(store.backup(job.owner_id, job.backup_id)).resolves.toEqual({ object_key: "original-audio/opaque" });
    let query = new URL(request!.url).searchParams;
    expect(query.get("id")).toBe(`eq.${job.backup_id}`);
    expect(query.get("owner_id")).toBe(`eq.${job.owner_id}`);
    expect(query.get("select")).toBe("object_key");
  });

  it("rejects malformed backup results instead of signing an unverified object", async () => {
    const store = new SupabaseTranscriptionSubmissionStore({
      supabaseURL: "https://project.supabase.co",
      serviceRoleKey: "service-role-key",
      fetch: async () => Response.json([{ object_key: 1 }])
    });

    await expect(store.backup(job.owner_id, job.backup_id)).resolves.toBeUndefined();
  });
});
