import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "../../lib/supabase";
import type { AudioDetail, Segment, Speaker } from "./audio-types";

function timestamp(milliseconds: number) {
  const seconds = Math.floor(milliseconds / 1000);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

export function TranscriptSpeakerEditor({ audioID, segment, speakers, automaticSpeakerLabel }: {
  audioID: string;
  segment: Segment;
  speakers: Speaker[];
  automaticSpeakerLabel: string;
}) {
  const automaticEditorialID = speakers.find((speaker) => speaker.automatic_speaker_id === segment.automatic_speaker_id)?.editorial_id;
  const [speakerID, setSpeakerID] = useState(segment.speakerCorrectionID ?? automaticEditorialID ?? "");
  const queryClient = useQueryClient();
  const updateSegment = (speakerCorrectionID: string | null) => queryClient.setQueryData<AudioDetail>(["audio", audioID], (current) => current && {
    ...current,
    segments: current.segments.map((item) => item.id === segment.id ? { ...item, speakerCorrectionID } : item)
  });
  const save = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("transcript_speaker_corrections").upsert(
        { transcript_segment_id: segment.id, speaker_id: speakerID },
        { onConflict: "transcript_segment_id" }
      );
      if (error) throw new Error(error.message);
    },
    onSuccess: () => updateSegment(speakerID)
  });
  const revert = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("transcript_speaker_corrections").delete().eq("transcript_segment_id", segment.id);
      if (error) throw new Error(error.message);
    },
    onSuccess: () => {
      setSpeakerID(automaticEditorialID ?? "");
      updateSegment(null);
    }
  });
  const pending = save.isPending || revert.isPending;
  const error = save.isError || revert.isError;
  const retry = save.isError ? () => save.mutate() : () => revert.mutate();
  const time = timestamp(segment.start_time_ms);

  return <section aria-label={`Edit Speaker at ${time}`}>
    <form onSubmit={(event) => { event.preventDefault(); save.mutate(); }}>
      <label htmlFor={`segment-speaker-${segment.id}`}>Speaker at {time}</label>
      <select id={`segment-speaker-${segment.id}`} value={speakerID} onChange={(event) => setSpeakerID(event.target.value)} disabled={pending}>
        {speakers.map((speaker) => <option key={speaker.editorial_id ?? speaker.id} value={speaker.editorial_id ?? speaker.id}>
          {speaker.name ?? speaker.provider_label}
        </option>)}
      </select>
      <button type="submit" disabled={pending || !speakerID}>{save.isPending ? "Saving" : "Save Speaker"}</button>
      {segment.speakerCorrectionID ? <button type="button" disabled={pending} onClick={() => revert.mutate()}>{revert.isPending ? "Reverting" : "Revert Speaker"}</button> : null}
      {save.isSuccess || revert.isSuccess ? <span role="status">Saved</span> : null}
      {error ? <span role="alert">Could not save. <button type="button" onClick={retry}>Retry</button></span> : null}
    </form>
    <details><summary>View automatic Speaker</summary><p aria-label="Automatic Speaker">{automaticSpeakerLabel}</p></details>
    {segment.correction ? <p className="sr-only">Text correction: {segment.correction}</p> : null}
  </section>;
}
