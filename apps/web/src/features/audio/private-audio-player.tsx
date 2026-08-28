import { useEffect, useRef, useState } from "react";
import { supabase, workerURL } from "../../lib/supabase";

export function PrivateAudioPlayer({ audioID, backedUp, durationMilliseconds, onTimeChange, seekTo }: { audioID: string; backedUp: boolean; durationMilliseconds: number; onTimeChange(time: number): void; seekTo?: number }) {
  const audio = useRef<HTMLAudioElement>(null); const renewed = useRef(false); const [url, setURL] = useState<string>(); const [error, setError] = useState(false); const [playing, setPlaying] = useState(false); const [speed, setSpeed] = useState(1);
  async function acquireURL() { const { data } = await supabase.auth.getSession(); if (!data.session || !workerURL) throw new Error("unavailable"); const response = await fetch(`${workerURL.replace(/\/$/, "")}/v1/audios/${audioID}/playback`, { headers: { Authorization: `Bearer ${data.session.access_token}` } }); if (!response.ok) throw new Error("unavailable"); const body: unknown = await response.json(); if (!body || typeof (body as { url?: unknown }).url !== "string") throw new Error("unavailable"); setURL((body as { url: string }).url); }
  useEffect(() => { renewed.current = false; setError(false); setURL(undefined); if (backedUp) void acquireURL().catch(() => setError(true)); }, [audioID, backedUp]);
  useEffect(() => { if (seekTo !== undefined && audio.current) audio.current.currentTime = seekTo; }, [seekTo]);
  if (!backedUp) return <p role="status">Cloud audio is not backed up yet.</p>;
  if (error) return <p role="alert">Audio playback is unavailable. Try again later.</p>;
  return <section aria-label="Audio player"><audio ref={audio} src={url} onTimeUpdate={(event) => onTimeChange(event.currentTarget.currentTime)} onPlay={() => setPlaying(true)} onPause={() => setPlaying(false)} onError={() => { if (!renewed.current) { renewed.current = true; void acquireURL().catch(() => setError(true)); } else setError(true); }} />
    <button type="button" disabled={!url} onClick={() => { const element = audio.current; if (!element) return; playing ? element.pause() : void element.play().catch(() => setError(true)); }}>{playing ? "Pause" : "Play"}</button>
    <button type="button" disabled={!url} onClick={() => { if (audio.current) audio.current.currentTime = Math.max(0, audio.current.currentTime - 10); }}>Back 10 seconds</button>
    <button type="button" disabled={!url} onClick={() => { if (audio.current) audio.current.currentTime = Math.min(durationMilliseconds / 1000, audio.current.currentTime + 10); }}>Forward 10 seconds</button>
    <label>Speed <select value={speed} onChange={(event) => { const next = Number(event.target.value); setSpeed(next); if (audio.current) audio.current.playbackRate = next; }}><option value="0.75">0.75×</option><option value="1">1×</option><option value="1.25">1.25×</option><option value="1.5">1.5×</option><option value="2">2×</option></select></label>
  </section>;
}
