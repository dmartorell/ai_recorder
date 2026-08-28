begin;

create extension if not exists pgtap with schema extensions;
select plan(123);

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
  'audios has row-level security enabled'
)
from pg_class
where oid = 'public.audios'::regclass;

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

select is_empty(
  $$ select * from public.audios $$,
  'the owner cannot read another owner catalog metadata'
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
  $$ select count(*)::integer from begin_audio_backup(
       '11111111-1111-1111-1111-111111111111',
       'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
       1024,
       repeat('a', 64),
       'english',
       'Backup-time title',
       '2026-08-28T10:32:00Z'::timestamptz,
       61000
     ) $$,
  array[1],
  'beginning a backup creates its cloud Audio catalog record'
);

select results_eq(
  $$ select title_snapshot || ':' || duration_milliseconds || ':' || transcription_language
     from public.audios
     where owner_id = '11111111-1111-1111-1111-111111111111' $$,
  array['Backup-time title:61000:english'],
  'the cloud Audio retains its backup-time metadata snapshot'
);

select results_eq(
  $$ select audio_id from public.audio_backups
     where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  array[(select id from public.audios where owner_id = '11111111-1111-1111-1111-111111111111')],
  'the backup lifecycle links to but does not replace its cloud Audio'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select is_empty(
  $$ select * from public.audios $$,
  'another user cannot read the owner cloud Audio metadata'
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
  $$ select state from public.fail_transcription_attempt(
       (select id from public.transcription_jobs
        where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'submit'
     ) $$,
  array['queued'],
  'the first transient submission failure remains retryable'
);

select results_eq(
  $$ select state from public.fail_transcription_attempt(
       (select id from public.transcription_jobs
        where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'submit'
     ) $$,
  array['queued'],
  'the second transient submission failure remains retryable'
);

select results_eq(
  $$ select state from public.fail_transcription_attempt(
       (select id from public.transcription_jobs
        where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'submit'
     ) $$,
  array['failed'],
  'the third submission failure is terminal'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ select state from public.transcription_jobs $$,
  array['failed'],
  'the owner can read a failed transcription job'
);
select throws_ok(
  $$ select * from public.retry_failed_transcription(
       (select id from public.transcription_jobs
        where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')
     ) $$,
  '42501',
  null,
  'authenticated users cannot retry transcription jobs directly'
);
select throws_ok(
  $$ select * from public.fail_transcription_attempt(
       (select id from public.transcription_jobs
        where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'submit'
     ) $$,
  '42501',
  null,
  'authenticated users cannot record transcription failures directly'
);
select throws_ok(
  $$ select * from public.fail_terminal_provider_transcription('terminal-provider-job') $$,
  '42501',
  null,
  'authenticated users cannot record terminal provider failures directly'
);
reset role;

select results_eq(
  $$ select state || ':' || coalesce(provider_job_id, '')
       from public.retry_failed_transcription(
         (select id from public.transcription_jobs
          where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')
       ) $$,
  array['queued:'],
  'an explicit retry resets a failed pre-submission job without changing its backup'
);

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

insert into public.audio_backups (id, owner_id, local_audio_id, object_key, byte_count, sha256, state, completed_at)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '11111111-1111-1111-1111-111111111111', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'original-audio/terminal-provider-failure', 1024, repeat('c', 64), 'backed_up', now());

select results_eq(
  $$ select state from public.record_transcription_submission(
       (select id from public.enqueue_transcription_job('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')),
       'terminal-provider-job'
     ) $$,
  array['processing'],
  'a provider submission is processing before a terminal provider failure'
);

select results_eq(
  $$ select state from public.fail_terminal_provider_transcription('terminal-provider-job') $$,
  array['failed'],
  'a terminal provider failure records the processing job as failed without provider details'
);

select results_eq(
  $$ select state from public.fail_transcription_attempt(
       (select id from public.transcription_jobs
        where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'ingest'
     ) $$,
  array['processing'],
  'the first transient ingestion failure remains retryable'
);

select results_eq(
  $$ select state from public.fail_transcription_attempt(
       (select id from public.transcription_jobs
        where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'ingest'
     ) $$,
  array['processing'],
  'the second transient ingestion failure remains retryable'
);

select results_eq(
  $$ select state from public.fail_transcription_attempt(
       (select id from public.transcription_jobs
        where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
       'ingest'
     ) $$,
  array['failed'],
  'the third ingestion failure is terminal'
);

select results_eq(
  $$ select count(*)::integer from public.automatic_transcripts $$,
  array[0],
  'a terminal ingestion failure preserves the absence of an automatic transcript'
);

select results_eq(
  $$ select state from public.retry_failed_transcription(
       (select id from public.transcription_jobs
        where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')
     ) $$,
  array['processing'],
  'an explicit retry preserves an accepted provider job for ingestion'
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
  $$ select provider_cleanup_state from public.transcription_jobs
     where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  array['pending'],
  'ingestion makes provider cleanup pending after preserving the transcript'
);

select results_eq(
  $$ with claimed as (
       select * from public.claim_provider_cleanup(
         (select id from public.transcription_jobs
          where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')
       )
     )
     select provider_cleanup_state
     from public.fail_provider_cleanup(
       (select transcription_job_id from claimed),
       (select provider_cleanup_claim from claimed)
     ) $$,
  array['pending'],
  'the first cleanup failure remains pending'
);

select results_eq(
  $$ with claimed as (
       select * from public.claim_provider_cleanup(
         (select id from public.transcription_jobs
          where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')
       )
     )
     select provider_cleanup_state
     from public.fail_provider_cleanup(
       (select transcription_job_id from claimed),
       (select provider_cleanup_claim from claimed)
     ) $$,
  array['pending'],
  'the second cleanup failure remains pending'
);

select results_eq(
  $$ with claimed as (
       select * from public.claim_provider_cleanup(
         (select id from public.transcription_jobs
          where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc')
       )
     )
     select provider_cleanup_state
     from public.fail_provider_cleanup(
       (select transcription_job_id from claimed),
       (select provider_cleanup_claim from claimed)
     ) $$,
  array['failed'],
  'the third cleanup failure is terminal without changing transcription completion'
);

select results_eq(
  $$ select count(*)::integer from public.automatic_transcripts $$,
  array[1],
  'a terminal cleanup failure preserves the completed automatic transcript'
);

select results_eq(
  $$ select state from public.transcription_jobs
     where backup_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc' $$,
  array['complete'],
  'a terminal cleanup failure retains transcription completion'
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
  $$ update public.automatic_transcripts set provider_job_id = 'mutated' $$,
  '42501', null,
  'an authenticated user cannot update automatic transcripts'
);
select throws_ok(
  $$ delete from public.automatic_transcripts $$,
  '42501', null,
  'an authenticated user cannot delete automatic transcripts'
);
select throws_ok(
  $$ update public.automatic_speakers set provider_label = 'mutated' $$,
  '42501', null,
  'an authenticated user cannot update automatic speakers'
);
select throws_ok(
  $$ delete from public.automatic_speakers $$,
  '42501', null,
  'an authenticated user cannot delete automatic speakers'
);
select throws_ok(
  $$ update public.transcript_segments set content = 'mutated' $$,
  '42501', null,
  'an authenticated user cannot update transcript segments'
);
select throws_ok(
  $$ delete from public.transcript_segments $$,
  '42501', null,
  'an authenticated user cannot delete transcript segments'
);
select throws_ok(
  $$ update public.transcript_words set content = 'mutated' $$,
  '42501', null,
  'an authenticated user cannot update transcript words'
);
select throws_ok(
  $$ delete from public.transcript_words $$,
  '42501', null,
  'an authenticated user cannot delete transcript words'
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

select ok(
  relrowsecurity,
  'speakers has row-level security enabled'
)
from pg_class
where oid = 'public.speakers'::regclass;

select ok(
  not has_table_privilege('anon', 'public.speakers', 'select,insert,update,delete'),
  'anon has no speakers privileges'
);

select ok(
  has_table_privilege('authenticated', 'public.speakers', 'select')
  and has_column_privilege('authenticated', 'public.speakers', 'name', 'update')
  and not has_column_privilege('authenticated', 'public.speakers', 'owner_id', 'update'),
  'authenticated can read and rename but not reassign speakers'
);

select results_eq(
  $$ select count(*)::integer from public.speakers $$,
  array[2],
  'ingestion creates one editorial speaker for each automatic speaker'
);

select results_eq(
  $$ select automatic.provider_label || ':' || coalesce(speaker.name, '')
     from public.speakers speaker
     join public.automatic_speakers automatic on automatic.id = speaker.automatic_speaker_id
     order by automatic.ordinal $$,
  array['S1:', 'S2:'],
  'new editorial speakers preserve automatic labels and start unnamed'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ select count(*)::integer from public.speakers $$,
  array[2],
  'the owner reads its audio-scoped editorial speakers'
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select is_empty(
  $$ select * from public.speakers $$,
  'another user cannot read editorial speakers'
);
select is_empty(
  $$ update public.speakers set name = 'Intruder' returning name $$,
  'another user cannot rename editorial speakers'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ select name from public.speakers speaker
     join public.automatic_speakers automatic on automatic.id = speaker.automatic_speaker_id
     where automatic.provider_label = 'S1' $$,
  array[null::text],
  'the denied rename leaves the speaker unnamed'
);
select results_eq(
  $$ update public.speakers set name = 'Journalist'
     where automatic_speaker_id = (select id from public.automatic_speakers where provider_label = 'S1')
     returning name $$,
  array['Journalist'],
  'the owner can rename its editorial speaker'
);
select throws_ok(
  $$ update public.automatic_speakers set provider_label = 'Changed' $$,
  '42501',
  null,
  'renaming an editorial speaker cannot mutate automatic speaker data'
);
select results_eq(
  $$ select automatic.provider_label || ':' || speaker.name
     from public.speakers speaker
     join public.automatic_speakers automatic on automatic.id = speaker.automatic_speaker_id
     where automatic.provider_label = 'S1' $$,
  array['S1:Journalist'],
  'the automatic provider label remains immutable after renaming'
);

select ok(
  relrowsecurity,
  'transcript_text_corrections has row-level security enabled'
)
from pg_class
where oid = 'public.transcript_text_corrections'::regclass;

select ok(
  not has_table_privilege('anon', 'public.transcript_text_corrections', 'select,insert,update,delete'),
  'anon has no transcript_text_corrections privileges'
);

select ok(
  has_table_privilege('authenticated', 'public.transcript_text_corrections', 'select,insert,update,delete')
  and not has_column_privilege('authenticated', 'public.transcript_text_corrections', 'owner_id', 'update'),
  'authenticated can manage correction text but not reassign its owner'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

insert into public.transcript_text_corrections (transcript_segment_id, content)
values ((select id from public.transcript_segments where ordinal = 0), 'Hola corregido');

select results_eq(
  $$ insert into public.transcript_text_corrections (transcript_segment_id, content)
     values ((select id from public.transcript_segments where ordinal = 0), 'Hola revisado')
     on conflict (transcript_segment_id) do update set content = excluded.content
     returning content $$,
  array['Hola revisado'],
  'the owner can replace one current text correction for its transcript segment'
);

select results_eq(
  $$ select count(*)::integer from public.transcript_text_corrections
     where transcript_segment_id = (select id from public.transcript_segments where ordinal = 0) $$,
  array[1],
  'a transcript segment has only one current text correction'
);
select throws_ok(
  $$ update public.transcript_text_corrections
     set transcript_segment_id = (select id from public.transcript_segments where ordinal = 1) $$,
  'P0001',
  'a text correction cannot change transcript segment',
  'an owner cannot reassign a text correction to another transcript segment'
);
select set_config(
  'test.transcript_segment_id',
  (select id::text from public.transcript_segments where ordinal = 0),
  true
);

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select is_empty(
  $$ select * from public.transcript_text_corrections $$,
  'another user cannot read the owner text correction'
);
select is_empty(
  $$ update public.transcript_text_corrections set content = 'Intruder' returning content $$,
  'another user cannot replace the owner text correction'
);
select is_empty(
  $$ delete from public.transcript_text_corrections returning content $$,
  'another user cannot revert the owner text correction'
);
select throws_ok(
  $$ insert into public.transcript_text_corrections (transcript_segment_id, content)
     values (current_setting('test.transcript_segment_id')::uuid, 'Intruder') $$,
  '42501', null,
  'another user cannot create a correction for the owner transcript segment'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ delete from public.transcript_text_corrections
     where transcript_segment_id = (select id from public.transcript_segments where ordinal = 0)
     returning content $$,
  array['Hola revisado'],
  'the owner can revert only its text correction'
);
select results_eq(
  $$ select content || ':' || automatic_speaker_id || ':' || ordinal || ':' || start_time_ms || ':' || end_time_ms
     from public.transcript_segments where ordinal = 0 $$,
  array[(select 'Hola,:' || id || ':0:100:400' from public.automatic_speakers where provider_label = 'S1')],
  'reverting a correction preserves automatic text, speaker, order, and timestamps'
);

select ok(
  relrowsecurity,
  'transcript_speaker_corrections has row-level security enabled'
)
from pg_class
where oid = 'public.transcript_speaker_corrections'::regclass;

select ok(
  not has_table_privilege('anon', 'public.transcript_speaker_corrections', 'select,insert,update,delete'),
  'anon has no transcript_speaker_corrections privileges'
);

select ok(
  has_table_privilege('authenticated', 'public.transcript_speaker_corrections', 'select,insert,update,delete')
  and not has_column_privilege('authenticated', 'public.transcript_speaker_corrections', 'owner_id', 'update'),
  'authenticated can manage speaker corrections but not reassign their owner'
);

select ok(
  has_column_privilege('authenticated', 'public.speakers', 'audio_id', 'insert')
  and has_column_privilege('authenticated', 'public.speakers', 'name', 'insert')
  and not has_column_privilege('authenticated', 'public.speakers', 'owner_id', 'insert'),
  'authenticated can create named speakers but cannot assign their owner'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';

with speaker as (
  insert into public.speakers (audio_id, name)
  values ((select audio_id from public.audio_backups where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'), 'Editor')
  returning id
)
select set_config('test.manual_speaker_id', (select id::text from speaker), true);

select results_eq(
  $$ select name from public.speakers where id = current_setting('test.manual_speaker_id')::uuid $$,
  array['Editor'],
  'the owner can add a named speaker to its audio'
);

select results_eq(
  $$ select count(*)::integer from public.speakers
     where audio_id = (select audio_id from public.audio_backups where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') $$,
  array[3],
  'adding a speaker retains the automatic speaker projections'
);

insert into public.transcript_text_corrections (transcript_segment_id, content)
values ((select id from public.transcript_segments where ordinal = 0), 'Texto corregido');

select results_eq(
  $$ insert into public.transcript_speaker_corrections (transcript_segment_id, speaker_id)
     values (
       (select id from public.transcript_segments where ordinal = 0),
       current_setting('test.manual_speaker_id')::uuid
     )
     returning speaker_id $$,
  array[current_setting('test.manual_speaker_id')::uuid],
  'the owner can assign an editorial speaker to its transcript segment'
);

select results_eq(
  $$ select count(*)::integer from public.transcript_speaker_corrections
     where transcript_segment_id = (select id from public.transcript_segments where ordinal = 0) $$,
  array[1],
  'a transcript segment has one current speaker correction'
);

select results_eq(
  $$ insert into public.transcript_speaker_corrections (transcript_segment_id, speaker_id)
     values (
       (select id from public.transcript_segments where ordinal = 0),
       (select speaker.id from public.speakers speaker
        join public.automatic_speakers automatic on automatic.id = speaker.automatic_speaker_id
        where automatic.provider_label = 'S2')
     )
     on conflict (transcript_segment_id) do update set speaker_id = excluded.speaker_id
     returning speaker_id $$,
  array[(select speaker.id from public.speakers speaker
         join public.automatic_speakers automatic on automatic.id = speaker.automatic_speaker_id
         where automatic.provider_label = 'S2')],
  'the owner can upsert a replacement speaker correction'
);

select throws_ok(
  $$ update public.transcript_speaker_corrections
     set transcript_segment_id = (select id from public.transcript_segments where ordinal = 1) $$,
  'P0001', 'a speaker correction can only change speaker',
  'an owner cannot reassign a speaker correction to another transcript segment'
);

reset role;
insert into public.audios (
  id, owner_id, local_audio_id, title_snapshot, capture_started_at, duration_milliseconds, transcription_language
) values (
  '99999999-9999-9999-9999-999999999999', '22222222-2222-2222-2222-222222222222',
  '88888888-8888-8888-8888-888888888888', 'Second Audio', now(), 0, 'english'
);

set local role authenticated;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
with speaker as (
  insert into public.speakers (audio_id, name)
  values ('99999999-9999-9999-9999-999999999999', 'Other Audio Speaker')
  returning id
)
select set_config('test.other_audio_speaker_id', (select id::text from speaker), true);

select throws_ok(
  $$ update public.transcript_speaker_corrections
     set speaker_id = current_setting('test.other_audio_speaker_id')::uuid
     where transcript_segment_id = (select id from public.transcript_segments where ordinal = 0) $$,
  'P0001', 'speaker correction must belong to the segment audio',
  'an owner cannot assign a speaker from another audio'
);

reset role;
select throws_ok(
  $$ update public.transcript_speaker_corrections
     set speaker_id = current_setting('test.other_audio_speaker_id')::uuid
     where transcript_segment_id = (select id from public.transcript_segments where ordinal = 0) $$,
  'P0001', 'speaker correction must belong to the segment audio',
  'database integrity rejects a cross-audio speaker correction'
);

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select is_empty(
  $$ select * from public.speakers where id = current_setting('test.manual_speaker_id')::uuid $$,
  'another user cannot read the owner manual speaker'
);
select is_empty(
  $$ select * from public.transcript_speaker_corrections $$,
  'another user cannot read the owner speaker correction'
);
select is_empty(
  $$ update public.transcript_speaker_corrections set speaker_id = current_setting('test.manual_speaker_id')::uuid returning speaker_id $$,
  'another user cannot update the owner speaker correction'
);
select is_empty(
  $$ delete from public.transcript_speaker_corrections returning speaker_id $$,
  'another user cannot delete the owner speaker correction'
);
select throws_ok(
  $$ insert into public.transcript_speaker_corrections (transcript_segment_id, speaker_id)
     values (
       (select id from public.transcript_segments where ordinal = 0),
       current_setting('test.manual_speaker_id')::uuid
     ) $$,
  '42501', null,
  'another user cannot create a speaker correction for the owner segment'
);

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$ delete from public.transcript_speaker_corrections
     where transcript_segment_id = (select id from public.transcript_segments where ordinal = 0)
     returning speaker_id $$,
  array[(select speaker.id from public.speakers speaker
         join public.automatic_speakers automatic on automatic.id = speaker.automatic_speaker_id
         where automatic.provider_label = 'S2')],
  'the owner can revert only its speaker correction'
);
select results_eq(
  $$ select correction.content || ':' || segment.automatic_speaker_id || ':' || segment.ordinal || ':' || segment.start_time_ms || ':' || segment.end_time_ms
     from public.transcript_segments segment
     join public.transcript_text_corrections correction on correction.transcript_segment_id = segment.id
     where segment.ordinal = 0 $$,
  array[(select 'Texto corregido:' || id || ':0:100:400' from public.automatic_speakers where provider_label = 'S1')],
  'reverting speaker attribution preserves the text correction and automatic source fields'
);

select * from finish();
rollback;
