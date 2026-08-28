import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "../../lib/supabase";
import type { AudioDetail, Segment } from "./audio-types";

export function TranscriptTextEditor({ audioID, segment, speakerLabel }: { audioID: string; segment: Segment; speakerLabel: string }) {
  const [draft, setDraft] = useState(segment.correction ?? segment.content);
  const queryClient = useQueryClient();
  const updateSegment = (correction: string | null) => queryClient.setQueryData<AudioDetail>(["audio", audioID], (current) => current && {
    ...current,
    segments: current.segments.map((item) => item.id === segment.id ? { ...item, correction } : item)
  });
  const save = useMutation({
    mutationFn: async () => {
      const content = draft.trim();
      if (!content) throw new Error("empty correction");
      const { error } = await supabase.from("transcript_text_corrections").upsert(
        { transcript_segment_id: segment.id, content },
        { onConflict: "transcript_segment_id" }
      );
      if (error) throw new Error(error.message);
      return content;
    },
    onSuccess: (content) => { setDraft(content); updateSegment(content); }
  });
  const revert = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("transcript_text_corrections").delete().eq("transcript_segment_id", segment.id);
      if (error) throw new Error(error.message);
    },
    onSuccess: () => { setDraft(segment.content); updateSegment(null); }
  });
  const error = save.isError || revert.isError;
  const pending = save.isPending || revert.isPending;
  const retry = save.isError ? () => save.mutate() : () => revert.mutate();
  const time = `${Math.floor(segment.start_time_ms / 60_000)}:${String(Math.floor(segment.start_time_ms / 1000) % 60).padStart(2, "0")}`;

  return <section aria-label={`Edit transcript text at ${time}`}>
    {segment.correction ? <span>Edited</span> : null}
    <form onSubmit={(event) => { event.preventDefault(); save.mutate(); }}>
      <label htmlFor={`segment-text-${segment.id}`}>Transcript text at {time}</label>
      <textarea id={`segment-text-${segment.id}`} value={draft} onChange={(event) => setDraft(event.target.value)} disabled={pending} />
      <button type="submit" disabled={pending}>{save.isPending ? "Saving" : "Save text"}</button>
      {segment.correction ? <button type="button" disabled={pending} onClick={() => revert.mutate()}>{revert.isPending ? "Reverting" : "Revert text"}</button> : null}
      {save.isSuccess || revert.isSuccess ? <span role="status">Saved</span> : null}
      {error ? <span role="alert">Could not save. <button type="button" onClick={retry}>Retry</button></span> : null}
    </form>
    <details><summary>View automatic text</summary><p>{segment.content}</p></details>
    <p className="sr-only">Speaker: {speakerLabel}</p>
  </section>;
}
