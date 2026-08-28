import { useQuery } from "@tanstack/react-query";
import { supabase } from "../../lib/supabase";
import type { Audio, AudioDetail, Segment, Speaker, TranscriptionState } from "./audio-types";

async function fail(error: { message: string } | null) { if (error) throw new Error(error.message); }
export function useAudios() { return useQuery({ queryKey: ["audios"], queryFn: async (): Promise<Audio[]> => {
  const { data, error } = await supabase.from("audios").select("id,title_snapshot,capture_started_at,duration_milliseconds,transcription_language,audio_backups(state)").order("capture_started_at", { ascending: false }); await fail(error); return (data ?? []) as Audio[];
} }); }
export function useAudioDetail(audioID: string | undefined) { return useQuery({ queryKey: ["audio", audioID], enabled: Boolean(audioID), queryFn: async (): Promise<AudioDetail | undefined> => {
  const { data: audio, error: audioError } = await supabase.from("audios").select("id,title_snapshot,capture_started_at,duration_milliseconds,transcription_language,audio_backups(id,state)").eq("id", audioID!).maybeSingle(); await fail(audioError); if (!audio) return undefined;
  const backup = (audio.audio_backups as { id: string; state: string }[])[0]; if (!backup) return { audio: audio as Audio, transcriptionState: "not_started", speakers: [], segments: [] };
  const { data: jobs, error: jobsError } = await supabase.from("transcription_jobs").select("id,state").eq("backup_id", backup.id).limit(1); await fail(jobsError);
  const transcriptionState = (jobs?.[0]?.state ?? "not_started") as TranscriptionState; if (transcriptionState !== "complete") return { audio: audio as Audio, transcriptionState, speakers: [], segments: [] };
  const { data: transcripts, error: transcriptError } = await supabase.from("automatic_transcripts").select("id").eq("transcription_job_id", jobs![0].id).limit(1); await fail(transcriptError); if (!transcripts?.[0]) return { audio: audio as Audio, transcriptionState, speakers: [], segments: [] };
  const transcriptID = transcripts[0].id;
  const [speakersResult, segmentsResult] = await Promise.all([
    supabase.from("automatic_speakers").select("id,provider_label,ordinal").eq("automatic_transcript_id", transcriptID).order("ordinal"),
    supabase.from("transcript_segments").select("id,automatic_speaker_id,ordinal,content,start_time_ms,end_time_ms").eq("automatic_transcript_id", transcriptID).order("ordinal")
  ]); await fail(speakersResult.error); await fail(segmentsResult.error);
  return { audio: audio as Audio, transcriptionState, speakers: (speakersResult.data ?? []) as Speaker[], segments: (segmentsResult.data ?? []) as Segment[] };
} }); }
