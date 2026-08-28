# Speaker Attribution Corrections Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an Audio owner add named Speakers, assign an Editorial Speaker to one Transcript Segment, and independently revert that assignment without mutating Automatic Transcript data.

**Architecture:** Keep `automatic_speakers` and `transcript_segments.automatic_speaker_id` immutable provider projections. Extend the Audio-scoped editorial `speakers` table to support user-created rows, and keep one current Speaker overlay per Transcript Segment in `transcript_speaker_corrections`. The SPA projects an effective Speaker from that overlay, while text and Speaker corrections update separate cache fields and can be reverted independently.

**Tech Stack:** Supabase Postgres/RLS/pgTAP, React, TypeScript, TanStack Query, Supabase JS, Vitest, Testing Library.

---

## File structure

| Path | Responsibility |
| --- | --- |
| `supabase/migrations/20260828203414_create_transcript_speaker_corrections.sql` | Allows user-created Speakers and persists owner-scoped, same-Audio Speaker correction overlays. |
| `supabase/migrations/20260828204739_permit_transcript_speaker_correction_upserts.sql` | Permits PostgREST upserts while trigger-protecting all correction fields except `speaker_id`. |
| `supabase/tests/audio_backups_rls.test.sql` | Proves Speaker insertion, correction RLS, same-Audio integrity, and independent reverts. |
| `apps/web/src/features/audio/audio-types.ts` | Represents manual Speakers and the nullable Speaker correction overlay. |
| `apps/web/src/features/audio/audio-queries.ts` | Fetches all editorial Speakers and current Speaker corrections for the existing Audio detail projection. |
| `apps/web/src/features/audio/add-speaker-form.tsx` | Owns an accessible named-Speaker draft, validation, save, error, and retry behavior. |
| `apps/web/src/features/audio/transcript-speaker-editor.tsx` | Owns a Segment's Speaker selection, save/retry, automatic-source disclosure, and Speaker-only revert. |
| `apps/web/src/features/audio/transcript.tsx` | Selects and renders the effective Speaker label for each Segment. |
| `apps/web/test/add-speaker-form.test.tsx` | Tests user-observable add-Speaker behavior. |
| `apps/web/test/transcript-speaker-editor.test.tsx` | Tests user-observable attribution save, failure/retry, source disclosure, and independent revert behavior. |
| `apps/web/test/transcript.test.tsx` | Tests effective Speaker rendering for automatically and manually attributed Segments. |

### Task 1: Persist a Speaker attribution overlay

**Files:**
- Create: `supabase/migrations/20260828203414_create_transcript_speaker_corrections.sql`
- Modify: `supabase/tests/audio_backups_rls.test.sql`

- [ ] **Step 1: Add failing pgTAP coverage and update the plan count.**

  Add 19 assertions after the existing text-correction assertions and update the pgTAP plan to 115. Cover owner-created Speakers, an assigned Speaker correction, a PostgREST-compatible replacement upsert, immutable correction identity, a same-owner cross-Audio rejection, foreign-owner read/insert/update/delete denial, and a Speaker-only revert that retains the text correction and automatic source fields.

  ```sql
  select plan(115);

  insert into public.speakers (audio_id, name)
  values ((select audio_id from public.audio_backups where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'), 'Editor');

  insert into public.transcript_speaker_corrections (transcript_segment_id, speaker_id)
  values (
    (select id from public.transcript_segments where ordinal = 0),
    current_setting('test.manual_speaker_id')::uuid
  );
  ```

- [ ] **Step 2: Run the database test to verify it fails.**

  Run: `supabase test db --local supabase/tests/audio_backups_rls.test.sql`

  Expected: FAIL because `transcript_speaker_corrections` does not exist and `speakers.automatic_speaker_id` is required.

- [ ] **Step 3: Create the migration.**

  Generate the migration with `supabase migration new create_transcript_speaker_corrections`, then implement these schema changes:

  ```sql
  alter table public.speakers
    alter column automatic_speaker_id drop not null;

  grant insert (audio_id, name) on table public.speakers to authenticated;

  create policy "Owners can create named speakers"
  on public.speakers for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and name is not null
    and exists (
      select 1 from public.audios audio
      where audio.id = audio_id and audio.owner_id = (select auth.uid())
    )
  );

  create table public.transcript_speaker_corrections (
    id uuid primary key default gen_random_uuid(),
    transcript_segment_id uuid not null unique references public.transcript_segments (id) on delete cascade,
    speaker_id uuid not null references public.speakers (id) on delete restrict,
    owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    created_at timestamptz not null default now()
  );
  ```

  Enable RLS, revoke all from `anon` and `authenticated`, grant `authenticated` select/insert/update(`speaker_id`)/delete and full service-role access. Create owner policies that require `owner_id = (select auth.uid())`, an owned Segment, and an owned target Speaker. Add a trigger function with `set search_path = ''` that raises `P0001` unless the target Speaker and the Segment's Audio have the same owner and Audio. Revoke public execute on that trigger function. Index `owner_id` and `speaker_id` for RLS and correction reads.

