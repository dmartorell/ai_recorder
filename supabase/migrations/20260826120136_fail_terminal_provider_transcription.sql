create function public.fail_terminal_provider_transcription(p_provider_job_id text)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.transcription_jobs;
begin
  update public.transcription_jobs
  set state = 'failed',
      submission_claim = null,
      failed_at = now(),
      updated_at = now()
  where provider_job_id = p_provider_job_id
    and state = 'processing'
  returning * into job;

  if found then
    return next job;
  end if;
end;
$$;

revoke all on function public.fail_terminal_provider_transcription(text) from public;
grant execute on function public.fail_terminal_provider_transcription(text) to service_role;
