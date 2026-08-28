create table public.transcript_text_corrections (
  id uuid primary key default gen_random_uuid(),
  transcript_segment_id uuid not null unique references public.transcript_segments (id) on delete cascade,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  content text not null check (btrim(content) <> ''),
  created_at timestamptz not null default now()
);

create index transcript_text_corrections_owner_id_idx
on public.transcript_text_corrections (owner_id);

alter table public.transcript_text_corrections enable row level security;
revoke all on table public.transcript_text_corrections from anon, authenticated;
grant select, insert, delete on table public.transcript_text_corrections to authenticated;
grant update (content) on table public.transcript_text_corrections to authenticated;
grant select, insert, update, delete on table public.transcript_text_corrections to service_role;

create policy "Owners can read their transcript text corrections"
on public.transcript_text_corrections for select to authenticated
using (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
  )
);

create policy "Owners can create their transcript text corrections"
on public.transcript_text_corrections for insert to authenticated
with check (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
  )
);

create policy "Owners can replace their transcript text corrections"
on public.transcript_text_corrections for update to authenticated
using (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
  )
)
with check (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
  )
);

create policy "Owners can delete their transcript text corrections"
on public.transcript_text_corrections for delete to authenticated
using (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
  )
);
