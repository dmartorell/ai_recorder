import type { TranscriptionIngester } from "./transcription-ingester";
import type { TranscriptionRecoveryStore } from "./transcription-recovery-store";
import type { TranscriptionSubmitter } from "./transcription-submitter";

export type TranscriptionQueueMessage =
  | { kind: "submit"; transcription_job_id: string }
  | { kind: "ingest"; transcription_job_id: string }
  | { kind: "cleanup"; transcription_job_id: string };

type QueueMessage = { body: unknown; attempts: number; ack(): void; retry(options: { delaySeconds: number }): void };

export async function handleTranscriptionQueue(messages: readonly QueueMessage[], dependencies: {
  submitter: Pick<TranscriptionSubmitter, "submit">;
  ingester: Pick<TranscriptionIngester, "ingest">;
  cleanup: { cleanup(jobID: string): Promise<void> };
  recovery: Pick<TranscriptionRecoveryStore, "failTranscriptionAttempt">;
}): Promise<void> {
  for (const message of messages) {
    const body = message.body;
    if (!isMessage(body)) { message.ack(); continue; }
    try {
      if (body.kind === "submit") await dependencies.submitter.submit(body.transcription_job_id);
      else if (body.kind === "ingest") await dependencies.ingester.ingest(body.transcription_job_id);
      else if (body.kind === "cleanup") await dependencies.cleanup.cleanup(body.transcription_job_id);
      else { message.ack(); continue; }
      message.ack();
    } catch {
      if (body.kind !== "cleanup") await dependencies.recovery.failTranscriptionAttempt(body.transcription_job_id, body.kind);
      if (message.attempts < 3) { message.retry({ delaySeconds: 60 }); continue; }
      message.ack();
    }
  }
}

function isMessage(value: unknown): value is TranscriptionQueueMessage {
  if (typeof value !== "object" || value === null) return false;
  const candidate = value as Record<string, unknown>;
  return (candidate.kind === "submit" || candidate.kind === "ingest" || candidate.kind === "cleanup")
    && typeof candidate.transcription_job_id === "string";
}
