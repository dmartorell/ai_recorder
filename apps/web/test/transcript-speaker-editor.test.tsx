import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const from = vi.hoisted(() => vi.fn());
vi.mock("../src/lib/supabase", () => ({ supabase: { from } }));

import { TranscriptSpeakerEditor } from "../src/features/audio/transcript-speaker-editor";
import type { Segment, Speaker } from "../src/features/audio/audio-types";

const segment: Segment = {
  id: "segment-1", automatic_speaker_id: "automatic-1", ordinal: 0,
  content: "Automatic text", correction: "Corrected text", start_time_ms: 10_000, end_time_ms: 12_000
};
const speakers: Speaker[] = [
  { id: "automatic-1", editorial_id: "editorial-1", automatic_speaker_id: "automatic-1", provider_label: "S1", ordinal: 0, name: "Journalist" },
  { id: "editorial-2", editorial_id: "editorial-2", automatic_speaker_id: null, provider_label: "Speaker", ordinal: 1, name: "Editor" }
];

function renderEditor(currentSegment = segment) {
  return render(<QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>
    <TranscriptSpeakerEditor audioID="audio-1" segment={currentSegment} speakers={speakers} automaticSpeakerLabel="Journalist" />
  </QueryClientProvider>);
}

beforeEach(() => vi.clearAllMocks());
afterEach(cleanup);

it("saves a Speaker correction without replacing the text correction", async () => {
  let resolve: (value: { error: null }) => void;
  const upsert = vi.fn().mockReturnValue(new Promise<{ error: null }>((complete) => { resolve = complete; }));
  from.mockReturnValue({ upsert });
  renderEditor();

  fireEvent.change(screen.getByLabelText("Speaker at 0:10"), { target: { value: "editorial-2" } });
  fireEvent.click(screen.getByRole("button", { name: "Save Speaker" }));
  await waitFor(() => expect(screen.getByRole("button", { name: "Saving" })).toBeDisabled());
  resolve!({ error: null });

  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Saved"));
  expect(upsert).toHaveBeenCalledWith(
    { transcript_segment_id: "segment-1", speaker_id: "editorial-2" },
    { onConflict: "transcript_segment_id" }
  );
});

it("retains the selected Speaker after failure and retries", async () => {
  const upsert = vi.fn().mockResolvedValueOnce({ error: { message: "offline" } }).mockResolvedValueOnce({ error: null });
  from.mockReturnValue({ upsert });
  renderEditor();

  fireEvent.change(screen.getByLabelText("Speaker at 0:10"), { target: { value: "editorial-2" } });
  fireEvent.click(screen.getByRole("button", { name: "Save Speaker" }));
  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Could not save."));
  expect(screen.getByLabelText("Speaker at 0:10")).toHaveValue("editorial-2");
  fireEvent.click(screen.getByRole("button", { name: "Retry" }));
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Saved"));
});

it("exposes the automatic Speaker and reverts only Speaker attribution", async () => {
  const eq = vi.fn().mockResolvedValue({ error: null });
  from.mockReturnValue({ delete: vi.fn().mockReturnValue({ eq }) });
  renderEditor({ ...segment, speakerCorrectionID: "editorial-2" });

  fireEvent.click(screen.getByText("View automatic Speaker"));
  expect(screen.getByLabelText("Automatic Speaker")).toHaveTextContent("Journalist");
  fireEvent.click(screen.getByRole("button", { name: "Revert Speaker" }));

  await waitFor(() => expect(eq).toHaveBeenCalledWith("transcript_segment_id", "segment-1"));
  expect(screen.getByText("Text correction: Corrected text")).toBeInTheDocument();
});
