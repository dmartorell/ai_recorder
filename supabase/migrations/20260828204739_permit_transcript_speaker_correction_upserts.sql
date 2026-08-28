grant update on table public.transcript_speaker_corrections to authenticated;

create or replace function public.validate_transcript_speaker_correction_scope()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  segment_owner_id uuid;
  segment_audio_id uuid;
  speaker_owner_id uuid;
  speaker_audio_id uuid;
begin
  if tg_op = 'UPDATE'
    and (
      new.id is distinct from old.id
      or new.transcript_segment_id is distinct from old.transcript_segment_id
      or new.owner_id is distinct from old.owner_id
      or new.created_at is distinct from old.created_at
    ) then
    raise exception 'a speaker correction can only change speaker' using errcode = 'P0001';
  end if;

  select transcript.owner_id, backup.audio_id
  into segment_owner_id, segment_audio_id
  from public.transcript_segments segment
  join public.automatic_transcripts transcript on transcript.id = segment.automatic_transcript_id
  join public.transcription_jobs job on job.id = transcript.transcription_job_id
  join public.audio_backups backup on backup.id = job.backup_id
  where segment.id = new.transcript_segment_id;

  select owner_id, audio_id
  into speaker_owner_id, speaker_audio_id
  from public.speakers
  where id = new.speaker_id;

  if segment_owner_id is distinct from speaker_owner_id
    or segment_audio_id is distinct from speaker_audio_id then
    raise exception 'speaker correction must belong to the segment audio' using errcode = 'P0001';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_transcript_speaker_correction_scope() from public;
