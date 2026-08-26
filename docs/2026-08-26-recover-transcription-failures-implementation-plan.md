# Recover Transcription Failures and Provider Cleanup Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bound recoverable transcription work, expose terminal transcription failure with an owner-initiated retry, and delete Speechmatics data after a preserved Automatic Transcript without allowing cleanup failure to change transcription completion.

**Architecture:** Keep `transcription_jobs` as the durable state machine. Queue messages remain opaque job UUIDs, carry one phase (`submit`, `ingest`, or `cleanup`), and use Cloudflare Queue delivery attempts for a maximum of three automatic attempts; on the final failed delivery, an internal RPC records the terminal state instead of silently dropping the message. The existing stable provider reference reconciles an uncertain submission before another provider job is made; successful ingestion atomically changes transcription to `complete` and provider cleanup to `pending`, then a distinct cleanup message deletes the remote job. Cleanup retries and its terminal pending state never modify the preserved Automatic Transcript or `transcription_jobs.state = complete`.

**Tech Stack:** Cloudflare Workers and Queues, private R2, Speechmatics Batch API, Supabase Postgres/RLS/pgTAP, TypeScript/Vitest, Swift 6/SwiftUI/XCTest.

---

## File structure

| Path | Responsibility |
| --- | --- |
| `supabase/migrations/<timestamp>_recover_transcription_failures.sql` | Durable retry/terminal/cleanup state plus service-role-only transitions. |
| `supabase/tests/audio_backups_rls.test.sql` | pgTAP proof of retry transitions, owner visibility, explicit retry, and preservation of completed transcript state through cleanup failure. |
| `apps/worker/src/transcription-recovery-store.ts` | Narrow Worker-facing persistence interface for terminal failures, explicit retry, and cleanup transitions. |
| `apps/worker/src/transcription-ingester.ts` | Enqueue cleanup only after the ingestion RPC has committed a complete transcript. |
| `apps/worker/src/speechmatics-batch-client.ts` | Delete one provider job without exposing identifiers or response bodies. |
| `apps/worker/src/index.ts` | Explicit phase dispatch, bounded Queue retry/ack logic, and provider cleanup orchestration. |
| `apps/worker/src/cloud-backup.ts` | Owner-authorized explicit retry endpoint that reuses verified cloud Original Audio and queues the correct phase. |
| `apps/worker/src/supabase-transcription-job-store.ts` | Read terminal state needed by the authorized endpoint and invoke the retry RPC. |
| `apps/worker/test/*transcription*.test.ts` | Unit coverage for phase retry bounds, idempotency, cleanup behavior, client calls, persistence adapters, and retry HTTP authorization. |
| `apps/worker/wrangler.jsonc` | Explicit Queue retry limit and retry delay matching the application bound. |
| `apps/ios/AIRecorder/CloudBackup/{CloudBackupCoordinator.swift,WorkerCloudBackupClient.swift}` | Authorized retry client seam and state refresh after retry. |
| `apps/ios/AIRecorder/Features/AudioDetail/AudioDetailView.swift` | Accessible `Retry transcription` control shown only when transcription is failed. |
| `apps/ios/AIRecorderTests/Features/{CloudBackupCoordinatorTests.swift,WorkerCloudBackupClientTests.swift}` | iOS retry request and state-refresh tests. |
| `docs/testing/cloud-backup-validation.md` | Secret-safe staging and synthetic-only validation of terminal failures, recovery, and cleanup. |

### Task 1: Add durable recovery and cleanup transitions

**Files:**
- Create: `supabase/migrations/<timestamp>_recover_transcription_failures.sql`
- Modify: `supabase/tests/audio_backups_rls.test.sql`

- [ ] **Step 1: Write failing pgTAP assertions for the state machine.**

  Add synthetic-only fixtures and assertions which show all of the following:

  ```sql
  select results_eq(
    $$ select state from public.fail_transcription_attempt(
         (select id from public.transcription_jobs
          where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
         'submit'
       ) $$,
    array['queued'],
    'the first transient submission failure remains retryable'
  );

  select results_eq(
    $$ select state from public.fail_transcription_attempt(
         (select id from public.transcription_jobs
          where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
         'submit'
       ) $$,
    array['queued'],
    'the second transient submission failure remains retryable'
  );

  select results_eq(
    $$ select state from public.fail_transcription_attempt(
         (select id from public.transcription_jobs
          where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
         'submit'
       ) $$,
    array['failed'],
    'the third submission failure is terminal'
  );

  select results_eq(
    $$ select state || ':' || coalesce(provider_job_id, '')
       from public.retry_failed_transcription(
         (select id from public.transcription_jobs
          where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')
       ) $$,
    array['queued:'],
    'an explicit retry resets a failed pre-submission job without changing its backup'
  );
  ```

  Also cover: a processing job reaches `failed` after its third ingestion failure without inserting a second `automatic_transcripts` row; `complete_transcription_ingestion` produces `state = 'complete'` and `provider_cleanup_state = 'pending'`; two cleanup failures retain `pending`; the third produces cleanup state `failed`; cleanup state `failed` retains the completed Automatic Transcript; only the owner can read the failed state; authenticated users cannot call the new RPCs.

