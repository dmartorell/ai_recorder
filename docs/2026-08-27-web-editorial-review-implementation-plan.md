# Web Editorial Review Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first authenticated web workspace for owner-scoped Audio library, private Original Audio playback, and read-only Automatic Transcript review.

**Architecture:** Add a cloud `audios` catalog root and link each `audio_backups` row to it. The iPhone supplies a backup-time metadata snapshot; the Worker authorizes only short-lived playback URLs. A Vite SPA reads catalog/transcript projection data through Supabase RLS and asks the Worker only for playback access.

**Tech Stack:** Supabase Postgres/RLS/pgTAP, Cloudflare Worker/R2, Swift/XCTest, Vite, React, TypeScript, React Router, TanStack Query, Supabase JS, Vitest, Testing Library.

---

## File structure

| Path | Responsibility |
| --- | --- |
| `supabase/migrations/<timestamp>_create_cloud_audios.sql` | Cloud Audio catalog, backup relation, RLS, idempotent backup upsert. |
| `supabase/tests/audio_backups_rls.test.sql` | Catalog ownership and relationship proof. |
| `apps/worker/src/cloud-backup.ts` | Backup metadata validation and `GET /v1/audios/:id/playback`. |
| `apps/worker/src/supabase-backup-store.ts` | Catalog-aware backup persistence and owner playback lookup. |
| `apps/worker/test/cloud-backup.test.ts` | Backup metadata and playback authorization behavior. |
| `apps/ios/AIRecorder/CloudBackup/*` | Send immutable backup-time metadata snapshot. |
| `apps/ios/AIRecorderTests/Features/*` | Backup metadata request coverage. |
| `apps/web/*` | SPA, routing, Supabase client, queries, playback and transcript UI. |

### Task 1: Persist the cloud Audio catalog

**Files:**
- Create: `supabase/migrations/<timestamp>_create_cloud_audios.sql`
- Modify: `supabase/tests/audio_backups_rls.test.sql`

- [ ] Write pgTAP assertions that an authenticated owner reads only their `audios` row, another owner reads no row, and one `audio_backups.audio_id` references the owner’s Audio.
- [ ] Run `supabase test db --local supabase/tests/audio_backups_rls.test.sql`; expect failure because `audios` does not exist.
- [ ] Generate the migration with `supabase migration new create_cloud_audios`. Create `public.audios` with UUID primary key, `owner_id`, unique `local_audio_id`, `title`, `started_at`, non-negative `duration_milliseconds`, and checked transcription language. Add nullable `audio_id` to `audio_backups`, backfill one Audio per existing backup, then make it non-null and unique. Enable RLS, grant authenticated read and service-role write, and add owner-only select policy.
- [ ] Extend `begin_audio_backup` to accept title, start, duration, and language; lock/upsert the owner’s Audio by `local_audio_id`, then create or reuse its backup. Metadata conflicts retain the existing idempotency error.
- [ ] Re-run pgTAP; expect pass. Commit `feat: catalog cloud audio metadata`.

### Task 2: Send backup-time metadata from iPhone

**Files:**
- Modify: `apps/ios/AIRecorder/CloudBackup/CloudBackupCoordinator.swift`
- Modify: `apps/ios/AIRecorder/CloudBackup/WorkerCloudBackupClient.swift`
- Modify: `apps/ios/AIRecorderTests/Features/CloudBackupCoordinatorTests.swift`
- Modify: `apps/ios/AIRecorderTests/Features/WorkerCloudBackupClientTests.swift`

- [ ] Add failing tests asserting the begin-backup JSON includes `title`, `started_at`, and `duration_milliseconds` from the finalized `AudioItem`, alongside existing byte count, SHA-256, and transcription language.
- [ ] Run the two focused XCTest classes; expect failure because the request model lacks metadata.
- [ ] Extend `CloudBackupRequest` with `title`, `startedAt`, and `durationMilliseconds`; construct it in `confirmBackup` from `item.displayTitle()`, `item.startedAt`, and `item.durationMilliseconds`. Encode the three snake-case fields in `BackupRequestBody`.
- [ ] Re-run focused tests; expect pass. Commit `feat: catalog audio metadata at backup`.

### Task 3: Authorize private browser playback

**Files:**
- Modify: `apps/worker/src/cloud-backup.ts`
- Modify: `apps/worker/src/supabase-backup-store.ts`
- Modify: `apps/worker/test/cloud-backup.test.ts`

