import { Link } from "react-router-dom";
import { useAudios } from "./audio-queries";
import { audioBackupFor, type Audio } from "./audio-types";
const locale = navigator.language.startsWith("es") ? "es" : "en";
function duration(milliseconds: number) { const seconds = Math.round(milliseconds / 1000); return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`; }
function backup(audio: Audio) { return audioBackupFor(audio)?.state === "backed_up" ? "Backed up" : "Not backed up"; }
export function AudioLibraryPage() { const query = useAudios(); if (query.isPending) return <p role="status">Loading Audio…</p>; if (query.isError) return <p role="alert">Your Audio library is unavailable.</p>; if (!query.data?.length) return <main><h1>Audio</h1><p>No Audio is available yet.</p></main>;
  return <main><h1>Audio</h1><ul className="audio-list">{query.data.map((audio) => <li key={audio.id}><Link to={`/audios/${audio.id}`}><strong>{audio.title_snapshot}</strong><span>{new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(audio.capture_started_at))} · {duration(audio.duration_milliseconds)} · {audio.transcription_language}</span><span>{backup(audio)}</span></Link></li>)}</ul></main>;
}