- [ ] **Step 2: Run the focused database test to verify the new transition functions do not exist.**

  Run:

  ```sh
  supabase test db --local supabase/tests/audio_backups_rls.test.sql
  ```

  Expected: FAIL because the recovery and cleanup functions are undefined.

- [ ] **Step 3: Add the migration with checked fields and locked service-role transitions.**

  Create the migration through `supabase migration new recover_transcription_failures`, then implement these database rules:

  ```sql
  alter table public.transcription_jobs
    add column attempt_phase text check (attempt_phase in ('submit', 'ingest')),
    add column attempt_count integer not null default 0 check (attempt_count between 0 and 3),
    add column failed_at timestamptz,
    add column provider_cleanup_state text not null default 'not_started'
      check (provider_cleanup_state in ('not_started', 'pending', 'complete', 'failed')),
    add column provider_cleanup_attempt_count integer not null default 0
      check (provider_cleanup_attempt_count between 0 and 3),
    add column provider_cleanup_failed_at timestamptz;
  ```

  Implement locked, pinned-search-path `SECURITY DEFINER` functions granted only to `service_role`:

  - `fail_transcription_attempt(p_job_id uuid, p_phase text)` increments the matching phase counter only while the job is active. Attempts one and two preserve `queued` (`submit`) or `processing` (`ingest`); attempt three changes `state` to `failed`, clears any stale submission claim, and timestamps `failed_at`. It never stores the provider error body or transcript content.
  - `retry_failed_transcription(p_job_id uuid)` locks a failed job, resets the relevant counter and `failed_at`, and returns it to `queued` when it has no provider job or `processing` when a provider job already exists. It does not change `backup_id`, `owner_id`, `provider_reference`, Original Audio, or any Automatic Transcript. Reject non-failed and complete jobs.
  - `claim_provider_cleanup(p_job_id uuid)` returns only a complete job whose cleanup state is `pending` and atomically establishes a cleanup claim so duplicate cleanup delivery performs at most one request at a time.
  - `complete_provider_cleanup(p_job_id uuid, p_claim uuid)` marks cleanup complete only for its claim. `fail_provider_cleanup(p_job_id uuid, p_claim uuid)` clears its claim, increments its independent counter, and leaves cleanup pending for attempts one and two or records cleanup failed at attempt three. Neither function changes the transcription state.

  Amend `complete_transcription_ingestion` so its existing transaction sets `provider_cleanup_state = 'pending'` with the transcription `state = 'complete'`. Preserve its same-artifact duplicate path without resetting or regressing cleanup state.

- [ ] **Step 4: Run pgTAP and inspect privilege coverage.**

  Run:

  ```sh
  supabase test db --local supabase/tests/audio_backups_rls.test.sql
  ```

  Expected: PASS with the updated assertion count; all fixtures roll back.

- [ ] **Step 5: Commit the database state machine.**

  ```sh
  git add supabase/migrations supabase/tests/audio_backups_rls.test.sql
  git commit -m "feat: persist transcription recovery state"
  ```

### Task 2: Make provider client and ingestion cleanup-capable

**Files:**
- Modify: `apps/worker/src/speechmatics-batch-client.ts`
- Modify: `apps/worker/src/transcription-ingester.ts`
- Create: `apps/worker/src/transcription-recovery-store.ts`
- Modify: `apps/worker/src/supabase-transcription-ingestion-store.ts`
- Create: `apps/worker/test/transcription-recovery-store.test.ts`
- Modify: `apps/worker/test/speechmatics-batch-client.test.ts`
- Modify: `apps/worker/test/transcription-ingester.test.ts`
- Modify: `apps/worker/test/supabase-transcription-ingestion-store.test.ts`

