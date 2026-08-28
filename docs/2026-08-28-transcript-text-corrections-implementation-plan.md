# Transcript Text Corrections Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an Audio owner correct and revert the displayed text of an individual Transcript Segment without changing its Automatic Transcript source or Speaker attribution.

**Architecture:** Preserve automatic segment text in `transcript_segments` and store one current `transcript_text_corrections` row per segment. RLS authorizes corrections only when the row owner also owns the segment's Automatic Transcript. The web detail query overlays correction text on the editorial projection; a focused editor owns its draft, save, retry, automatic-text disclosure, and text-only revert states.

**Tech Stack:** Supabase Postgres/RLS/pgTAP, React, TypeScript, TanStack Query, Supabase JS, Vitest, Testing Library.

---

## File structure

| Path | Responsibility |
| --- | --- |
| `supabase/migrations/20260828184845_create_transcript_text_corrections.sql` | Current text correction storage, ownership RLS, minimal grants. |
| `supabase/tests/audio_backups_rls.test.sql` | Ownership, one-current-correction, revert, and Automatic Transcript immutability assertions. |
| `apps/web/src/features/audio/audio-types.ts` | Segment correction projection type. |
| `apps/web/src/features/audio/audio-queries.ts` | Fetch owned text corrections with the existing transcript projection. |
| `apps/web/src/features/audio/transcript-text-editor.tsx` | Per-segment draft, save/retry, automatic-text disclosure, and text-only revert UI. |
| `apps/web/src/features/audio/transcript.tsx` | Render the Editorial Transcript and compose each segment editor. |
| `apps/web/test/transcript-text-editor.test.tsx` | Observable save, failure/retry, automatic source, and independent revert states. |
| `apps/web/test/transcript.test.tsx` | Corrected text and Edited indicator rendering. |

### Task 1: Persist current text corrections

**Files:**
- Modify: `supabase/migrations/20260828184845_create_transcript_text_corrections.sql`
- Modify: `supabase/tests/audio_backups_rls.test.sql`

- [ ] Add failing pgTAP assertions after the editorial Speaker assertions. As the Audio owner, insert a correction for the `Hola,` Segment, upsert a replacement, and verify exactly one row with the newest content. As the other user, prove that selecting, inserting, updating, and deleting the owner's correction returns no rows or permission-denied. Delete the owner's correction and prove the Segment's automatic content, automatic Speaker, ordinal, and timestamps remain unchanged.
- [ ] Run `supabase test db --local supabase/tests/audio_backups_rls.test.sql`. Expected: failure because `transcript_text_corrections` does not exist.
- [ ] Create `public.transcript_text_corrections` with `id uuid primary key default gen_random_uuid()`, `transcript_segment_id uuid not null unique references public.transcript_segments(id) on delete cascade`, `owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade`, `content text not null check (btrim(content) <> '')`, and `created_at timestamptz not null default now()`. Enable RLS, revoke all from `anon` and `authenticated`, grant authenticated `select`, `insert`, `update(content)`, and `delete`, and service role full table access. Add owner-only select, insert, update, and delete policies. Each policy must require both `owner_id = (select auth.uid())` and an `exists` check joining the segment's Automatic Transcript to the same owner.
- [ ] Run `supabase test db --local supabase/tests/audio_backups_rls.test.sql`. Expected: pass.

### Task 2: Project correction data into the web Editorial Transcript

**Files:**
- Modify: `apps/web/src/features/audio/audio-types.ts`
- Modify: `apps/web/src/features/audio/audio-queries.ts`

- [ ] Extend `Segment` with nullable `correction?: string | null`.
- [ ] After the existing parallel Speaker and Segment reads, query `transcript_text_corrections` for the fetched Segment IDs, selecting `transcript_segment_id,content`. Map results by Segment ID and project `correction` without overwriting automatic `content`. Skip the query when no segments exist.
- [ ] Run `cd apps/web && npm run build`. Expected: successful TypeScript build.

### Task 3: Build an observable per-segment text editor

**Files:**
- Create: `apps/web/src/features/audio/transcript-text-editor.tsx`
- Create: `apps/web/test/transcript-text-editor.test.tsx`

- [ ] Write failing component tests with a mocked Supabase client. Cover: editing starts with current editorial text; save upserts `{ transcript_segment_id, content }` through the Segment ID conflict target and shows `Saving` then `Saved`; an error retains the edited draft and shows generic `Could not save.` with Retry; View automatic text exposes the immutable automatic text; Revert text deletes only the correction and restores automatic text while retaining the supplied Speaker label.
- [ ] Implement `TranscriptTextEditor`. Keep the input draft in component state. Trim only for validation and do not submit an empty value. On save, use `upsert(..., { onConflict: "transcript_segment_id" })`, update `['audio', audioID]` TanStack Query cache only after success, and preserve the draft after errors. On revert, delete by correction's Segment ID, update only that Segment's `correction` cache field, and retain all other Segment fields. Use buttons and labels with segment-specific accessible names.
- [ ] Run `cd apps/web && npm test -- transcript-text-editor`. Expected: pass.

### Task 4: Render Editorial Transcript corrections

**Files:**
- Modify: `apps/web/src/features/audio/transcript.tsx`
- Modify: `apps/web/test/transcript.test.tsx`

- [ ] Add failing Transcript tests that corrected text replaces displayed automatic text, displays `Edited`, and exposes the supplied automatic text on request. Retain the existing seek button and Speaker label assertions.
- [ ] Rename the section heading and accessible landmark to `Editorial Transcript`. Render `TranscriptTextEditor` for every Segment, supplying automatic Segment content, correction, effective Speaker label, and select callback. Keep the source timestamp/order/Speaker mapping untouched; the select button remains the sole seek interaction.
- [ ] Run `cd apps/web && npm test -- transcript transcript-text-editor && npm run build`. Expected: pass.

### Task 5: Validate the vertical slice

**Files:**
- Verify: `supabase/tests/audio_backups_rls.test.sql`
- Verify: `apps/web/test/transcript-text-editor.test.tsx`
- Verify: `apps/web/test/transcript.test.tsx`

- [ ] Run `supabase test db --local supabase/tests/audio_backups_rls.test.sql`.
- [ ] Run `cd apps/web && npm test && npm run build`.
- [ ] Run `git diff --check`.
- [ ] Confirm the diff creates no automatic transcript mutation API, does not alter transcript timestamps/order/boundaries, and includes no network or unrelated product scope.

## Self-review

- Current correction storage is unique per Transcript Segment and deletion restores source text rather than destroying it.
- RLS ties every read and mutation to the owner of both the correction and its Transcript Segment.
- Save failures keep local draft text and offer generic Retry.
- Revert changes only correction data, leaving automatic content, Speaker attribution, timestamps, order, and boundaries intact.
