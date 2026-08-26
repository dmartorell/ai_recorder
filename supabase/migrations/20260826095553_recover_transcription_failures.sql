alter table public.transcription_jobs
  add column attempt_phase text check (attempt_phase in ('submit', 'ingest')),
  add column attempt_count integer not null default 0 check (attempt_count between 0 and 3),
  add column failed_at timestamptz,
  add column provider_cleanup_state text not null default 'not_started'
    check (provider_cleanup_state in ('not_started', 'pending', 'complete', 'failed')),
  add column provider_cleanup_attempt_count integer not null default 0
    check (provider_cleanup_attempt_count between 0 and 3),
  add column provider_cleanup_failed_at timestamptz,
  add column provider_cleanup_claim uuid;

update public.transcription_jobs
set provider_cleanup_state = 'pending'
where state = 'complete' and provider_cleanup_state = 'not_started';

create function public.fail_transcription_attempt(p_job_id uuid, p_phase text)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.transcription_jobs;
  next_attempt_count integer;
begin
  if p_phase not in ('submit', 'ingest') then
    raise exception 'invalid transcription attempt phase' using errcode = 'P0001';
  end if;

  select * into job from public.transcription_jobs where id = p_job_id for update;
  if not found then
    raise exception 'transcription job not found' using errcode = 'P0001';
  end if;
  if (p_phase = 'submit' and job.state <> 'queued')
    or (p_phase = 'ingest' and job.state <> 'processing') then
    raise exception 'transcription job is not active for this phase' using errcode = 'P0001';
  end if;
  if job.attempt_phase is not null and job.attempt_phase <> p_phase then
    raise exception 'transcription attempt phase changed unexpectedly' using errcode = 'P0001';
  end if;

  next_attempt_count := job.attempt_count + 1;
  update public.transcription_jobs
  set attempt_phase = p_phase,
      attempt_count = next_attempt_count,
      state = case when next_attempt_count = 3 then 'failed' else state end,
      submission_claim = case when next_attempt_count = 3 then null else submission_claim end,
      failed_at = case when next_attempt_count = 3 then now() else null end,
      updated_at = now()
  where id = job.id
  returning * into job;

  return next job;
end;
$$;

create function public.retry_failed_transcription(p_job_id uuid)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.transcription_jobs;
begin
  select * into job from public.transcription_jobs where id = p_job_id for update;
  if not found then
    raise exception 'transcription job not found' using errcode = 'P0001';
  end if;
  if job.state <> 'failed' then
    raise exception 'transcription job is not failed' using errcode = 'P0001';
  end if;

  update public.transcription_jobs
  set state = case when provider_job_id is null then 'queued' else 'processing' end,
      attempt_phase = null,
      attempt_count = 0,
      failed_at = null,
      submission_claim = null,
      updated_at = now()
  where id = job.id
  returning * into job;

  return next job;
end;
$$;

create function public.claim_provider_cleanup(p_job_id uuid)
returns table (transcription_job_id uuid, provider_cleanup_claim uuid, provider_job_id text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update public.transcription_jobs as job
  set provider_cleanup_claim = pg_catalog.gen_random_uuid(),
      updated_at = now()
  where job.id = p_job_id
    and job.state = 'complete'
    and job.provider_cleanup_state = 'pending'
    and job.provider_cleanup_claim is null
  returning job.id, job.provider_cleanup_claim, job.provider_job_id;
end;
$$;

create function public.complete_provider_cleanup(p_job_id uuid, p_claim uuid)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.transcription_jobs;
begin
  update public.transcription_jobs
  set provider_cleanup_state = 'complete',
      provider_cleanup_claim = null,
      updated_at = now()
  where id = p_job_id
    and state = 'complete'
    and provider_cleanup_state = 'pending'
    and provider_cleanup_claim = p_claim
  returning * into job;

  if found then
    return next job;
  end if;

  select * into job from public.transcription_jobs where id = p_job_id;
  if found then
    return next job;
  end if;
end;
$$;

create function public.fail_provider_cleanup(p_job_id uuid, p_claim uuid)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.transcription_jobs;
  next_attempt_count integer;
begin
  select * into job from public.transcription_jobs where id = p_job_id for update;
  if not found then
    raise exception 'transcription job not found' using errcode = 'P0001';
  end if;
  if job.state <> 'complete'
    or job.provider_cleanup_state <> 'pending'
    or job.provider_cleanup_claim is distinct from p_claim then
    return next job;
    return;
  end if;

  next_attempt_count := job.provider_cleanup_attempt_count + 1;
  update public.transcription_jobs
  set provider_cleanup_attempt_count = next_attempt_count,
      provider_cleanup_state = case when next_attempt_count = 3 then 'failed' else 'pending' end,
      provider_cleanup_claim = null,
      provider_cleanup_failed_at = case when next_attempt_count = 3 then now() else null end,
      updated_at = now()
  where id = job.id
  returning * into job;

  return next job;
end;
$$;

alter function public.complete_transcription_ingestion(uuid, text, jsonb)
  rename to preserve_automatic_transcript;
revoke all on function public.preserve_automatic_transcript(uuid, text, jsonb) from public, service_role;

create function public.complete_transcription_ingestion(
  p_job_id uuid,
  p_artifact_key text,
  p_transcript jsonb
)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.transcription_jobs;
begin
  select * into job
  from public.preserve_automatic_transcript(p_job_id, p_artifact_key, p_transcript);

  update public.transcription_jobs
  set provider_cleanup_state = 'pending',
      updated_at = now()
  where id = job.id
    and state = 'complete'
    and provider_cleanup_state = 'not_started';

  select * into job from public.transcription_jobs where id = p_job_id;
  return next job;
end;
$$;

revoke all on function public.fail_transcription_attempt(uuid, text) from public;
revoke all on function public.retry_failed_transcription(uuid) from public;
revoke all on function public.claim_provider_cleanup(uuid) from public;
revoke all on function public.complete_provider_cleanup(uuid, uuid) from public;
revoke all on function public.fail_provider_cleanup(uuid, uuid) from public;
revoke all on function public.complete_transcription_ingestion(uuid, text, jsonb) from public;

grant execute on function public.fail_transcription_attempt(uuid, text) to service_role;
grant execute on function public.retry_failed_transcription(uuid) to service_role;
grant execute on function public.claim_provider_cleanup(uuid) to service_role;
grant execute on function public.complete_provider_cleanup(uuid, uuid) to service_role;
grant execute on function public.fail_provider_cleanup(uuid, uuid) to service_role;
grant execute on function public.complete_transcription_ingestion(uuid, text, jsonb) to service_role;
