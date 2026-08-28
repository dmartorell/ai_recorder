export type BackupState = "uploading" | "backed_up" | "cancelled";
export type TranscriptionState = "not_started" | "queued" | "processing" | "complete" | "failed";
export interface Audio { id: string; title_snapshot: string; capture_started_at: string; duration_milliseconds: number; transcription_language: string; audio_backups: { state: BackupState }[]; }
export interface Speaker { id: string; provider_label: string; ordinal: number; }
export interface Segment { id: string; automatic_speaker_id: string; ordinal: number; content: string; start_time_ms: number; end_time_ms: number; }
export interface AudioDetail { audio: Audio; transcriptionState: TranscriptionState; speakers: Speaker[]; segments: Segment[]; }
