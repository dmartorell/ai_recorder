import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const from = vi.hoisted(() => vi.fn());
vi.mock("../src/lib/supabase", () => ({ supabase: { from } }));

import { TranscriptTextEditor } from "../src/features/audio/transcript-text-editor";
import type { Segment } from "../src/features/audio/audio-types";

const automaticSegment: Segment = {
  id: "segment-1", automatic_speaker_id: "speaker-1", ordinal: 0,
  content: "Automatic text", start_time_ms: 10_000, end_time_ms: 12_000
};

function renderEditor(segment = automaticSegment) {
  return render(<QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>
    <TranscriptTextEditor audioID="audio-1" segment={segment} speakerLabel="Journalist" />
  </QueryClientProvider>);
}

beforeEach(() => vi.clearAllMocks());
afterEach(cleanup);

it("saves one current correction and identifies the edited text", async () => {
  let resolve: (value: { error: null }) => void;
  const upsert = vi.fn().mockReturnValue(new Promise<{ error: null }>((complete) => { resolve = complete; }));
  from.mockReturnValue({ upsert });
  renderEditor();

  const input = screen.getByLabelText("Transcript text at 0:10");
  expect(input).toHaveValue("Automatic text");
  fireEvent.change(input, { target: { value: "Corrected text" } });
  fireEvent.click(screen.getByRole("button", { name: "Save text" }));

  await waitFor(() => expect(screen.getByRole("button", { name: "Saving" })).toBeDisabled());
  resolve!({ error: null });
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Saved"));
  expect(from).toHaveBeenCalledWith("transcript_text_corrections");
  expect(upsert).toHaveBeenCalledWith(
    { transcript_segment_id: "segment-1", content: "Corrected text" },
    { onConflict: "transcript_segment_id" }
  );
});

it("retains the local draft and retries with generic error copy", async () => {
  const upsert = vi.fn().mockResolvedValueOnce({ error: { message: "offline" } }).mockResolvedValueOnce({ error: null });
  from.mockReturnValue({ upsert });
  renderEditor();

  const input = screen.getByLabelText("Transcript text at 0:10");
  fireEvent.change(input, { target: { value: "Corrected text" } });
  fireEvent.click(screen.getByRole("button", { name: "Save text" }));

  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Could not save."));
  expect(input).toHaveValue("Corrected text");
  fireEvent.click(screen.getByRole("button", { name: "Retry" }));
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Saved"));
  expect(input).toHaveValue("Corrected text");
});

it("exposes automatic text and reverts only the text correction", async () => {
  const eq = vi.fn().mockResolvedValue({ error: null });
  from.mockReturnValue({ delete: vi.fn().mockReturnValue({ eq }) });
  renderEditor({ ...automaticSegment, correction: "Corrected text" });

  expect(screen.getByText("Edited")).toBeInTheDocument();
  fireEvent.click(screen.getByText("View automatic text"));
  expect(screen.getByText("Automatic text")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Revert text" }));

  await waitFor(() => expect(eq).toHaveBeenCalledWith("transcript_segment_id", "segment-1"));
  expect(screen.getByLabelText("Transcript text at 0:10")).toHaveValue("Automatic text");
  expect(screen.getByText("Speaker: Journalist")).toBeInTheDocument();
});
