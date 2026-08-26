import { describe, expect, it } from "vitest";
import { SpeechmaticsBatchClient } from "../src/speechmatics-batch-client";

describe("SpeechmaticsBatchClient", () => {
  it("submits a diarized bilingual job using only the supplied scoped source URL", async () => {
    let request: Request | undefined;
    const client = new SpeechmaticsBatchClient({
      apiKey: "test-key",
      fetch: async (input, init) => {
        request = new Request(input, init);
        return Response.json({ id: "provider-job" }, { status: 201 });
      }
    });

    await expect(client.submit({
      sourceURL: "https://worker.example.test/v1/transcription-source/opaque-capability",
      language: "spanish_english",
      reference: "stable-job-reference"
    })).resolves.toBe("provider-job");

    expect(request?.headers.get("Authorization")).toBe("Bearer test-key");
    await expect(request?.json()).resolves.toEqual({
      type: "transcription",
      fetch_data: { url: "https://worker.example.test/v1/transcription-source/opaque-capability" },
      transcription_config: { model: "melia-1", language: "multi", language_hints: ["es", "en"], diarization: "speaker" },
      tracking: { reference: "stable-job-reference" }
    });
  });

  it("requests a metadata-only authenticated completion notification", async () => {
    let request: Request | undefined;
    const client = new SpeechmaticsBatchClient({ apiKey: "test-key", fetch: async (input, init) => {
      request = new Request(input, init);
      return Response.json({ id: "provider-job" }, { status: 201 });
    } });

    await client.submit({ sourceURL: "https://worker.example.test/source", language: "english", reference: "stable-reference", notification: { url: "https://worker.example.test/v1/transcription-callback", bearerToken: "callback-token" } });
    await expect(request?.json()).resolves.toMatchObject({
      notification_config: [{ url: "https://worker.example.test/v1/transcription-callback", auth_headers: ["Authorization: Bearer callback-token"] }]
    });
  });

  it("retrieves the JSON-v2 transcript server-side", async () => {
    let request: Request | undefined;
    const client = new SpeechmaticsBatchClient({ apiKey: "test-key", fetch: async (input, init) => {
      request = new Request(input, init);
      return Response.json({ format: "2.9" });
    } });
    await expect(client.transcript("provider/job")).resolves.toEqual({ format: "2.9" });
    expect(request?.url).toBe("https://asr.api.speechmatics.com/v2/jobs/provider%2Fjob/transcript");
  });

  it("deletes a provider job without parsing its response", async () => {
    let request: Request | undefined;
    const client = new SpeechmaticsBatchClient({ apiKey: "test-key", fetch: async (input, init) => {
      request = new Request(input, init);
      return new Response(null, { status: 204 });
    } });

    await expect(client.deleteJob("provider/job")).resolves.toBe("deleted");
    expect(request?.method).toBe("DELETE");
    expect(request?.url).toBe("https://asr.api.speechmatics.com/v2/jobs/provider%2Fjob");
  });

  it.each([404, 410])("treats deletion status %i as already deleted", async (status) => {
    const client = new SpeechmaticsBatchClient({ apiKey: "test-key", fetch: async () => new Response(null, { status }) });
    await expect(client.deleteJob("provider-job")).resolves.toBe("already_deleted");
  });

  it("rejects an unsuccessful provider deletion without exposing its response", async () => {
    const client = new SpeechmaticsBatchClient({ apiKey: "test-key", fetch: async () => new Response("sensitive provider response", { status: 500 }) });
    await expect(client.deleteJob("provider-job")).rejects.toThrow("Speechmatics job deletion failed");
  });

  it("finds a recent provider job by the stable tracking reference", async () => {
    const client = new SpeechmaticsBatchClient({
      apiKey: "test-key",
      fetch: async () => Response.json({ jobs: [
        { id: "unrelated", config: { tracking: { reference: "other" } } },
        { id: "provider-job", config: { tracking: { reference: "stable-reference" } } }
      ] })
    });

    await expect(client.findByReference("stable-reference")).resolves.toBe("provider-job");
  });

  it("rejects an ambiguous provider reconciliation", async () => {
    const client = new SpeechmaticsBatchClient({
      apiKey: "test-key",
      fetch: async () => Response.json({ jobs: [
        { id: "provider-job-1", config: { tracking: { reference: "stable-reference" } } },
        { id: "provider-job-2", config: { tracking: { reference: "stable-reference" } } }
      ] })
    });

    await expect(client.findByReference("stable-reference")).rejects.toThrow("duplicate");
  });

  it.each([
    ["spanish", { model: "melia-1", language: "es", diarization: "speaker" }],
    ["english", { model: "melia-1", language: "en", diarization: "speaker" }]
  ] as const)("configures %s with diarization", async (language, transcriptionConfig) => {
    let request: Request | undefined;
    const client = new SpeechmaticsBatchClient({ apiKey: "test-key", fetch: async (input, init) => {
      request = new Request(input, init);
      return Response.json({ id: "provider-job" }, { status: 201 });
    } });

    await client.submit({ sourceURL: "https://worker.example.test/source", language, reference: "reference" });
    await expect(request?.json()).resolves.toMatchObject({ transcription_config: transcriptionConfig });
  });
});
