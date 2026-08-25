import type { SpeechmaticsClient, SpeechmaticsSubmission, TranscriptionLanguage } from "./speechmatics-batch-client";

export interface SubmissionJob {
  id: string;
  backup_id: string;
  owner_id: string;
  state: "queued" | "processing" | "complete" | "failed";
  transcription_language: TranscriptionLanguage;
  provider_reference: string;
  provider_job_id: string | null;
  submission_claim: string | null;
}

export interface SubmissionJobStore {
  claimSubmission(jobID: string, claimID: string): Promise<SubmissionJob>;
  recordSubmission(jobID: string, providerJobID: string): Promise<SubmissionJob>;
  releaseSubmissionClaim(jobID: string, claimID: string): Promise<void>;
  backup(ownerID: string, backupID: string): Promise<{ object_key: string } | undefined>;
}

export interface PrivateAudioSource { signedReadURL(key: string): Promise<string>; }

export class TranscriptionSubmitter {
  constructor(private readonly dependencies: { jobs: SubmissionJobStore; source: PrivateAudioSource; provider: SpeechmaticsClient; callbackBaseURL: string; claimID?: () => string }) {}

  async submit(jobID: string): Promise<void> {
    const claimID = this.dependencies.claimID?.() ?? crypto.randomUUID();
    const job = await this.dependencies.jobs.claimSubmission(jobID, claimID);
    if (job.provider_job_id) return;

    let submission: SpeechmaticsSubmission;
    try {
      const existingProviderJobID = await this.dependencies.provider.findByReference(job.provider_reference);
      if (existingProviderJobID) {
        await this.dependencies.jobs.recordSubmission(job.id, existingProviderJobID);
        return;
      }
      if (job.submission_claim !== claimID) throw new Error("A transcription submission is unresolved");
      const backup = await this.dependencies.jobs.backup(job.owner_id, job.backup_id);
      if (!backup) throw new Error("Verified audio backup was not found");
      submission = {
        sourceURL: await this.dependencies.source.signedReadURL(backup.object_key),
        callbackURL: new URL(`/v1/transcription-callbacks/${job.provider_reference}`, this.dependencies.callbackBaseURL).toString(),
        language: job.transcription_language,
        reference: job.provider_reference
      };
    } catch (error) {
      if (job.submission_claim === claimID) await this.dependencies.jobs.releaseSubmissionClaim(job.id, claimID);
      throw error;
    }

    const providerJobID = await this.dependencies.provider.submit(submission);
    await this.dependencies.jobs.recordSubmission(job.id, providerJobID);
  }
}