- [ ] Add failing Worker tests for `GET /v1/audios/:audioID/playback`: `401` unauthenticated, `404` absent or foreign Audio, `409` when no verified backup, and `200` containing only `{ url, expires_in: 900 }` for an owned backed-up Audio.
- [ ] Run `cd apps/worker && npm test -- cloud-backup`; expect failure because the route is absent.
- [ ] Add an owner-scoped catalog lookup to `BackupStore`; its result contains only the verified backup’s opaque object key. Dispatch the exact playback route before backup route matching, call existing `MultipartGateway.signedReadURL`, and return the 900-second response. Never log or return the object key.
- [ ] Re-run focused Worker tests and `npm run check`; expect pass. Commit `feat: authorize private audio playback`.

### Task 4: Create the web application foundation

**Files:**
- Create: `apps/web/package.json`, `apps/web/vite.config.ts`, `apps/web/tsconfig.json`, `apps/web/index.html`, `apps/web/src/main.tsx`, `apps/web/src/app.tsx`, `apps/web/src/lib/supabase.ts`, `apps/web/src/lib/query-client.ts`, `apps/web/src/styles.css`
- Create: `apps/web/src/routes/login-page.tsx`, `apps/web/src/routes/auth-callback-page.tsx`, `apps/web/src/routes/require-session.tsx`
- Create: `apps/web/test/setup.ts`, `apps/web/vitest.config.ts`

- [ ] Add package dependencies approved by the design: React, React DOM, React Router, TanStack Query, Supabase JS, Vite, Cloudflare Vite plugin, Vitest, Testing Library, and jsdom. Commit the lockfile.
- [ ] Write route tests that `/audios` redirects without a session, login requests a magic link, and the callback exchanges the URL session then navigates to `/audios`.
- [ ] Implement a single Supabase browser client using only the public publishable key, a QueryClient provider, BrowserRouter routes, and session gate. Keep configuration in `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, and `VITE_WORKER_URL`; do not commit values.
- [ ] Run `npm test` and `npm run build` in `apps/web`; expect pass. Commit `feat: add authenticated web workspace shell`.

### Task 5: Implement library and transcript detail

**Files:**
- Create: `apps/web/src/features/audio/audio-queries.ts`, `apps/web/src/features/audio/audio-types.ts`, `apps/web/src/features/audio/audio-library-page.tsx`, `apps/web/src/features/audio/audio-detail-page.tsx`, `apps/web/src/features/audio/transcript.tsx`
- Create: `apps/web/test/audio-library-page.test.tsx`, `apps/web/test/audio-detail-page.test.tsx`

- [ ] Write failing tests for owner-visible library metadata, empty/loading/error states, ordered Speakers and Transcript Segments, segment click seeking, and active-segment rendering from player time.
- [ ] Query `audios` and its backup/transcription state through Supabase RLS. On detail, fetch the owned Audio, Automatic Transcript, Speakers, and ordered Transcript Segments in parallel where dependencies permit. Do not fetch transcript words.
- [ ] Render responsive library rows and read-only detail. Use locale-aware date/duration formatting, browser-language strings, semantic buttons, and accessible segment labels. Do not render a waveform, edit control, retry control, download, search, or filters.
- [ ] Run focused web tests; expect pass. Commit `feat: review automatic transcripts on web`.

### Task 6: Add the private player and validate the vertical slice

**Files:**
- Create: `apps/web/src/features/audio/private-audio-player.tsx`, `apps/web/test/private-audio-player.test.tsx`
- Modify: `apps/web/src/features/audio/audio-detail-page.tsx`
- Modify: `docs/testing/cloud-backup-validation.md`

- [ ] Write failing player tests for custom play/pause, ten-second skips, speed, no player before verified backup, and exactly one URL renewal after an expiry-related media error.
- [ ] Implement the player with an `HTMLAudioElement`, request playback URL only for backed-up Audio, and renew once. Preserve detail state and show a generic accessible error after a second failure.
- [ ] Run `cd apps/web && npm test && npm run build`, `cd apps/worker && npm run check && npm test`, the focused pgTAP suite, and `git diff --check`.
- [ ] Execute synthetic staging E2E: magic-link login, owner library, private playback, segment seek, and foreign-owner denial. Record pass/fail and statuses only.
- [ ] Commit `docs: validate web editorial review`.

## Self-review

- Cloud Audio is separate from backup state; the Original Audio stays private and immutable.
- Automatic Transcript data is read-only, with no User Correction or Generated Analysis added.
- Browser playback is owner-authorized and short-lived; RLS covers all direct reads.
- No waveform, downloads, web recording, search, filters, exports, collaboration, or fragment joining are included.
