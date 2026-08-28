import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "../../lib/supabase";
import type { Speaker } from "./audio-types";

export function SpeakerNameEditor({ audioID, speaker }: { audioID: string; speaker: Speaker }) {
  const [name, setName] = useState(speaker.name ?? speaker.provider_label);
  const queryClient = useQueryClient();
  const rename = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.from("speakers").update({ name }).eq("id", speaker.editorial_id!);
      if (error) throw new Error(error.message);
    },
    onSuccess: () => queryClient.setQueryData(["audio", audioID], (current: { speakers: Speaker[] } | undefined) => current && {
      ...current,
      speakers: current.speakers.map((item) => item.id === speaker.id ? { ...item, name } : item)
    })
  });

  return <form onSubmit={(event) => { event.preventDefault(); rename.mutate(); }}>
    <label htmlFor={`speaker-${speaker.id}`}>Speaker name</label>
    <input id={`speaker-${speaker.id}`} value={name} onChange={(event) => setName(event.target.value)} disabled={rename.isPending} />
    <button type="submit" disabled={rename.isPending}>{rename.isPending ? "Saving" : "Save"}</button>
    {rename.isSuccess ? <span role="status">Saved</span> : null}
    {rename.isError ? <span role="alert">Could not save. <button type="button" onClick={() => rename.mutate()}>Retry</button></span> : null}
  </form>;
}
