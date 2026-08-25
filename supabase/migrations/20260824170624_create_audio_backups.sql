create table public.audio_backups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  local_audio_id uuid not null,
  object_key text not null unique,
  byte_count bigint not null check (byte_count > 0),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  state text not null default 'uploading' check (state in ('uploading', 'backed_up', 'cancelled', 'failed')),
  r2_upload_id text unique,
  r2_upload_claim uuid,
  r2_upload_claimed_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, local_audio_id),
  check ((state = 'backed_up') = (completed_at is not null))
);

create table public.audio_backup_parts (
  backup_id uuid not null references public.audio_backups (id) on delete cascade,
  part_number integer not null check (part_number between 1 and 10000),
  etag text not null,
  byte_count bigint not null check (byte_count > 0),
  confirmed_at timestamptz not null default now(),
  primary key (backup_id, part_number)
);

create index audio_backups_owner_id_idx on public.audio_backups (owner_id);

-- This is called only with the service-role key by the Worker. The row lock makes
-- creation idempotent and turns a cancelled backup into a new object generation.
create function public.begin_audio_backup(
  p_owner_id uuid,
  p_local_audio_id uuid,
  p_byte_count bigint,
  p_sha256 text
)
returns setof public.audio_backups
language plpgsql
security definer
set search_path = ''
as $$
declare
  backup public.audio_backups;
begin
  select * into backup
  from public.audio_backups
  where owner_id = p_owner_id and local_audio_id = p_local_audio_id
  for update;

  if found then
    if backup.state = 'cancelled' then
      delete from public.audio_backup_parts where backup_id = backup.id;
      update public.audio_backups
      set object_key = 'original-audio/' || gen_random_uuid(),
          byte_count = p_byte_count,
          sha256 = p_sha256,
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
    end if;
  else
    insert into public.audio_backups (
      owner_id, local_audio_id, object_key, byte_count, sha256, state
    ) values (
      p_owner_id, p_local_audio_id, 'original-audio/' || gen_random_uuid(),
      p_byte_count, p_sha256, 'uploading'
    ) returning * into backup;
  end if;

  return next backup;
end;
$$;

revoke all on function public.begin_audio_backup(uuid, uuid, bigint, text) from public;
grant execute on function public.begin_audio_backup(uuid, uuid, bigint, text) to service_role;

alter table public.audio_backups enable row level security;
revoke all on table public.audio_backups from anon, authenticated;
grant select on table public.audio_backups to authenticated;
grant select, insert, update, delete on table public.audio_backups to service_role;
create policy "Owners can read their audio backups"
on public.audio_backups for select to authenticated
using ((select auth.uid()) = owner_id);

alter table public.audio_backup_parts enable row level security;
revoke all on table public.audio_backup_parts from anon, authenticated;
grant select, insert, update, delete on table public.audio_backup_parts to service_role;
