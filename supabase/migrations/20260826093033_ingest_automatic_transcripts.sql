create table public.automatic_transcripts (
  id uuid primary key default gen_random_uuid(),
  transcription_job_id uuid not null unique references public.transcription_jobs (id) on delete cascade,
  owner_id uuid not null references auth.users (id) on delete cascade,
  provider_job_id text not null unique,
  provider_reference uuid not null,
  source_artifact_key text not null unique,
  format_version text not null,
  created_at timestamptz not null default now(),
  unique (transcription_job_id, provider_reference)
);

create index automatic_transcripts_owner_id_idx on public.automatic_transcripts (owner_id);

create table public.automatic_speakers (
  id uuid primary key default gen_random_uuid(),
  automatic_transcript_id uuid not null references public.automatic_transcripts (id) on delete cascade,
  provider_label text not null,
  ordinal integer not null check (ordinal >= 0),
  unique (automatic_transcript_id, provider_label),
  unique (automatic_transcript_id, ordinal)
);

create index automatic_speakers_automatic_transcript_id_idx on public.automatic_speakers (automatic_transcript_id);

create table public.transcript_segments (
  id uuid primary key default gen_random_uuid(),
  automatic_transcript_id uuid not null references public.automatic_transcripts (id) on delete cascade,
  automatic_speaker_id uuid not null references public.automatic_speakers (id) on delete restrict,
  ordinal integer not null check (ordinal >= 0),
  content text not null,
  start_time_ms integer not null check (start_time_ms >= 0),
  end_time_ms integer not null check (end_time_ms >= start_time_ms),
  unique (automatic_transcript_id, ordinal)
);

create index transcript_segments_automatic_transcript_id_ordinal_idx on public.transcript_segments (automatic_transcript_id, ordinal);

create table public.transcript_words (
  id uuid primary key default gen_random_uuid(),
  transcript_segment_id uuid not null references public.transcript_segments (id) on delete cascade,
  ordinal integer not null check (ordinal >= 0),
  content text not null,
  start_time_ms integer not null check (start_time_ms >= 0),
  end_time_ms integer not null check (end_time_ms >= start_time_ms),
  confidence double precision not null check (confidence >= 0 and confidence <= 1),
  language text not null,
  provider_speaker_label text not null,
  unique (transcript_segment_id, ordinal)
);

create index transcript_words_transcript_segment_id_ordinal_idx on public.transcript_words (transcript_segment_id, ordinal);

alter table public.automatic_transcripts enable row level security;
alter table public.automatic_speakers enable row level security;
alter table public.transcript_segments enable row level security;
alter table public.transcript_words enable row level security;

revoke all on table public.automatic_transcripts, public.automatic_speakers, public.transcript_segments, public.transcript_words from anon, authenticated;
grant select on table public.automatic_transcripts, public.automatic_speakers, public.transcript_segments, public.transcript_words to authenticated;
grant select, insert, update, delete on table public.automatic_transcripts, public.automatic_speakers, public.transcript_segments, public.transcript_words to service_role;

create policy "Owners can read their automatic transcripts"
on public.automatic_transcripts for select to authenticated
using ((select auth.uid()) = owner_id);

create policy "Owners can read their automatic speakers"
on public.automatic_speakers for select to authenticated
using (
  exists (
    select 1 from public.automatic_transcripts transcript
    where transcript.id = automatic_transcript_id
      and transcript.owner_id = (select auth.uid())
  )
);

create policy "Owners can read their transcript segments"
on public.transcript_segments for select to authenticated
using (
  exists (
    select 1 from public.automatic_transcripts transcript
    where transcript.id = automatic_transcript_id
      and transcript.owner_id = (select auth.uid())
  )
);

create policy "Owners can read their transcript words"
on public.transcript_words for select to authenticated
using (
  exists (
    select 1
    from public.transcript_segments segment
    join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
    where segment.id = transcript_segment_id
      and transcript.owner_id = (select auth.uid())
  )
);

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
  transcript public.automatic_transcripts;
  item jsonb;
  alternative jsonb;
  word jsonb;
  segment jsonb;
  speaker_id uuid;
  segment_id uuid;
  current_speaker text;
  current_segment integer := -1;
  current_segment_start integer;
  current_segment_end integer;
  current_content text := '';
  word_ordinal integer := 0;
  segment_word_ordinal integer := 0;
  speaker_ordinal integer := 0;
  item_type text;
  item_content text;
  item_speaker text;
  item_language text;
  item_confidence double precision;
  item_start integer;
  item_end integer;
