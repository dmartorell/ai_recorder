import { createDefaultWorker } from "./cloud-backup";
import { R2MultipartGateway } from "./r2-multipart";

export default {
  fetch(request, env, context) {
    const multipart = env.R2_ACCESS_KEY_ID && env.R2_SECRET_ACCESS_KEY && env.R2_BUCKET_NAME && env.R2_ACCOUNT_ID && env.ORIGINAL_AUDIO
      ? new R2MultipartGateway({
          bucket: env.R2_BUCKET_NAME,
          accountID: env.R2_ACCOUNT_ID,
          accessKeyID: env.R2_ACCESS_KEY_ID,
          secretAccessKey: env.R2_SECRET_ACCESS_KEY,
          r2: env.ORIGINAL_AUDIO
        })
      : undefined;
    return createDefaultWorker(env.SUPABASE_URL ?? "https://unconfigured.invalid", env.SUPABASE_SERVICE_ROLE_KEY, multipart, env.TRANSCRIPTION_JOBS).fetch!(request, env, context);
  }
} satisfies ExportedHandler<Env>;