- [ ] **Step 4: Run the database test to verify it passes.**

  Run: `supabase test db --local supabase/tests/audio_backups_rls.test.sql`

  Expected: PASS with 115 assertions.

### Task 2: Project manual Speakers and attribution overlays

**Files:**
- Modify: `apps/web/src/features/audio/audio-types.ts`
- Modify: `apps/web/src/features/audio/audio-queries.ts`

- [ ] **Step 1: Add failing query projection tests or extend the existing Audio-detail query test seam.**

  Mock an automatic Speaker, a named manual Speaker, and a correction whose `speaker_id` is that manual Speaker. Assert that automatic `content` and `automatic_speaker_id` remain present and that only `speakerCorrectionID` represents the overlay.

- [ ] **Step 2: Extend the types without replacing automatic identifiers.**

  ```ts
  export interface Speaker {
    id: string;
    provider_label: string;
    ordinal: number;
    editorial_id: string;
    name: string | null;
    automatic_speaker_id: string | null;
  }

  export interface Segment {
    id: string;
    automatic_speaker_id: string;
    ordinal: number;
    content: string;
    correction?: string | null;
    speakerCorrectionID?: string | null;
    start_time_ms: number;
    end_time_ms: number;
  }
  ```

- [ ] **Step 3: Fetch and project the overlays.**

  Keep the automatic Speaker, editorial Speaker, and Segment reads parallel. Query `transcript_speaker_corrections` only after Segment IDs are known, then map the results without replacing `automatic_speaker_id`.

  ```ts
  const { data: speakerCorrections, error: speakerCorrectionsError } = await supabase
    .from("transcript_speaker_corrections")
    .select("transcript_segment_id,speaker_id")
    .in("transcript_segment_id", segments.map((segment) => segment.id));
  await fail(speakerCorrectionsError);

  const speakerCorrectionBySegmentID = new Map(
    (speakerCorrections ?? []).map((correction) => [correction.transcript_segment_id, correction.speaker_id])
  );
  ```

  Map every `speakers` row, including rows without `automatic_speaker_id`, into the `Speaker` projection. Seeded rows retain their provider label and ordinal from their automatic Speaker. Manual rows use `"Speaker"` as their fallback label and sort after seeded rows.

- [ ] **Step 4: Build the web app.**

  Run: `cd apps/web && npm run build`

  Expected: successful TypeScript build.

### Task 3: Add named Speakers from the Editorial Transcript

**Files:**
- Create: `apps/web/src/features/audio/add-speaker-form.tsx`
- Create: `apps/web/test/add-speaker-form.test.tsx`
- Modify: `apps/web/src/features/audio/transcript.tsx`

- [ ] **Step 1: Write failing component tests.**

  Test non-empty validation, `insert({ audio_id: audioID, name })`, pending `Saving`, success cache insertion, generic error copy, retained draft, and Retry.

  ```tsx
  fireEvent.change(screen.getByLabelText("New Speaker name"), { target: { value: "Editor" } });
  fireEvent.click(screen.getByRole("button", { name: "Add Speaker" }));
  await waitFor(() => expect(insert).toHaveBeenCalledWith({ audio_id: "audio-1", name: "Editor" }));
  ```

- [ ] **Step 2: Implement the focused form.**

  Use local state, trim only for validation/submission, and insert directly through `supabase.from("speakers")`. After successful insertion, append the returned editorial Speaker to `['audio', audioID]`; do not refetch or update automatic Speaker data.

  ```tsx
  const { data, error } = await supabase
    .from("speakers")
    .insert({ audio_id: audioID, name: draft.trim() })
    .select("id,automatic_speaker_id,name")
    .single();
  ```

  Render buttons and labels with accessible names, `Saving`, `Saved`, `Could not save.`, and `Retry` states.

- [ ] **Step 3: Render it above the Segment list.**

  ```tsx
  <AddSpeakerForm audioID={audioID} />
  ```

- [ ] **Step 4: Run focused tests.**

  Run: `cd apps/web && npm test -- add-speaker-form`

  Expected: PASS.

