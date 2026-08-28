grant update (transcript_segment_id) on table public.transcript_text_corrections to authenticated;

create function public.prevent_transcript_text_correction_reassignment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.transcript_segment_id <> old.transcript_segment_id then
    raise exception 'a text correction cannot change transcript segment' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger transcript_text_corrections_prevent_reassignment
  before update on public.transcript_text_corrections
  for each row execute function public.prevent_transcript_text_correction_reassignment();

revoke all on function public.prevent_transcript_text_correction_reassignment() from public;