- [ ] **Step 1: Write failing Worker tests for the cleanup seam.**

  Add tests that require these observable interactions:

  ```ts
  await ingester.ingest(job.id);
  expect(queue.messages).toEqual([{ kind: "cleanup", transcription_job_id: job.id }]);

  await cleanup.delete(job.id);
  expect(provider.deleted).toEqual([job.provider_job_id]);
  expect(store.completedClaims).toEqual([claim]);
  ```

  Include duplicate post-ingestion delivery (one immutable artifact/projection and safely repeatable cleanup enqueue), provider `DELETE` success, `404`/`410` interpreted as already deleted, and rejection of non-success/non-already-deleted responses without including the provider response body in an error.

- [ ] **Step 2: Run the focused tests to verify they fail.**

  Run:

  ```sh
  cd apps/worker && npm test -- transcription-ingester speechmatics-batch-client transcription-recovery-store supabase-transcription-ingestion-store
  ```

  Expected: FAIL because cleanup interfaces and behavior are absent.

- [ ] **Step 3: Extend the injected interfaces without leaking provider data.**

  Add `deleteJob(providerJobID: string): Promise<"deleted" | "already_deleted">` to `SpeechmaticsClient`. In `SpeechmaticsBatchClient`, issue `DELETE https://asr.api.speechmatics.com/v2/jobs/${encodeURIComponent(providerJobID)}` using the existing server-held authorization header. Return `already_deleted` for `404` and `410`; otherwise accept only successful deletion. Do not parse, log, return, or interpolate a response body, provider ID, API key, URL, or transcript.

  Define `TranscriptionRecoveryStore` with typed methods matching the Task 1 RPCs. Its cleanup claim result contains only opaque job ID, opaque claim ID, and provider job ID. Implement a Supabase REST adapter that sends only the required opaque values to the service-role RPC paths and validates every returned record.

- [ ] **Step 4: Queue cleanup strictly after preservation.**

  Extend `TranscriptionIngester` with an injected queue interface and send:

  ```ts
  await this.dependencies.jobs.complete(job.id, artifactKey, transcript);
  await this.dependencies.queue.send({ kind: "cleanup", transcription_job_id: job.id });
  ```

  Keep the queue message opaque. If queue publication fails after database completion, surface the error so its ingest delivery is retried; the duplicate ingestion branch must also enqueue cleanup when its durable cleanup state remains pending. Do not delete the artifact, projection, or Original Audio on any cleanup outcome.

- [ ] **Step 5: Run focused Worker tests.**

  Run:

  ```sh
  cd apps/worker && npm test -- transcription-ingester speechmatics-batch-client transcription-recovery-store supabase-transcription-ingestion-store
  ```

  Expected: PASS.

- [ ] **Step 6: Commit the cleanup seams.**

  ```sh
  git add apps/worker/src apps/worker/test
  git commit -m "feat: clean up preserved provider transcripts"
  ```

### Task 3: Bound queue work and provide owner-authorized retry

**Files:**
- Modify: `apps/worker/src/index.ts`
- Modify: `apps/worker/src/cloud-backup.ts`
- Modify: `apps/worker/src/speechmatics-callback.ts`
- Modify: `apps/worker/src/supabase-transcription-job-store.ts`
- Modify: `apps/worker/wrangler.jsonc`
- Modify: `apps/worker/test/transcription-jobs.test.ts`
- Modify: `apps/worker/test/speechmatics-callback.test.ts`
- Create: `apps/worker/test/transcription-queue-recovery.test.ts`
- Modify: `apps/worker/test/supabase-transcription-submission-store.test.ts`

- [ ] **Step 1: Write failing queue and HTTP tests.**

  Test all phase outcomes through fakes, including:

  ```ts
  expect(retry).toHaveBeenCalledWith({ delaySeconds: 60 }); // attempts 1 and 2
  expect(failures).toEqual([{ jobID, phase: "ingest" }]);  // attempt 3
  expect(ack).toHaveBeenCalledTimes(1);                     // terminal message is not dropped silently
  ```

  Cover transient submission, ingestion/retrieval, and cleanup errors; successful phase acknowledgements; unknown messages acknowledged; final submission/ingestion failures becoming terminal; final cleanup failure retaining `complete`; and an uncertain submission that calls `findByReference` before a second `submit`. Add callback tests showing a valid terminal provider failure status records the processing job as failed without queuing ingestion, while a Queue-send error from a valid success notification is allowed to fail the callback request so Speechmatics can redeliver it.

  Add HTTP tests for `POST /v1/audio-backups/:backupID/transcription/retry`: `401` when unauthenticated, `404` for another owner or absent backup, `409` for a nonfailed job, and `204` plus one opaque `ingest` message when retrying a failed job that already has a provider job (otherwise one `submit` message). Assert no backup begin/upload endpoint is called.