### Task 4: Edit and revert effective Segment Speaker attribution

**Files:**
- Create: `apps/web/src/features/audio/transcript-speaker-editor.tsx`
- Create: `apps/web/test/transcript-speaker-editor.test.tsx`
- Modify: `apps/web/src/features/audio/transcript.tsx`

- [ ] **Step 1: Write failing component tests.**

  Cover an initial automatic assignment, choice of an Audio-scoped editorial Speaker, upsert through the Segment ID conflict target, pending/success/error/retry states, source disclosure, and a revert that preserves a supplied text correction.

  ```tsx
  fireEvent.change(screen.getByLabelText("Speaker at 0:10"), { target: { value: "editorial-2" } });
  fireEvent.click(screen.getByRole("button", { name: "Save Speaker" }));
  await waitFor(() => expect(upsert).toHaveBeenCalledWith(
    { transcript_segment_id: "segment-1", speaker_id: "editorial-2" },
    { onConflict: "transcript_segment_id" }
  ));
  ```

- [ ] **Step 2: Implement `TranscriptSpeakerEditor`.**

  Use a controlled `<select>` of editorial Speaker IDs. Save an upsert to `transcript_speaker_corrections`, update only `speakerCorrectionID` in the Audio cache on success, and delete that row on revert. Preserve all other Segment fields including `correction`.

  ```ts
  segments: current.segments.map((item) =>
    item.id === segment.id ? { ...item, speakerCorrectionID } : item
  )
  ```

  Show `View automatic Speaker` with the automatic label, and render `Revert Speaker` only when an overlay exists.

- [ ] **Step 3: Compose one editor per Segment.**

  Pass the automatic label, all Audio-scoped Speakers, and the current overlay into `TranscriptSpeakerEditor`. Keep the existing Segment seek button as the sole seek control.

- [ ] **Step 4: Run focused tests.**

  Run: `cd apps/web && npm test -- transcript-speaker-editor transcript`

  Expected: PASS.

### Task 5: Render effective labels and validate the complete slice

**Files:**
- Modify: `apps/web/src/features/audio/transcript.tsx`
- Modify: `apps/web/test/transcript.test.tsx`
- Verify: `supabase/tests/audio_backups_rls.test.sql`

- [ ] **Step 1: Add Transcript behavior tests.**

  Verify that a Segment with no `speakerCorrectionID` shows the Speaker mapped from `automatic_speaker_id`, while a corrected Segment shows the selected editorial Speaker's name. Also verify that corrected text remains displayed when the Speaker correction is reverted.

- [ ] **Step 2: Select the effective Speaker without overwriting source attribution.**

  ```ts
  const automaticSpeakers = new Map(speakers
    .filter((speaker) => speaker.automatic_speaker_id)
    .map((speaker) => [speaker.automatic_speaker_id!, speaker]));
  const editorialSpeakers = new Map(speakers.map((speaker) => [speaker.editorial_id, speaker]));
  const effectiveSpeaker = segment.speakerCorrectionID
    ? editorialSpeakers.get(segment.speakerCorrectionID)
    : automaticSpeakers.get(segment.automatic_speaker_id);
  ```

  Use `effectiveSpeaker?.name ?? effectiveSpeaker?.provider_label ?? "Speaker"` for the visible label and preserve `segment.automatic_speaker_id` for the source disclosure.

- [ ] **Step 3: Run all required validation.**

  Run:

  ```bash
  supabase test db --local supabase/tests/audio_backups_rls.test.sql
  cd apps/web && npm test && npm run build
  git diff --check
  ```

  Expected: all commands succeed.

- [ ] **Step 4: Review scope and commit.**

  Confirm no route, Worker, Automatic Transcript mutation, Speaker deletion, cross-Audio identity, revision history, or unrelated changes were added. Commit the focused slice:

  ```bash
  git add supabase/migrations supabase/tests apps/web/src/features/audio apps/web/test docs/2026-08-28-speaker-attribution-corrections-implementation-plan.md
  git commit -m "feat: correct transcript segment speakers"
  ```

## Self-review

- A named Speaker is scoped to one owned Audio and cannot be empty.
- A Speaker correction is unique per Transcript Segment and cannot target a Speaker from another Audio or owner.
- Reverting Speaker attribution deletes only its correction row, preserving text correction, Automatic Speaker, timestamps, ordering, and boundaries.
- The Editorial Transcript overlays correction data and never writes provider projections.
- All database and UI errors retain user input and use generic visible error copy.
