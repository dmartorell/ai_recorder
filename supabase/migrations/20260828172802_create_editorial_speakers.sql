create table public.speakers (
  id uuid primary key default gen_random_uuid(),
  audio_id uuid not null references public.audios (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  automatic_speaker_id uuid not null unique references public.automatic_speakers (id) on delete cascade,
  name text check (name is null or (btrim(name) <> '' and char_length(name) <= 200)),
  created_at timestamptz not null default now()
);

create index speakers_owner_id_audio_id_idx on public.speakers (owner_id, audio_id);

insert into public.audios (
  owner_id, local_audio_id, title_snapshot, capture_started_at,
  duration_milliseconds, transcription_language
)
select owner_id, local_audio_id, 'Audio', created_at, 0, transcription_language
from public.audio_backups
where audio_id is null
on conflict (owner_id, local_audio_id) do nothing;

update public.audio_backups backup
set audio_id = audio.id
from public.audios audio
where backup.audio_id is null
  and audio.owner_id = backup.owner_id
  and audio.local_audio_id = backup.local_audio_id;

insert into public.speakers (audio_id, owner_id, automatic_speaker_id)
select backup.audio_id, transcript.owner_id, automatic_speaker.id
from public.automatic_speakers automatic_speaker
join public.automatic_transcripts transcript on transcript.id = automatic_speaker.automatic_transcript_id
join public.transcription_jobs job on job.id = transcript.transcription_job_id
join public.audio_backups backup on backup.id = job.backup_id
where backup.audio_id is not null;

create function public.create_editorial_speaker()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.speakers (audio_id, owner_id, automatic_speaker_id)
  select backup.audio_id, transcript.owner_id, new.id
  from public.automatic_transcripts transcript
  join public.transcription_jobs job on job.id = transcript.transcription_job_id
  join public.audio_backups backup on backup.id = job.backup_id
  where transcript.id = new.automatic_transcript_id
    and backup.audio_id is not null;

  return new;
end;
$$;

create trigger automatic_speakers_create_editorial_speaker
  after insert on public.automatic_speakers
  for each row execute function public.create_editorial_speaker();

alter table public.speakers enable row level security;
revoke all on table public.speakers from anon, authenticated;
grant select on table public.speakers to authenticated;
grant update (name) on table public.speakers to authenticated;
grant select, insert, update, delete on table public.speakers to service_role;

create policy "Owners can read their speakers"
on public.speakers for select to authenticated
using ((select auth.uid()) = owner_id);

create policy "Owners can rename their speakers"
on public.speakers for update to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

revoke all on function public.create_editorial_speaker() from public;
grant execute on function public.create_editorial_speaker() to service_role;
