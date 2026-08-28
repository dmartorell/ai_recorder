create table public.audios (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  local_audio_id uuid not null,
  title_snapshot text not null check (btrim(title_snapshot) <> '' and char_length(title_snapshot) <= 500),
  capture_started_at timestamptz not null,
  duration_milliseconds bigint not null check (duration_milliseconds >= 0),
  transcription_language text not null check (transcription_language in ('spanish', 'english', 'spanish_english')),
  created_at timestamptz not null default now(),
  unique (owner_id, local_audio_id)
);

create index audios_owner_id_capture_started_at_idx
on public.audios (owner_id, capture_started_at desc);

alter table public.audio_backups
add column audio_id uuid references public.audios (id) on delete restrict,
add constraint audio_backups_audio_id_unique unique (audio_id);

alter table public.audios enable row level security;
revoke all on table public.audios from anon, authenticated;
grant select on table public.audios to authenticated;
grant select, insert, update, delete on table public.audios to service_role;
create policy "Owners can read their audios"
on public.audios for select to authenticated
using ((select auth.uid()) = owner_id);

drop function public.begin_audio_backup(uuid, uuid, bigint, text, text);

create function public.begin_audio_backup(
  p_owner_id uuid,
  p_local_audio_id uuid,
  p_byte_count bigint,
  p_sha256 text,
  p_transcription_language text,
  p_title_snapshot text,
  p_capture_started_at timestamptz,
  p_duration_milliseconds bigint
)
returns setof public.audio_backups
language plpgsql
security definer
set search_path = ''
as $$
declare
  audio public.audios;
  backup public.audio_backups;
begin
  if p_transcription_language not in ('spanish', 'english', 'spanish_english')
    or p_title_snapshot is null
    or btrim(p_title_snapshot) = ''
    or char_length(p_title_snapshot) > 500
    or p_capture_started_at is null
    or p_duration_milliseconds is null
    or p_duration_milliseconds < 0 then
    raise exception 'invalid audio catalog metadata' using errcode = 'P0001';
  end if;

  insert into public.audios (
    owner_id, local_audio_id, title_snapshot, capture_started_at,
    duration_milliseconds, transcription_language
  ) values (
    p_owner_id, p_local_audio_id, p_title_snapshot, p_capture_started_at,
    p_duration_milliseconds, p_transcription_language
  )
  on conflict (owner_id, local_audio_id) do update
  set owner_id = excluded.owner_id
  returning * into audio;

  select * into backup from public.audio_backups
  where owner_id = p_owner_id and local_audio_id = p_local_audio_id for update;

  if found then
    if backup.state = 'cancelled' then
      delete from public.audio_backup_parts where backup_id = backup.id;
      update public.audio_backups
      set audio_id = audio.id,
          object_key = 'original-audio/' || gen_random_uuid(),
          byte_count = p_byte_count,
          sha256 = p_sha256,
          transcription_language = p_transcription_language,
          state = 'uploading',
          r2_upload_id = null,
          r2_upload_claim = null,
          r2_upload_claimed_at = null,
          completed_at = null,
          updated_at = now()
      where id = backup.id
      returning * into backup;
    elsif backup.state <> 'uploading'
       or backup.byte_count <> p_byte_count
       or backup.sha256 <> p_sha256 then
      raise exception 'audio backup metadata conflict' using errcode = 'P0001';
    else
      update public.audio_backups
      set audio_id = audio.id,
          transcription_language = p_transcription_language,
          updated_at = now()
      where id = backup.id
      returning * into backup;
    end if;
  else
    insert into public.audio_backups (
      owner_id, local_audio_id, audio_id, object_key, byte_count, sha256,
      transcription_language
    ) values (
      p_owner_id, p_local_audio_id, audio.id,
      'original-audio/' || gen_random_uuid(), p_byte_count, p_sha256,
      p_transcription_language
    ) returning * into backup;
  end if;

  return next backup;
end;
$$;

revoke all on function public.begin_audio_backup(uuid, uuid, bigint, text, text, text, timestamptz, bigint) from public;
grant execute on function public.begin_audio_backup(uuid, uuid, bigint, text, text, text, timestamptz, bigint) to service_role;
