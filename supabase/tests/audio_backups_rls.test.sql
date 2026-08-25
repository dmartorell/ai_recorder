begin;

create extension if not exists pgtap with schema extensions;
select plan(21);

insert into auth.users (id, email)
values
  ('11111111-1111-1111-1111-111111111111', 'owner@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'other@example.com');

insert into public.audio_backups (
  id,
  owner_id,
  local_audio_id,
  object_key,
  byte_count,
  sha256,
  state,
  completed_at
)
values
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'original-audio/opaque-owner-key/opaque-backup-key',
    1024,
    repeat('a', 64),
    'uploading',
    null
  ),
  (
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '22222222-2222-2222-2222-222222222222',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'original-audio/another-owner-key/another-backup-key',
    2048,
    repeat('b', 64),
    'backed_up',
    now()
  );

insert into public.audio_backup_parts (backup_id, part_number, etag, byte_count)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, 'part-etag', 1024);

select ok(
  relrowsecurity,
  'audio_backups has row-level security enabled'
)
from pg_class
where oid = 'public.audio_backups'::regclass;

select ok(
  relrowsecurity,
  'audio_backup_parts has row-level security enabled'
)
from pg_class
where oid = 'public.audio_backup_parts'::regclass;

select ok(
  not has_table_privilege('anon', 'public.audio_backups', 'select,insert,update,delete'),
  'anon has no audio_backups privileges'
);

select ok(
  not has_table_privilege('anon', 'public.audio_backup_parts', 'select,insert,update,delete'),
  'anon has no audio_backup_parts privileges'
);

select ok(
  has_table_privilege('authenticated', 'public.audio_backups', 'select')
  and not has_table_privilege('authenticated', 'public.audio_backups', 'insert,update,delete'),
  'authenticated has read-only audio_backups privileges'
);

select ok(
  has_table_privilege('service_role', 'public.audio_backups', 'select,insert,update,delete'),
  'service_role can persist authoritative audio backup state'
);

set local role anon;
select throws_ok(
  $$ select * from public.audio_backups $$,
  '42501',
  null,
  'anon cannot read audio_backups'
);

select throws_ok(
  $$ select * from public.audio_backup_parts $$,
  '42501',
  null,
  'anon cannot read audio_backup_parts'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$ select id from public.audio_backups order by id $$,
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid],
  'the owner reads only their audio backup'
);

select throws_ok(
  $$ insert into public.audio_backups (owner_id, local_audio_id, object_key, byte_count, sha256)
     values (
       '11111111-1111-1111-1111-111111111111',
       'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
       'original-audio/owner/new-backup',
       512,
       repeat('c', 64)
     ) $$,
  '42501',
  null,
  'the owner cannot create audio_backups directly'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ select id from public.audio_backups order by id $$,
  array['cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid],
  'another user cannot read the owner backup'
);

select throws_ok(
  $$ update public.audio_backups
     set state = 'cancelled'
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  '42501',
  null,
  'another user cannot update the owner backup'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$ select state from public.audio_backups
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  array['uploading'],
  'the denied update left the owner backup intact'
);

select throws_ok(
  $$ delete from public.audio_backups
     where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  '42501',
  null,
  'the owner cannot delete another user backup'
);

reset role;

select results_eq(
  $$ select count(*)::integer from enqueue_transcription_job('cccccccc-cccc-cccc-cccc-cccccccccccc') $$,
  array[1],
  'a verified backup creates one transcription job'
);

select results_eq(
  $$ select count(*)::integer from enqueue_transcription_job('cccccccc-cccc-cccc-cccc-cccccccccccc') $$,
  array[1],
  'a duplicate trigger reuses the transcription job'
);

select results_eq(
  $$ select count(*)::integer from public.transcription_jobs where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  array[1],
  'only one transcription job exists per backup'
);

select throws_ok(
  $$ select * from enqueue_transcription_job('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') $$,
  'P0001',
  'audio backup is not verified',
  'an unverified backup cannot create a transcription job'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ select state from public.transcription_jobs $$,
  array['queued'],
  'the owner can read its queued transcription job'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select is_empty(
  $$ select * from public.transcription_jobs $$,
  'another user cannot read the transcription job'
);

select throws_ok(
  $$ insert into public.transcription_jobs (backup_id, owner_id)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111') $$,
  '42501',
  null,
  'an authenticated user cannot create a transcription job directly'
);

select * from finish();
rollback;
