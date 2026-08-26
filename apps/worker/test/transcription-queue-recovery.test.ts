import { describe, expect, it, vi } from "vitest";
import { handleTranscriptionQueue } from "../src/transcription-queue";

type QueueMessage = { kind: "submit" | "ingest" | "cleanup"; transcription_job_id: string };

function message(kind: QueueMessage["kind"], attempts: number) {
  const retry = vi.fn();
  const ack = vi.fn();
  return { body: { kind, transcription_job_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" }, attempts, retry, ack };
}

describe("transcription queue recovery", () => {
  it("retries a transient ingestion error twice with the configured delay", async () => {
    const item = message("ingest", 1);
    const failures: unknown[] = [];
    await handleTranscriptionQueue([item], {
      submitter: { submit: async () => undefined },
      ingester: { ingest: async () => { throw new Error("transient"); } },
      cleanup: { cleanup: async () => undefined },
      recovery: { failTranscriptionAttempt: async (jobID: string, phase: string) => { failures.push({ jobID, phase }); }, failProviderCleanup: async () => undefined }
    });
    expect(failures).toEqual([{ jobID: item.body.transcription_job_id, phase: "ingest" }]);
    expect(item.retry).toHaveBeenCalledWith({ delaySeconds: 60 });
    expect(item.ack).not.toHaveBeenCalled();
  });

  it("records and acknowledges the third submission failure", async () => {
    const item = message("submit", 3);
    const failures: unknown[] = [];
    await handleTranscriptionQueue([item], {
      submitter: { submit: async () => { throw new Error("transient"); } },
      ingester: { ingest: async () => undefined },
      cleanup: { cleanup: async () => undefined },
      recovery: { failTranscriptionAttempt: async (jobID: string, phase: string) => { failures.push({ jobID, phase }); }, failProviderCleanup: async () => undefined }
    });
    expect(failures).toEqual([{ jobID: item.body.transcription_job_id, phase: "submit" }]);
    expect(item.ack).toHaveBeenCalledTimes(1);
  });

  it("retains transcription completion when cleanup exhausts retries", async () => {
    const item = message("cleanup", 3);
    await handleTranscriptionQueue([item], {
      submitter: { submit: async () => undefined },
      ingester: { ingest: async () => undefined },
      cleanup: { cleanup: async () => { throw new Error("transient"); } },
      recovery: { failTranscriptionAttempt: async () => undefined }
    });
    expect(item.ack).toHaveBeenCalledTimes(1);
  });
});
