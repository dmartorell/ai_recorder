import { createDefaultWorker } from "./cloud-backup";
import { R2MultipartGateway } from "./r2-multipart";
import { SpeechmaticsBatchClient } from "./speechmatics-batch-client";
import { SupabaseTranscriptionSubmissionStore } from "./supabase-transcription-submission-store";
import { TranscriptionSubmitter } from "./transcription-submitter";

export default {
  fetch(request, env, context) {
    const multipart = gateway(env);
    return createDefaultWorker(env.SUPABASE_URL ?? "https://unconfigured.invalid", env.SUPABASE_SERVICE_ROLE_KEY, multipart, env.TRANSCRIPTION_JOBS).fetch!(request, env, context);
  },
  async queue(batch, env) {
    const multipart = gateway(env);
    if (!multipart || !env.SUPABASE_SERVICE_ROLE_KEY || !env.SPEECHMATICS_API_KEY) {
      for (const message of batch.messages) message.retry();
      return;
    }
    const submitter = new TranscriptionSubmitter({
      jobs: new SupabaseTranscriptionSubmissionStore({ supabaseURL: env.SUPABASE_URL ?? "https://unconfigured.invalid", serviceRoleKey: env.SUPABASE_SERVICE_ROLE_KEY }),
      source: multipart,
      provider: new SpeechmaticsBatchClient({ apiKey: env.SPEECHMATICS_API_KEY })
    });
    for (const message of batch.messages) {
      const body = message.body as { transcription_job_id?: unknown };
      if (typeof body?.transcription_job_id !== "string") { message.ack(); continue; }
      try { await submitter.submit(body.transcription_job_id); message.ack(); } catch { message.retry(); }
    }
  }
} satisfies ExportedHandler<Env>;

function gateway(env: Env): R2MultipartGateway | undefined {
  return env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY && env.R2_BUCKET_NAME && env.R2_ACCOUNT_ID && env.ORIGINAL_AUDIO
    ? new R2MultipartGateway({ bucket: env.R2_BUCKET_NAME, accountID: env.R2_ACCOUNT_ID, accessKeyID: env.R2_ACCESS_KEY_ID, secretAccessKey: env.R2_SECRET_ACCESS_KEY, r2: env.ORIGINAL_AUDIO })
    : undefined;
}
