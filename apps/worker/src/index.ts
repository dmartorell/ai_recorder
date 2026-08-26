import { createDefaultWorker } from "./cloud-backup";
import { R2MultipartGateway } from "./r2-multipart";
import { SpeechmaticsBatchClient } from "./speechmatics-batch-client";
import { SpeechmaticsCallback } from "./speechmatics-callback";
import { R2TranscriptArtifactStore, TranscriptionIngester } from "./transcription-ingester";
import { ProviderCleanupService, SupabaseTranscriptionRecoveryStore } from "./transcription-recovery-store";
import { handleTranscriptionQueue, type TranscriptionQueueMessage } from "./transcription-queue";
import { SupabaseTranscriptionIngestionStore } from "./supabase-transcription-ingestion-store";
import { SupabaseTranscriptionSubmissionStore } from "./supabase-transcription-submission-store";
import { TranscriptionSubmitter } from "./transcription-submitter";

export default {
  fetch(request, env, context) {
    const multipart = gateway(env);
    const ingestionStore = configuredIngestionStore(env);
    const callback = configuredCallback(env, ingestionStore);
    return createDefaultWorker(
      env.SUPABASE_URL ?? "https://unconfigured.invalid",
      env.SUPABASE_SERVICE_ROLE_KEY,
      multipart,
      env.TRANSCRIPTION_JOBS,
      callback
    ).fetch!(request, env, context);
  },
  async queue(batch, env) {
    const multipart = gateway(env);
    const ingestionStore = configuredIngestionStore(env);
    const notification = callbackConfiguration(env);
    const recovery = env.SUPABASE_SERVICE_ROLE_KEY
      ? new SupabaseTranscriptionRecoveryStore({ supabaseURL: env.SUPABASE_URL ?? "https://unconfigured.invalid", serviceRoleKey: env.SUPABASE_SERVICE_ROLE_KEY })
      : undefined;
    if (!multipart || !ingestionStore || !notification || !recovery) {
      for (const message of batch.messages) message.retry({ delaySeconds: 60 });
      return;
    }
    if (!env.SPEECHMATICS_API_KEY) {
      for (const message of batch.messages) {
        const body = message.body as Partial<TranscriptionQueueMessage>;
        if ((body.kind === "submit" || body.kind === "ingest") && typeof body.transcription_job_id === "string" && message.attempts >= 3) {
          await recovery.failTranscriptionAttempt(body.transcription_job_id, body.kind);
          message.ack();
        } else {
          message.retry({ delaySeconds: 60 });
        }
      }
      return;
    }
    const provider = new SpeechmaticsBatchClient({ apiKey: env.SPEECHMATICS_API_KEY });
    const submitter = new TranscriptionSubmitter({
      jobs: new SupabaseTranscriptionSubmissionStore({ supabaseURL: env.SUPABASE_URL ?? "https://unconfigured.invalid", serviceRoleKey: env.SUPABASE_SERVICE_ROLE_KEY }),
      source: multipart,
      provider,
      notification
    });
    const ingester = new TranscriptionIngester({
      jobs: ingestionStore,
      provider,
      artifacts: new R2TranscriptArtifactStore(env.ORIGINAL_AUDIO!),
      queue: env.TRANSCRIPTION_JOBS
    });
    const cleanup = new ProviderCleanupService({ store: recovery, provider });
    await handleTranscriptionQueue(batch.messages, { submitter, ingester, cleanup, recovery });
  }
} satisfies ExportedHandler<Env>;

function configuredIngestionStore(env: Env): SupabaseTranscriptionIngestionStore | undefined {
  return env.SUPABASE_SERVICE_ROLE_KEY
    ? new SupabaseTranscriptionIngestionStore({ supabaseURL: env.SUPABASE_URL ?? "https://unconfigured.invalid", serviceRoleKey: env.SUPABASE_SERVICE_ROLE_KEY })
    : undefined;
}

function configuredCallback(env: Env, jobs: SupabaseTranscriptionIngestionStore | undefined): SpeechmaticsCallback | undefined {
  const configuration = callbackConfiguration(env);
  return configuration && jobs && env.TRANSCRIPTION_JOBS
    ? new SpeechmaticsCallback({ bearerToken: configuration.bearerToken, jobs, queue: env.TRANSCRIPTION_JOBS })
    : undefined;
}

function callbackConfiguration(env: Env): { url: string; bearerToken: string } | undefined {
  if (!env.PUBLIC_WORKER_URL || !env.TRANSCRIPTION_CALLBACK_TOKEN) return undefined;
  return { url: new URL("/v1/transcription-callback", env.PUBLIC_WORKER_URL).toString(), bearerToken: env.TRANSCRIPTION_CALLBACK_TOKEN };
}

function gateway(env: Env): R2MultipartGateway | undefined {
  return env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY && env.R2_BUCKET_NAME && env.R2_ACCOUNT_ID && env.ORIGINAL_AUDIO
    ? new R2MultipartGateway({ bucket: env.R2_BUCKET_NAME, accountID: env.R2_ACCOUNT_ID, accessKeyID: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY, r2: env.ORIGINAL_AUDIO })
    : undefined;
}
