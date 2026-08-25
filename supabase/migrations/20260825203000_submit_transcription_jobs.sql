alter table public.audio_backups
add column transcription_language text not null default 'spanish_english'
check (transcription_language in ('spanish', 'english', 'spanish_english'));

alter table public.transcription_jobs
add column transcription_language text not null default 'spanish_english'
check (transcription_language in ('spanish', 'english', 'spanish_english')),
add column provider_reference uuid not null default gen_random_uuid() unique,
add column provider_job_id text unique,
add column submission_claim uuid,
add column submission_started_at timestamptz,
add column submitted_at timestamptz;

create or replace function public.create_transcription_job_for_verified_backup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.transcription_jobs (backup_id, owner_id, transcription_language)
  values (new.id, new.owner_id, new.transcription_language)
  on conflict (backup_id) do nothing;
  return new;
end;
$$;

create function public.claim_transcription_submission(p_job_id uuid, p_submission_claim uuid)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare job public.transcription_jobs;
begin
  select * into job from public.transcription_jobs where id = p_job_id for update;
  if not found then raise exception 'transcription job not found' using errcode = 'P0001'; end if;
  if job.provider_job_id is not null then return next job; return; end if;
  if job.state <> 'queued' then raise exception 'transcription job is not queued' using errcode = 'P0001'; end if;
  if job.submission_claim is not null then return next job; return; end if;

  update public.transcription_jobs
  set submission_claim = p_submission_claim, submission_started_at = now(), updated_at = now()
  where id = job.id
  returning * into job;
  return next job;
end;
$$;

create function public.release_transcription_submission_claim(p_job_id uuid, p_submission_claim uuid)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare job public.transcription_jobs;
begin
  update public.transcription_jobs
  set submission_claim = null, updated_at = now()
  where id = p_job_id and provider_job_id is null and submission_claim = p_submission_claim
  returning * into job;
  if not found then select * into job from public.transcription_jobs where id = p_job_id; end if;
  return next job;
end;
$$;

create function public.record_transcription_submission(p_job_id uuid, p_provider_job_id text)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare job public.transcription_jobs;
begin
  update public.transcription_jobs
  set provider_job_id = p_provider_job_id,
      state = 'processing',
      submission_claim = null,
      submitted_at = now(),
      updated_at = now()
  where id = p_job_id and provider_job_id is null
  returning * into job;
  if not found then select * into job from public.transcription_jobs where id = p_job_id; end if;
  return next job;
end;
$$;

create function public.begin_audio_backup(
  p_owner_id uuid,
  p_local_audio_id uuid,
  p_byte_count bigint,
  p_sha256 text,
  p_transcription_language text
)
returns setof public.audio_backups
language plpgsql
security definer
set search_path = ''
as $$
declare backup public.audio_backups;
begin
  if p_transcription_language not in ('spanish', 'english', 'spanish_english') then
    raise exception 'invalid transcription language' using errcode = 'P0001';
  end if;

  select * into backup from public.audio_backups
  where owner_id = p_owner_id and local_audio_id = p_local_audio_id for update;

  if found then
    if backup.state = 'cancelled' then
      delete from public.audio_backup_parts where backup_id = backup.id;
      update public.audio_backups
      set object_key = 'original-audio/' || gen_random_uuid(),
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
      set transcription_language = p_transcription_language, updated_at = now()
      where id = backup.id
      returning * into backup;
    end if;
  else
    insert into public.audio_backups (owner_id, local_audio_id, object_key, byte_count, sha256, transcription_language)
    values (p_owner_id, p_local_audio_id, 'original-audio/' || gen_random_uuid(), p_byte_count, p_sha256, p_transcription_language)
    returning * into backup;
  end if;
  return next backup;
end;
$$;

revoke all on function public.begin_audio_backup(uuid, uuid, bigint, text, text) from public;
grant execute on function public.begin_audio_backup(uuid, uuid, bigint, text, text) to service_role;
revoke all on function public.claim_transcription_submission(uuid, uuid) from public;
revoke all on function public.release_transcription_submission_claim(uuid, uuid) from public;
revoke all on function public.record_transcription_submission(uuid, text) from public;
grant execute on function public.claim_transcription_submission(uuid, uuid) to service_role;
grant execute on function public.release_transcription_submission_claim(uuid, uuid) to service_role;
grant execute on function public.record_transcription_submission(uuid, text) to service_role;
