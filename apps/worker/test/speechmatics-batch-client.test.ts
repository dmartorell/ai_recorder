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
      callbackURL: "https://worker.example.test/v1/transcription-callbacks/opaque-callback",
      language: "spanish_english",
      reference: "stable-job-reference"
    })).resolves.toBe("provider-job");

    expect(request?.headers.get("Authorization")).toBe("Bearer test-key");
    await expect(request?.json()).resolves.toEqual({
      type: "transcription",
      fetch_data: { url: "https://worker.example.test/v1/transcription-source/opaque-capability" },
      transcription_config: { model: "melia-1", language: "multi", language_hints: ["es", "en"], diarization: "speaker" },
      notification_config: [{ url: "https://worker.example.test/v1/transcription-callbacks/opaque-callback", contents: ["jobinfo"], method: "post" }],
      tracking: { reference: "stable-job-reference" }
    });
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

    await client.submit({ sourceURL: "https://worker.example.test/source", callbackURL: "https://worker.example.test/callback", language, reference: "reference" });
    await expect(request?.json()).resolves.toMatchObject({ transcription_config: transcriptionConfig });
  });
});