begin
  if p_artifact_key !~ '^automatic-transcripts/[0-9a-f-]{36}\.json$' then
    raise exception 'invalid transcript artifact' using errcode = 'P0001';
  end if;

  select * into job from public.transcription_jobs where id = p_job_id for update;
  if not found then raise exception 'transcription job not found' using errcode = 'P0001'; end if;

  select * into transcript from public.automatic_transcripts where transcription_job_id = job.id;
  if found then
    if transcript.source_artifact_key = p_artifact_key then
      return next job;
      return;
    end if;
    raise exception 'conflicting transcription result' using errcode = 'P0001';
  end if;

  if job.state <> 'processing' then
    raise exception 'transcription job is not processing' using errcode = 'P0001';
  end if;

  if job.provider_job_id is null
    or jsonb_typeof(p_transcript) <> 'object'
    or p_transcript ->> 'format' !~ '^2\.'
    or p_transcript #>> '{job,id}' is distinct from job.provider_job_id
    or p_transcript #>> '{job,tracking,reference}' is distinct from job.provider_reference::text
    or jsonb_typeof(p_transcript -> 'results') <> 'array' then
    raise exception 'invalid provider transcript' using errcode = 'P0001';
  end if;

  insert into public.automatic_transcripts (
    transcription_job_id, owner_id, provider_job_id, provider_reference, source_artifact_key, format_version
  ) values (
    job.id, job.owner_id, job.provider_job_id, job.provider_reference, p_artifact_key, p_transcript ->> 'format'
  ) returning * into transcript;

  for item in select value from jsonb_array_elements(p_transcript -> 'results') loop
    item_type := item ->> 'type';
    if item_type not in ('word', 'punctuation') then continue; end if;
    alternative := item -> 'alternatives' -> 0;
    if jsonb_typeof(alternative) <> 'object' then
      raise exception 'invalid provider transcript result' using errcode = 'P0001';
    end if;
    item_content := alternative ->> 'content';
    item_speaker := alternative ->> 'speaker';
    if item_content is null or item_content = '' or item_speaker is null or item_speaker = '' then
      raise exception 'invalid provider transcript result' using errcode = 'P0001';
    end if;

    if item_type = 'punctuation' then
      if current_segment < 0 then raise exception 'punctuation without word' using errcode = 'P0001'; end if;
      current_content := current_content || item_content;
      continue;
    end if;

    item_language := alternative ->> 'language';
    item_confidence := (alternative ->> 'confidence')::double precision;
    item_start := round((item ->> 'start_time')::numeric * 1000)::integer;
    item_end := round((item ->> 'end_time')::numeric * 1000)::integer;
    if item_language is null or item_language = '' or item_confidence is null or item_confidence < 0 or item_confidence > 1
      or item_start < 0 or item_end < item_start then
      raise exception 'invalid provider transcript word' using errcode = 'P0001';
    end if;

    if current_segment < 0 or current_speaker <> item_speaker then
      if current_segment >= 0 then
        insert into public.transcript_segments (
          automatic_transcript_id, automatic_speaker_id, ordinal, content, start_time_ms, end_time_ms
        ) values (
          transcript.id, speaker_id, current_segment, current_content, current_segment_start, current_segment_end
        ) returning id into segment_id;

        for word in select value from jsonb_array_elements(segment -> 'words') loop
          insert into public.transcript_words (
            transcript_segment_id, ordinal, content, start_time_ms, end_time_ms, confidence, language, provider_speaker_label
          ) values (
            segment_id, (word ->> 'ordinal')::integer, word ->> 'content', (word ->> 'start_time_ms')::integer,
            (word ->> 'end_time_ms')::integer, (word ->> 'confidence')::double precision, word ->> 'language', word ->> 'speaker'
          );
        end loop;
      end if;

      insert into public.automatic_speakers (automatic_transcript_id, provider_label, ordinal)
      values (transcript.id, item_speaker, speaker_ordinal)
      on conflict (automatic_transcript_id, provider_label) do update set provider_label = excluded.provider_label
      returning id into speaker_id;
      if not exists (select 1 from public.automatic_speakers where automatic_transcript_id = transcript.id and provider_label = item_speaker and ordinal < speaker_ordinal) then
        speaker_ordinal := speaker_ordinal + 1;
      end if;
      current_segment := current_segment + 1;
      current_speaker := item_speaker;
      current_segment_start := item_start;
      current_content := item_content;
      segment_word_ordinal := 0;
      segment := jsonb_build_object('words', jsonb_build_array());
    else
      current_content := current_content || ' ' || item_content;
      segment_word_ordinal := segment_word_ordinal + 1;
    end if;
    current_segment_end := item_end;
    segment := jsonb_set(segment, '{words}', (segment -> 'words') || jsonb_build_array(jsonb_build_object(
      'ordinal', segment_word_ordinal, 'content', item_content, 'start_time_ms', item_start, 'end_time_ms', item_end,
      'confidence', item_confidence, 'language', item_language, 'speaker', item_speaker
    )));
    word_ordinal := word_ordinal + 1;
  end loop;

  if current_segment < 0 then raise exception 'provider transcript has no words' using errcode = 'P0001'; end if;
  insert into public.transcript_segments (
    automatic_transcript_id, automatic_speaker_id, ordinal, content, start_time_ms, end_time_ms
  ) values (
    transcript.id, speaker_id, current_segment, current_content, current_segment_start, current_segment_end
  ) returning id into segment_id;
  for word in select value from jsonb_array_elements(segment -> 'words') loop
    insert into public.transcript_words (
      transcript_segment_id, ordinal, content, start_time_ms, end_time_ms, confidence, language, provider_speaker_label
    ) values (
      segment_id, (word ->> 'ordinal')::integer, word ->> 'content', (word ->> 'start_time_ms')::integer,
      (word ->> 'end_time_ms')::integer, (word ->> 'confidence')::double precision, word ->> 'language', word ->> 'speaker'
    );
  end loop;

  update public.transcription_jobs set state = 'complete', updated_at = now() where id = job.id returning * into job;
  return next job;
end;
$$;

revoke all on function public.complete_transcription_ingestion(uuid, text, jsonb) from public;
grant execute on function public.complete_transcription_ingestion(uuid, text, jsonb) to service_role;
