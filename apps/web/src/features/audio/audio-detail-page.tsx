import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { PrivateAudioPlayer } from "./private-audio-player";
import { Transcript } from "./transcript";
import { useAudioDetail } from "./audio-queries";
import { audioBackupFor, type Segment } from "./audio-types";
export function AudioDetailPage() { const { audioID } = useParams(); const query = useAudioDetail(audioID); const [time, setTime] = useState(0); const [seekTo, setSeekTo] = useState<number>();
  if (query.isPending) return <p role="status">Loading Audio…</p>; if (query.isError) return <p role="alert">This Audio is unavailable.</p>; if (!query.data) return <p role="alert">This Audio is unavailable.</p>;
  const { audio, transcriptionState, speakers, segments } = query.data; const backedUp = audioBackupFor(audio)?.state === "backed_up"; const active = segments.find((segment) => time * 1000 >= segment.start_time_ms && time * 1000 <= segment.end_time_ms)?.id;
  function select(segment: Segment) { setSeekTo(segment.start_time_ms / 1000); setTime(segment.start_time_ms / 1000); }
  return <main><Link to="/audios">Back to Audio</Link><h1>{audio.title_snapshot}</h1><p>Cloud audio: {backedUp ? "Backed up" : "Not backed up"}</p><p>Transcription: {transcriptionState}</p><PrivateAudioPlayer audioID={audio.id} backedUp={backedUp} durationMilliseconds={audio.duration_milliseconds} onTimeChange={setTime} seekTo={seekTo} />{transcriptionState === "complete" ? <Transcript audioID={audio.id} speakers={speakers} segments={segments} activeID={active} onSelect={select} /> : <p role="status">Automatic Transcript {transcriptionState === "failed" ? "failed." : "is processing."}</p>}</main>;
}