- [ ] **Step 2: Run the focused Worker tests to verify failure.**

  Run:

  ```sh
  cd apps/worker && npm test -- transcription-queue-recovery transcription-jobs transcription-submitter
  ```

  Expected: FAIL because cleanup dispatch, bounded terminal handling, and the retry endpoint do not exist.

- [ ] **Step 3: Add explicit phase dispatch and bounded retries in `index.ts`.**

  Extend the union exactly as follows:

  ```ts
  type TranscriptionQueueMessage =
    | { kind: "submit"; transcription_job_id: string }
    | { kind: "ingest"; transcription_job_id: string }
    | { kind: "cleanup"; transcription_job_id: string };
  ```

  Use a single phase dispatcher with injected/orchestrated submitter, ingester, cleanup service, and recovery store. On an exception from `submit` or `ingest`, call `message.retry({ delaySeconds: 60 })` for delivery attempts below three. On the third, call `failTranscriptionAttempt(jobID, phase)`, then `message.ack()`. For cleanup, use the equivalent independent cleanup-failure transition and acknowledge after terminal cleanup failure. Catch only to perform these transitions; do not log caught errors or message/provider/transcript fields.

  Configure the Worker consumer explicitly with `max_retries: 3` and `retry_delay: 60`, so an infrastructure retry cannot outlive the same documented automatic bound. Continue using `max_batch_size: 1`.

- [ ] **Step 4: Add the retry route without weakening ownership.**

  Extend `TranscriptionJobStore` with a service-role `retryFailed(ownerID, backupID)` call which first constrains the read by both owner and backup, then calls the Task 1 RPC with the resolved opaque job ID. In `cloud-backup.ts`, recognize only an owner-authenticated `POST .../transcription/retry`, choose `ingest` when `provider_job_id` exists and `submit` otherwise, enqueue one opaque message, and return `204`. A failed job reuses its backed-up Original Audio and never begins another upload.

  Extend `SpeechmaticsCallback` with a service-role failure transition: accept authenticated metadata-only terminal provider failure notifications for a syntactically valid provider job, resolve only that processing job, mark it failed without recording provider error text, and return `204`. Preserve the existing `success` path; if `queue.send` fails, let the callback return an error rather than acknowledging an ingestion notification that was never queued.

- [ ] **Step 5: Run focused checks.**

  Run:

  ```sh
  cd apps/worker
  npm run check
  npm test -- transcription-queue-recovery transcription-jobs transcription-submitter
  ```

  Expected: PASS.

- [ ] **Step 6: Commit bounded orchestration.**

  ```sh
  git add apps/worker/src apps/worker/test apps/worker/wrangler.jsonc
  git commit -m "feat: recover bounded transcription work"
  ```

### Task 4: Expose and trigger explicit retry in the iPhone app

**Files:**
- Modify: `apps/ios/AIRecorder/CloudBackup/CloudBackupCoordinator.swift`
- Modify: `apps/ios/AIRecorder/CloudBackup/WorkerCloudBackupClient.swift`
- Modify: `apps/ios/AIRecorder/Features/AudioDetail/AudioDetailView.swift`
- Modify: `apps/ios/AIRecorderTests/Features/CloudBackupCoordinatorTests.swift`
- Modify: `apps/ios/AIRecorderTests/Features/WorkerCloudBackupClientTests.swift`

- [ ] **Step 1: Write failing iOS tests for retry behavior.**

  Add a `CloudBackupCoordinatorTests` case with a backed-up item whose transcription is `.failed`; call `retryTranscription(for:)` and assert the fake client received its existing cloud backup UUID and the item refreshes to `.processing` (or the server-returned current state) without changing `cloudBackupState` or deleting the local file. Add a `WorkerCloudBackupClientTests` case that verifies:

  ```swift
  XCTAssertEqual(transport.request?.httpMethod, "POST")
  XCTAssertEqual(transport.request?.url?.path,
                 "/v1/audio-backups/\(backupID.uuidString)/transcription/retry")
  ```

- [ ] **Step 2: Run the focused tests to verify failure.**

  Run:

  ```sh
  xcodebuild test -project apps/ios/AIRecorder.xcodeproj -scheme AIRecorder -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AIRecorderTests/CloudBackupCoordinatorTests -only-testing:AIRecorderTests/WorkerCloudBackupClientTests
  ```

  Expected: FAIL because `retryTranscription` and the retry request are undefined.

