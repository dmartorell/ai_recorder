export type BackupState = "uploading" | "backed_up" | "cancelled";
export type TranscriptionState = "not_started" | "queued" | "processing" | "complete" | "failed";
export interface AudioBackup { id?: string; state: BackupState; }
export interface Audio { id: string; title_snapshot: string; capture_started_at: string; duration_milliseconds: number; transcription_language: string; audio_backups: AudioBackup[] | AudioBackup | null; }
export function audioBackupFor(audio: Audio): AudioBackup | null { return Array.isArray(audio.audio_backups) ? (audio.audio_backups[0] ?? null) : audio.audio_backups; }
export interface Speaker { id: string; provider_label: string; ordinal: number; editorial_id?: string; name: string | null; }
export interface Segment { id: string; automatic_speaker_id: string; ordinal: number; content: string; start_time_ms: number; end_time_ms: number; }
export interface AudioDetail { audio: Audio; transcriptionState: TranscriptionState; speakers: Speaker[]; segments: Segment[]; }
