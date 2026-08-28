alter table public.speakers
  alter column automatic_speaker_id drop not null,
  alter column owner_id set default auth.uid();

grant insert (audio_id, name) on table public.speakers to authenticated;

create policy "Owners can create named speakers"
on public.speakers for insert to authenticated
with check (
  owner_id = (select auth.uid())
  and name is not null
  and exists (
    select 1
    from public.audios audio
    where audio.id = audio_id
      and audio.owner_id = (select auth.uid())
  )
);

create table public.transcript_speaker_corrections (
  id uuid primary key default gen_random_uuid(),
  transcript_segment_id uuid not null unique references public.transcript_segments (id) on delete cascade,
  speaker_id uuid not null references public.speakers (id) on delete restrict,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index transcript_speaker_corrections_owner_id_idx
on public.transcript_speaker_corrections (owner_id);

create index transcript_speaker_corrections_speaker_id_idx
on public.transcript_speaker_corrections (speaker_id);

create function public.validate_transcript_speaker_correction_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  segment_owner_id uuid;
  segment_audio_id uuid;
  speaker_owner_id uuid;
  speaker_audio_id uuid;
begin
  select transcript.owner_id, backup.audio_id
  into segment_owner_id, segment_audio_id
  from public.transcript_segments segment
  join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
  join public.transcription_jobs job on job.id = transcript.transcription_job_id
  join public.audio_backups backup on backup.id = job.backup_id
  where segment.id = new.transcript_segment_id;

  select owner_id, audio_id
  into speaker_owner_id, speaker_audio_id
  from public.speakers
  where id = new.speaker_id;

  if segment_owner_id is distinct from speaker_owner_id
    or segment_audio_id is distinct from speaker_audio_id then
    raise exception 'speaker correction must belong to the segment audio' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger transcript_speaker_corrections_validate_scope
before insert or update on public.transcript_speaker_corrections
for each row execute function public.validate_transcript_speaker_correction_scope();

alter table public.transcript_speaker_corrections enable row level security;
revoke all on table public.transcript_speaker_corrections from anon, authenticated;
grant select, insert, delete on table public.transcript_speaker_corrections to authenticated;
grant update (speaker_id) on table public.transcript_speaker_corrections to authenticated;
grant select, insert, update, delete on table public.transcript_speaker_corrections to service_role;

create policy "Owners can read their transcript speaker corrections"
on public.transcript_speaker_corrections for select to authenticated
using (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    join public.transcription_jobs job on job.id = transcript.transcription_job_id
    join public.audio_backups backup on backup.id = job.backup_id
    join public.speakers speaker on speaker.id = speaker_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
      and speaker.owner_id = (select auth.uid())
      and speaker.audio_id = backup.audio_id
  )
);

create policy "Owners can create their transcript speaker corrections"
on public.transcript_speaker_corrections for insert to authenticated
with check (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    join public.transcription_jobs job on job.id = transcript.transcription_job_id
    join public.audio_backups backup on backup.id = job.backup_id
    join public.speakers speaker on speaker.id = speaker_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
      and speaker.owner_id = (select auth.uid())
      and speaker.audio_id = backup.audio_id
  )
);

create policy "Owners can replace their transcript speaker corrections"
on public.transcript_speaker_corrections for update to authenticated
using (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    join public.transcription_jobs job on job.id = transcript.transcription_job_id
    join public.audio_backups backup on backup.id = job.backup_id
    join public.speakers speaker on speaker.id = speaker_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
      and speaker.owner_id = (select auth.uid())
      and speaker.audio_id = backup.audio_id
  )
)
with check (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    join public.transcription_jobs job on job.id = transcript.transcription_job_id
    join public.audio_backups backup on backup.id = job.backup_id
    join public.speakers speaker on speaker.id = speaker_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
      and speaker.owner_id = (select auth.uid())
      and speaker.audio_id = backup.audio_id
  )
);

create policy "Owners can delete their transcript speaker corrections"
on public.transcript_speaker_corrections for delete to authenticated
using (
  owner_id = (select auth.uid())
  and exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    join public.transcription_jobs job on job.id = transcript.transcription_job_id
    join public.audio_backups backup on backup.id = job.backup_id
    join public.speakers speaker on speaker.id = speaker_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
      and speaker.owner_id = (select auth.uid())
      and speaker.audio_id = backup.audio_id
  )
);

revoke all on function public.validate_transcript_speaker_correction_scope() from public;