- [ ] **Step 3: Implement the client and coordinator seam.**

  Add `retryTranscription(id: UUID) async throws` to `CloudBackupClient`, `UnavailableCloudBackupClient`, `WorkerCloudBackupClient`, and the test fake. In the coordinator, guard `.backedUp`, an existing backup ID, and `.failed`; call the endpoint, then call `refreshTranscriptionStatus(for:)`. Route errors through the existing user-visible `CloudBackupErrorMessage` path without misrepresenting a transcript as backup state.

- [ ] **Step 4: Add the accessible detail action.**

  In `CloudBackupSection`, render only when `item.transcriptionState == .failed`:

  ```swift
  Button("Retry transcription") {
      Task { await coordinator.retryTranscription(for: item) }
  }
  .accessibilityHint("Retries transcription from the verified cloud audio without uploading the Original Audio again.")
  .accessibilityIdentifier("transcription-retry")
  ```

  Keep the existing separate local-audio, cloud-audio, transcription, and summary labels. Do not add transcript display, editing, analysis, or provider-cleanup UI.

- [ ] **Step 5: Run focused iOS tests.**

  Run the Step 2 command again.

  Expected: PASS.

- [ ] **Step 6: Commit iOS retry.**

  ```sh
  git add apps/ios/AIRecorder apps/ios/AIRecorderTests
  git commit -m "feat: retry failed transcription"
  ```

### Task 5: Validate end-to-end safeguards and document operations

**Files:**
- Modify: `docs/testing/cloud-backup-validation.md`

- [ ] **Step 1: Document synthetic-only staging checks.**

  Add a section that records only pass/fail and HTTP status for: two transient submission errors followed by reconciliation and one provider job; terminal submission/ingestion failure after three deliveries; owner-only explicit retry without a new multipart upload; one completed immutable artifact/projection; provider deletion success; and cleanup retries that leave transcription complete when deletion remains pending/failed. State that provider IDs, provider responses, transcript text, object keys, signed URLs, and secrets must not be retained in commands, logs, evidence, or issue comments.

- [ ] **Step 2: Run the Worker suite and static check.**

  Run:

  ```sh
  cd apps/worker && npm run check && npm test
  git diff --check
  ```

  Expected: PASS with no whitespace errors.

- [ ] **Step 3: Run database and iOS suites.**

  Run the focused pgTAP command from Task 1, then:

  ```sh
  xcodebuild test -project apps/ios/AIRecorder.xcodeproj -scheme AIRecorder -destination 'platform=iOS Simulator,name=iPhone 16'
  ```

  Expected: PASS. If the named simulator is absent, select an installed iOS simulator and record the replacement only in local execution output, not product documentation.

- [ ] **Step 4: Perform a privacy review before commit.**

  Run:

  ```sh
  rg -n -i 'console\.|logger|provider_job_id|sourceURL|callback-token|automatic-transcripts/' apps/worker/src apps/worker/test docs/testing
  git diff --check
  ```

  Review every match: production errors and logs must not expose provider IDs, Original Audio, transcript content, signed URLs, object keys, callback tokens, API keys, or service-role credentials. Minimal synthetic test fixtures may contain compact fake values only.

- [ ] **Step 5: Commit validation documentation.**

  ```sh
  git add docs/testing/cloud-backup-validation.md
  git commit -m "docs: validate transcription recovery"
  ```

## Self-review

- **Spec coverage:** Task 3 covers bounded transient submission, notification/queue delivery, retrieval, and ingestion handling; stable-reference reconciliation remains in `TranscriptionSubmitter` and is explicitly regression-tested. Tasks 1 and 3 expose terminal failure and owner-authorized retry without a backup re-upload. Tasks 1–3 make provider cleanup follow successful ingestion, retry independently, and leave `complete` unchanged. Tasks 1–5 provide database, Worker, iOS, and privacy/no-content-log validation.
- **Scope:** The plan does not add web workflows, transcript UI, analysis, local deletion, public R2, provider credentials in clients, automatic local deletion, or a waveform.
- **Type consistency:** Queue kinds are `submit`, `ingest`, and `cleanup`; automatic delivery limit is three; database cleanup values are `not_started`, `pending`, `complete`, and `failed`; iOS only consumes the existing transcription `failed` state and calls the owner-authorized retry endpoint.
- **Placeholder scan:** Every implementation step names its files, expected behavior, and verification command. Migration timestamps are intentionally generated by `supabase migration new` rather than invented.
