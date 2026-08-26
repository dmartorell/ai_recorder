# Ingest Automatic Transcripts Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Accept authenticated Speechmatics completion callbacks and atomically preserve each completed Automatic Transcript as a private immutable artifact and ownership-scoped editorial projection.

**Architecture:** The public Worker callback authenticates a metadata-only Speechmatics notification and sends an opaque ingestion message to the existing Queue. Its consumer retrieves the JSON-v2 result from Speechmatics, validates and normalizes the provider output, stores a stable private R2 artifact, then commits the Automatic Transcript, Automatic Speakers, Transcript Segments, and word timing through one service-role RPC. The callback, queue, R2 artifact, and Postgres transition are all idempotent; no transcript text, callback credential, provider ID, or object key is logged or returned to a client.

**Tech Stack:** Cloudflare Workers, Queues, private R2, Speechmatics Batch API, Supabase Postgres/RLS/pgTAP, TypeScript, Vitest.

---

### Task 1: Persist immutable Automatic Transcript layers

**Files:**
- Create: `supabase/migrations/<timestamp>_ingest_automatic_transcripts.sql`
- Modify: `supabase/tests/audio_backups_rls.test.sql`

- [x] Add `automatic_transcripts`, `automatic_speakers`, `transcript_segments`, and `transcript_words`. Each row is owned through its `automatic_transcripts.owner_id`; provider labels are unique per Automatic Transcript; segment and word ordinal positions are unique in their parent layer. Store audio timing as integer milliseconds, word confidence as `double precision`, detected language, provider speaker label, and the source artifact key.
- [x] Enable RLS and revoke all client writes on all four public tables. Grant authenticated `SELECT` only and create owner-only `SELECT` policies using `(select auth.uid()) = owner_id`; retain service-role persistence only.
- [x] Add `complete_transcription_ingestion(p_job_id uuid, p_artifact_key text, p_transcript jsonb)`, as a pinned-search-path, service-role-only `SECURITY DEFINER` function. Lock the job; require its state is `processing`; validate the provider job ID and tracking reference in the JSON; insert the immutable layers and set the job to `complete` in one transaction. If the job is already complete with the same artifact, return it; reject any conflicting second provider result.
- [x] Extend pgTAP to prove owner isolation and client-write denial for every layer, duplicate completion idempotency, complete-state atomicity, automatic-Speaker Audio scoping, and persisted word timing/language/confidence. Use only synthetic transcript strings.

### Task 2: Isolate Speechmatics callback and ingestion interfaces

**Files:**
- Create: `apps/worker/src/transcription-ingester.ts`
- Create: `apps/worker/src/supabase-transcription-ingestion-store.ts`
- Modify: `apps/worker/src/speechmatics-batch-client.ts`
- Modify: `apps/worker/src/transcription-submitter.ts`
- Test: `apps/worker/test/transcription-ingester.test.ts`
- Test: `apps/worker/test/speechmatics-batch-client.test.ts`
- Test: `apps/worker/test/supabase-transcription-ingestion-store.test.ts`

- [x] Extend the provider interface with `transcript(providerJobID)` and make job submission request a notification with no `contents`, the callback URL, and an opaque callback bearer token. Keep the source read URL and callback credential out of errors and test output.
- [x] Define a narrow `TranscriptionIngestionStore` that resolves a provider job to its processing Transcription Job and calls the atomic RPC. Define a private artifact store that writes JSON to `automatic-transcripts/<transcription-job-id>.json` and never overwrites an existing object.
- [x] Implement `TranscriptionIngester.ingest(jobID)`: resolve the job, retrieve the provider JSON, validate its shape and exact provider-job/tracking identity, serialize the private artifact, normalize only recognized JSON-v2 word/punctuation results into ordered Speakers, Segments, and Words, then complete the database RPC. A duplicate queue delivery must not create a second artifact or projection.
- [x] Test a successful bilingual, two-Speaker ingestion; malformed/provider-mismatched results; duplicate delivery; private artifact before completion; and no provider result in errors. Use fakes and compact synthetic values only.

### Task 3: Receive authenticated metadata-only callbacks and dispatch Queue messages

**Files:**
- Create: `apps/worker/src/speechmatics-callback.ts`
- Modify: `apps/worker/src/cloud-backup.ts`
- Modify: `apps/worker/src/index.ts`
- Modify: `apps/worker/src/env.d.ts`
- Modify: `apps/worker/wrangler.jsonc`
- Test: `apps/worker/test/speechmatics-callback.test.ts`
- Test: `apps/worker/test/cloud-backup.test.ts`

- [x] Add `POST /v1/transcription-callback`, outside Supabase-user authentication. Require the configured bearer token using a timing-safe comparison; accept only a valid provider job ID and `status=success`; reject a body payload and all failed statuses without logging payload or query values.
- [x] Send `{ kind: "ingest", transcription_job_id: <opaque UUID> }` to the existing Queue only after lookup confirms that provider job belongs to one processing Transcription Job. Change existing submission messages to `{ kind: "submit", transcription_job_id: <opaque UUID> }` and dispatch both shapes explicitly in the queue handler.
- [x] Wire the ingestion worker dependencies only when all service-role, Speechmatics, R2, callback-token, and public Worker URL configuration is present. Otherwise callback returns unavailable and queue messages retry; local Capture and backup HTTP paths remain unaffected.
- [x] Test rejected auth, unsupported status, malformed IDs, duplicate accepted callback, no transcript body persistence, correct queue payload, and coexistence with existing backup endpoints.

### Task 4: Validate and document operational setup

**Files:**
- Modify: `docs/testing/cloud-backup-validation.md`

- [x] Document the operator-only staging setup for the callback secret and public callback base URL without placing either value in the repository or command history. Record the expected synthetic-only callback and ingestion checks.
- [x] Run `npm run check` and `npm test` in `apps/worker`; run the focused pgTAP suite where Docker is available; run `git diff --check`.
- [x] Review that no logs, test names, fixtures, docs, errors, queue bodies, or HTTP responses contain Original Audio, transcript text outside minimal synthetic fixtures, callback tokens, provider IDs, signed URLs, or object keys.

## Self-review

- The plan covers each #47 acceptance criterion: authenticated metadata-only callback, private immutable artifact, normalized source projection, Audio-scoped Automatic Speakers, atomic completion, owner isolation, and duplicate-callback coverage.
- It retains the existing Source-of-Truth and offline-first boundaries: Original Audio is neither modified nor deleted, and no client receives provider credentials or provider output.
- Retry bounds, terminal failures, and provider deletion are deliberately excluded for #48.
