# Queue Verified Audio for Transcription Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create one ownership-scoped queued Transcription Job whenever private Original Audio has passed cloud-backup verification, and show that state independently in iPhone status.

**Architecture:** Supabase owns the durable job record, keyed uniquely by its verified `audio_backups` row. The Cloudflare Worker creates or reuses that record immediately after remote-object verification and sends only its opaque job ID to a Queue. The iPhone reads the authorized job state from the existing Worker boundary at launch, foregrounding, and Audio-detail opening.

**Tech Stack:** Cloudflare Workers and Queues, Supabase Postgres/RLS/pgTAP, TypeScript/Vitest, Swift 6/SwiftUI/SwiftData/XCTest.

---

### Task 1: Durable, ownership-scoped job storage

**Files:**
- Create: `supabase/migrations/<timestamp>_create_transcription_jobs.sql`
- Modify: `supabase/tests/audio_backups_rls.test.sql`

- [x] Add `public.transcription_jobs`, one row per `audio_backups.id`, with `owner_id`, `state = 'queued'`, timestamps, a foreign key to the backup, RLS, and authenticated owner-only SELECT.
- [x] Add service-role-only `enqueue_transcription_job(uuid)` which locks the backup, rejects non-verified backups, and inserts or returns its single queued job.
- [x] Add pgTAP coverage for uniqueness, immutable queued state, direct authenticated-write denial, and owner isolation.

### Task 2: Worker enqueue and authorized status seams

**Files:**
- Create: `apps/worker/src/supabase-transcription-job-store.ts`
- Modify: `apps/worker/src/cloud-backup.ts`
- Modify: `apps/worker/src/index.ts`
- Modify: `apps/worker/src/env.d.ts`
- Modify: `apps/worker/wrangler.jsonc`
- Create: `apps/worker/test/transcription-jobs.test.ts`

- [x] Define injected job-store and queue interfaces so tests do not require Cloudflare or a provider account.
- [x] After `markBackedUp`, create or reuse the job and publish its opaque ID. A duplicate verification response or duplicate trigger must reuse the same record.
- [x] Add the authorized backup transcription-status endpoint. It returns only the caller-owned job state and never changes backup state.
- [x] Add the staging Queue binding. Configure no consumer in this slice because Speechmatics submission belongs to #44.
- [x] Cover creation, idempotency, queue publication, authorization, and missing-job state in Vitest.

### Task 3: iPhone transcription-state refresh

**Files:**
- Modify: `apps/ios/AIRecorder/Persistence/AudioItem.swift`
- Modify: `apps/ios/AIRecorder/CloudBackup/CloudBackupCoordinator.swift`
- Modify: `apps/ios/AIRecorder/CloudBackup/CloudBackupPersistence.swift`
- Modify: `apps/ios/AIRecorder/CloudBackup/WorkerCloudBackupClient.swift`
- Modify: `apps/ios/AIRecorder/App/RootView.swift`
- Modify: `apps/ios/AIRecorder/Features/AudioDetail/AudioDetailView.swift`
- Modify: `apps/ios/AIRecorder/Features/Library/LibraryAudioStatus.swift`
- Modify: `apps/ios/AIRecorderTests/Features/CloudBackupCoordinatorTests.swift`
- Modify: `apps/ios/AIRecorderTests/Features/WorkerCloudBackupClientTests.swift`
- Modify: `apps/ios/AIRecorderTests/Features/LibraryAudioStatusTests.swift`

- [x] Persist `notStarted`, `queued`, and later-compatible processing state independently of backup fields.
- [x] Extend the injected client with a status read and refresh backed-up Audio on launch, foregrounding, and detail opening.
- [x] Display `Transcription: Queued` separately from local audio, cloud audio, and summary state. Do not alter deletion eligibility.
- [x] Cover client decoding, refresh lifecycle seams, and independent status presentation with fakes.

### Task 4: Validation

**Files:**
- Modify: `docs/testing/cloud-backup-validation.md`

- [ ] Run Worker typecheck and tests, database tests where linked credentials permit, iOS focused tests, the full iOS suite, and `git diff --check`. Worker and iOS suites pass. Supabase pgTAP is blocked because Docker or Podman is unavailable.
- [x] Document the Queue provisioning command and clarify that no Speechmatics credential is required for this ticket.
