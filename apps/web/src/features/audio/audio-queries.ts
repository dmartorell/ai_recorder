import { useQuery } from "@tanstack/react-query";
import { supabase } from "../../lib/supabase";
import { audioBackupFor, type Audio, type AudioDetail, type Segment, type Speaker, type TranscriptionState } from "./audio-types";

async function fail(error: { message: string } | null) { if (error) throw new Error(error.message); }
export function useAudios() { return useQuery({ queryKey: ["audios"], queryFn: async (): Promise<Audio[]> => {
  const { data, error } = await supabase.from("audios").select("id,title_snapshot,capture_started_at,duration_milliseconds,transcription_language,audio_backups(state)").order("capture_started_at", { ascending: false }); await fail(error); return (data ?? []) as Audio[];
} }); }
export function useAudioDetail(audioID: string | undefined) { return useQuery({ queryKey: ["audio", audioID], enabled: Boolean(audioID), queryFn: async (): Promise<AudioDetail | undefined> => {
  const { data: audio, error: audioError } = await supabase.from("audios").select("id,title_snapshot,capture_started_at,duration_milliseconds,transcription_language,audio_backups(id,state)").eq("id", audioID!).maybeSingle(); await fail(audioError); if (!audio) return undefined;
  const backup = audioBackupFor(audio as Audio) as { id: string; state: string } | null; if (!backup) return { audio: audio as Audio, transcriptionState: "not_started", speakers: [], segments: [] };
  const { data: jobs, error: jobsError } = await supabase.from("transcription_jobs").select("id,state").eq("backup_id", backup.id).limit(1); await fail(jobsError);
  const transcriptionState = (jobs?.[0]?.state ?? "not_started") as TranscriptionState; if (transcriptionState !== "complete") return { audio: audio as Audio, transcriptionState, speakers: [], segments: [] };
  const { data: transcripts, error: transcriptError } = await supabase.from("automatic_transcripts").select("id").eq("transcription_job_id", jobs![0].id).limit(1); await fail(transcriptError); if (!transcripts?.[0]) return { audio: audio as Audio, transcriptionState, speakers: [], segments: [] };
  const transcriptID = transcripts[0].id;
  const [speakersResult, editorialSpeakersResult, segmentsResult] = await Promise.all([
    supabase.from("automatic_speakers").select("id,provider_label,ordinal").eq("automatic_transcript_id", transcriptID).order("ordinal"),
    supabase.from("speakers").select("id,automatic_speaker_id,name").eq("audio_id", audio.id),
    supabase.from("transcript_segments").select("id,automatic_speaker_id,ordinal,content,start_time_ms,end_time_ms").eq("automatic_transcript_id", transcriptID).order("ordinal")
  ]); await fail(speakersResult.error); await fail(editorialSpeakersResult.error); await fail(segmentsResult.error);
  const editorialByAutomaticID = new Map((editorialSpeakersResult.data ?? []).map((speaker) => [speaker.automatic_speaker_id, speaker]));
  const speakers = (speakersResult.data ?? []).map((speaker) => {
    const editorial = editorialByAutomaticID.get(speaker.id);
    return { ...speaker, editorial_id: editorial?.id, name: editorial?.name ?? null };
  }) as Speaker[];
  const segments = (segmentsResult.data ?? []) as Segment[];
  if (!segments.length) return { audio: audio as Audio, transcriptionState, speakers, segments };
  const { data: corrections, error: correctionsError } = await supabase
    .from("transcript_text_corrections")
    .select("transcript_segment_id,content")
    .in("transcript_segment_id", segments.map((segment) => segment.id));
  await fail(correctionsError);
  const correctionBySegmentID = new Map((corrections ?? []).map((correction) => [correction.transcript_segment_id, correction.content]));
  return { audio: audio as Audio, transcriptionState, speakers, segments: segments.map((segment) => ({ ...segment, correction: correctionBySegmentID.get(segment.id) ?? null })) };
} }); }
