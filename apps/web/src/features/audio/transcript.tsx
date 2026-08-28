import type { Segment, Speaker } from "./audio-types";
import { AddSpeakerForm } from "./add-speaker-form";
import { SpeakerNameEditor } from "./speaker-name-editor";
import { TranscriptSpeakerEditor } from "./transcript-speaker-editor";
import { TranscriptTextEditor } from "./transcript-text-editor";

function timestamp(milliseconds: number) {
  const seconds = Math.floor(milliseconds / 1000);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

export function Transcript({ audioID, speakers, segments, activeID, onSelect }: { audioID: string; speakers: Speaker[]; segments: Segment[]; activeID?: string; onSelect(segment: Segment): void }) {
  const automaticSpeakers = new Map(speakers.map((speaker) => [speaker.automatic_speaker_id ?? speaker.id, speaker]));
  const editorialSpeakers = new Map(speakers.map((speaker) => [speaker.editorial_id ?? speaker.id, speaker]));

  return <section aria-label="Editorial Transcript">
    <h2>Editorial Transcript</h2>
    <AddSpeakerForm audioID={audioID} />
    {speakers.map((speaker) => speaker.editorial_id ? <SpeakerNameEditor key={speaker.id} audioID={audioID} speaker={speaker} /> : null)}
    {segments.length ? <ol className="transcript">{segments.map((segment) => {
      const automaticSpeaker = automaticSpeakers.get(segment.automatic_speaker_id);
      const effectiveSpeaker = segment.speakerCorrectionID ? editorialSpeakers.get(segment.speakerCorrectionID) : automaticSpeaker;
      const automaticSpeakerLabel = automaticSpeaker?.name ?? automaticSpeaker?.provider_label ?? "Speaker";
      const speakerLabel = effectiveSpeaker?.name ?? effectiveSpeaker?.provider_label ?? "Speaker";
      const content = segment.correction ?? segment.content;
      return <li key={segment.id} className={segment.id === activeID ? "active" : ""}>
        <button type="button" aria-label={`${speakerLabel}, ${timestamp(segment.start_time_ms)}`} onClick={() => onSelect(segment)}>
          <strong>{speakerLabel}</strong><time>{timestamp(segment.start_time_ms)}</time><span>{content}</span>
        </button>
        <TranscriptTextEditor audioID={audioID} segment={segment} speakerLabel={speakerLabel} />
        <TranscriptSpeakerEditor audioID={audioID} segment={segment} speakers={speakers} automaticSpeakerLabel={automaticSpeakerLabel} />
      </li>;
    })}</ol> : <p>No Automatic Transcript has been preserved yet.</p>}
  </section>;
}
