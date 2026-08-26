begin;

create extension if not exists pgtap with schema extensions;
select plan(45);

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

select throws_ok(
  $$ update public.transcription_jobs set state = 'processing' $$,
  '42501',
  null,
  'an authenticated user cannot update a transcription job directly'
);

reset role;

select results_eq(
  $$ select transcription_language from public.transcription_jobs
     where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  array['spanish_english'],
  'a transcription job preserves the backup language'
);

select results_eq(
  $$ select count(distinct provider_reference)::integer from public.transcription_jobs
     where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  array[1],
  'the transcription job has one stable provider reference'
);

select results_eq(
  $$ select submission_claim from claim_transcription_submission(
       (select id from public.transcription_jobs where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
     ) $$,
  array['eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid],
  'claiming a queued job records an opaque submission claim'
);

select results_eq(
  $$ select state || ':' || provider_job_id from record_transcription_submission(
       (select id from public.transcription_jobs where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'speechmatics-job'
     ) $$,
  array['processing:speechmatics-job'],
  'recording provider acceptance moves the job from queued to processing'
);

select results_eq(
  $$ select state from complete_transcription_ingestion(
       (select id from public.transcription_jobs where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'automatic-transcripts/' || (select id from public.transcription_jobs where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')::text || '.json',
       jsonb_build_object(
         'format', '2.9',
         'job', jsonb_build_object(
           'id', 'speechmatics-job',
           'tracking', jsonb_build_object('reference', (select provider_reference::text from public.transcription_jobs where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'))
         ),
         'results', jsonb_build_array(
           jsonb_build_object('type', 'word', 'start_time', 0.1, 'end_time', 0.4, 'alternatives', jsonb_build_array(jsonb_build_object('content', 'Hola', 'confidence', 0.98, 'language', 'es', 'speaker', 'S1'))),
           jsonb_build_object('type', 'punctuation', 'start_time', 0.4, 'end_time', 0.4, 'alternatives', jsonb_build_array(jsonb_build_object('content', ',', 'speaker', 'S1'))),
           jsonb_build_object('type', 'word', 'start_time', 0.5, 'end_time', 0.9, 'alternatives', jsonb_build_array(jsonb_build_object('content', 'hello', 'confidence', 0.97, 'language', 'en', 'speaker', 'S2')))
         )
       )
     ) $$,
  array['complete'],
  'ingestion atomically completes a processing transcription job'
);

select results_eq(
  $$ select count(*)::integer from public.automatic_transcripts $$,
  array[1],
  'ingestion preserves one immutable automatic transcript'
);

select results_eq(
  $$ select provider_label from public.automatic_speakers order by ordinal $$,
  array['S1', 'S2'],
  'automatic speakers are scoped to the automatic transcript'
);

select results_eq(
  $$ select content from public.transcript_segments order by ordinal $$,
  array['Hola,', 'hello'],
  'recognized words and punctuation form ordered transcript segments'
);

select results_eq(
  $$ select start_time_ms || ':' || end_time_ms || ':' || confidence || ':' || language
     from public.transcript_words order by start_time_ms $$,
  array['100:400:0.98:es', '500:900:0.97:en'],
  'word timing confidence and language are persisted'
);

select results_eq(
  $$ select state from complete_transcription_ingestion(
       (select id from public.transcription_jobs where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'automatic-transcripts/' || (select id from public.transcription_jobs where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')::text || '.json',
       jsonb_build_object('format', 'not-used')
     ) $$,
  array['complete'],
  'duplicate completion with the same artifact is idempotent'
);

select throws_ok(
  $$ select * from complete_transcription_ingestion(
       (select id from public.transcription_jobs where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'automatic-transcripts/ffffffff-ffff-ffff-ffff-ffffffffffff.json',
       '{}'::jsonb
     ) $$,
  'P0001',
  'conflicting transcription result',
  'a second artifact cannot replace an automatic transcript'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ select count(*)::integer from public.automatic_transcripts $$,
  array[1],
  'the owner can read its automatic transcript'
);
select results_eq(
  $$ select count(*)::integer from public.automatic_speakers $$,
  array[2],
  'the owner can read its audio-scoped automatic speakers'
);
select results_eq(
  $$ select count(*)::integer from public.transcript_segments $$,
  array[2],
  'the owner can read its transcript segments'
);
select results_eq(
  $$ select count(*)::integer from public.transcript_words $$,
  array[2],
  'the owner can read its transcript words'
);
select throws_ok(
  $$ insert into public.automatic_transcripts (transcription_job_id, owner_id, provider_job_id, provider_reference, source_artifact_key, format_version)
     values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'provider', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'automatic-transcripts/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.json', '2.9') $$,
  '42501', null,
  'an authenticated user cannot write automatic transcripts directly'
);
select throws_ok(
  $$ insert into public.automatic_speakers (automatic_transcript_id, provider_label, ordinal) values ((select id from public.automatic_transcripts), 'S3', 2) $$,
  '42501', null,
  'an authenticated user cannot write automatic speakers directly'
);
select throws_ok(
  $$ insert into public.transcript_segments (automatic_transcript_id, automatic_speaker_id, ordinal, content, start_time_ms, end_time_ms) values ((select id from public.automatic_transcripts), (select id from public.automatic_speakers limit 1), 2, 'synthetic', 1, 2) $$,
  '42501', null,
  'an authenticated user cannot write transcript segments directly'
);
select throws_ok(
  $$ insert into public.transcript_words (transcript_segment_id, ordinal, content, start_time_ms, end_time_ms, confidence, language, provider_speaker_label) values ((select id from public.transcript_segments limit 1), 9, 'synthetic', 1, 2, 0.5, 'en', 'S1') $$,
  '42501', null,
  'an authenticated user cannot write transcript words directly'
);
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select is_empty($$ select * from public.automatic_transcripts $$, 'another user cannot read automatic transcripts');
select is_empty($$ select * from public.automatic_speakers $$, 'another user cannot read automatic speakers');
select is_empty($$ select * from public.transcript_segments $$, 'another user cannot read transcript segments');
select is_empty($$ select * from public.transcript_words $$, 'another user cannot read transcript words');

select * from finish();
rollback;
