import { describe, expect, it } from "vitest";
import { SpeechmaticsCallback } from "../src/speechmatics-callback";

const providerJobID = "provider-job";
const job = { id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", provider_job_id: providerJobID, provider_reference: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", state: "processing" as const };

describe("SpeechmaticsCallback", () => {
  it("accepts an authenticated metadata-only success callback", async () => {
    const dependencies = new Fakes();
    const response = await callback(dependencies).handle(new Request(`https://worker.example.test/v1/transcription-callback?id=${providerJobID}&status=success`, { method: "POST", headers: { Authorization: "Bearer callback-token" } }));
    expect(response.status).toBe(204);
    expect(dependencies.messages).toEqual([{ kind: "ingest", transcription_job_id: job.id }]);
  });

  it("queues duplicate accepted callbacks safely", async () => {
    const dependencies = new Fakes();
    const request = () => new Request(`https://worker.example.test/v1/transcription-callback?id=${providerJobID}&status=success`, { method: "POST", headers: { Authorization: "Bearer callback-token" } });
    await callback(dependencies).handle(request());
    await callback(dependencies).handle(request());
    expect(dependencies.messages).toEqual([{ kind: "ingest", transcription_job_id: job.id }, { kind: "ingest", transcription_job_id: job.id }]);
  });

  it.each([
    ["missing bearer", new Request(`https://worker.example.test/v1/transcription-callback?id=${providerJobID}&status=success`, { method: "POST" })],
    ["failed status", new Request(`https://worker.example.test/v1/transcription-callback?id=${providerJobID}&status=error`, { method: "POST", headers: { Authorization: "Bearer callback-token" } })],
    ["malformed provider job ID", new Request("https://worker.example.test/v1/transcription-callback?id=bad%20id&status=success", { method: "POST", headers: { Authorization: "Bearer callback-token" } })],
    ["body payload", new Request(`https://worker.example.test/v1/transcription-callback?id=${providerJobID}&status=success`, { method: "POST", headers: { Authorization: "Bearer callback-token" }, body: "not persisted" })]
  ])("rejects %s", async (_name, request) => {
    const dependencies = new Fakes();
    expect((await callback(dependencies).handle(request)).status).toBeGreaterThanOrEqual(400);
    expect(dependencies.messages).toEqual([]);
  });
});

function callback(fakes: Fakes) { return new SpeechmaticsCallback({ bearerToken: "callback-token", jobs: fakes.jobs, queue: { send: async (message) => { fakes.messages.push(message); } } }); }
class Fakes {
  messages: { kind: "ingest"; transcription_job_id: string }[] = [];
  jobs = { processingJob: async () => job, job: async () => job, complete: async () => undefined };
}
