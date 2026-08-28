import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "../../lib/supabase";
import type { AudioDetail, Speaker } from "./audio-types";

export function AddSpeakerForm({ audioID }: { audioID: string }) {
  const [draft, setDraft] = useState("");
  const [validationError, setValidationError] = useState(false);
  const queryClient = useQueryClient();
  const add = useMutation({
    mutationFn: async () => {
      const name = draft.trim();
      if (!name) throw new Error("empty speaker name");
      const { data, error } = await supabase
        .from("speakers")
        .insert({ audio_id: audioID, name })
        .select("id,automatic_speaker_id,name")
        .single();
      if (error) throw new Error(error.message);
      return data;
    },
    onSuccess: (speaker) => {
      setDraft("");
      setValidationError(false);
      queryClient.setQueryData<AudioDetail>(["audio", audioID], (current) => current && {
        ...current,
        speakers: [...current.speakers, {
          id: speaker.id,
          editorial_id: speaker.id,
          automatic_speaker_id: speaker.automatic_speaker_id,
          provider_label: "Speaker",
          ordinal: current.speakers.length,
          name: speaker.name
        } satisfies Speaker]
      });
    }
  });
  const submit = () => {
    if (!draft.trim()) {
      setValidationError(true);
      return;
    }
    setValidationError(false);
    add.mutate();
  };

  return <form onSubmit={(event) => { event.preventDefault(); submit(); }}>
    <label htmlFor={`new-speaker-${audioID}`}>New Speaker name</label>
    <input id={`new-speaker-${audioID}`} value={draft} onChange={(event) => setDraft(event.target.value)} disabled={add.isPending} />
    <button type="submit" disabled={add.isPending}>{add.isPending ? "Saving" : "Add Speaker"}</button>
    {add.isSuccess ? <span role="status">Saved</span> : null}
    {validationError ? <span role="alert">Enter a Speaker name.</span> : null}
    {add.isError ? <span role="alert">Could not save. <button type="button" onClick={() => add.mutate()}>Retry</button></span> : null}
  </form>;
}
