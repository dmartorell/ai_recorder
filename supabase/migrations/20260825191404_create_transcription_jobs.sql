create table public.transcription_jobs (
  id uuid primary key default gen_random_uuid(),
  backup_id uuid not null unique references public.audio_backups (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  state text not null default 'queued' check (state in ('queued', 'processing', 'complete', 'failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index transcription_jobs_owner_id_idx on public.transcription_jobs (owner_id);

create function public.create_transcription_job_for_verified_backup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.transcription_jobs (backup_id, owner_id)
  values (new.id, new.owner_id)
  on conflict (backup_id) do nothing;
  return new;
end;
$$;

create trigger create_transcription_job_after_backup_verification
after update of state on public.audio_backups
for each row
when (old.state is distinct from new.state and new.state = 'backed_up')
execute function public.create_transcription_job_for_verified_backup();

revoke all on function public.create_transcription_job_for_verified_backup() from public;

create function public.enqueue_transcription_job(p_backup_id uuid)
returns setof public.transcription_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  backup public.audio_backups;
  job public.transcription_jobs;
begin
  select * into backup
  from public.audio_backups
  where id = p_backup_id
  for update;

  if not found or backup.state <> 'backed_up' then
    raise exception 'audio backup is not verified' using errcode = 'P0001';
  end if;

  insert into public.transcription_jobs (backup_id, owner_id)
  values (backup.id, backup.owner_id)
  on conflict (backup_id) do update
    set backup_id = excluded.backup_id
  returning * into job;

  return next job;
end;
$$;

revoke all on function public.enqueue_transcription_job(uuid) from public;
grant execute on function public.enqueue_transcription_job(uuid) to service_role;

alter table public.transcription_jobs enable row level security;
revoke all on table public.transcription_jobs from anon, authenticated;
grant select on table public.transcription_jobs to authenticated;
grant select, insert, update, delete on table public.transcription_jobs to service_role;
create policy "Owners can read their transcription jobs"
on public.transcription_jobs for select to authenticated
using ((select auth.uid()) = owner_id);
