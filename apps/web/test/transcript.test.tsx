import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ComponentProps } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { Transcript } from "../src/features/audio/transcript";

const segment = { id: "segment-1", automatic_speaker_id: "speaker-1", ordinal: 0, content: "Synthetic segment", start_time_ms: 10_000, end_time_ms: 12_000 };
afterEach(cleanup);

function renderTranscript(props: ComponentProps<typeof Transcript>) {
  return render(<QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>
    <Transcript {...props} />
  </QueryClientProvider>);
}

it("seeks when a Transcript Segment is selected and identifies the active segment", () => {
  const select = vi.fn();
  renderTranscript({ audioID: "audio-1", speakers: [{ id: "speaker-1", provider_label: "S1", ordinal: 0, name: null }], segments: [segment], activeID: "segment-1", onSelect: select });
  const button = screen.getByRole("button", { name: "S1, 0:10" });
  expect(button.closest("li")).toHaveClass("active");
  fireEvent.click(button);
  expect(select).toHaveBeenCalledWith(segment);
});

it("uses the editorial name when one exists", () => {
  renderTranscript({ audioID: "audio-1", speakers: [{ id: "speaker-1", provider_label: "S1", ordinal: 0, name: "Journalist" }], segments: [segment], onSelect: vi.fn() });
  expect(screen.getByRole("button", { name: "Journalist, 0:10" })).toBeInTheDocument();
});

it("renders corrected editorial text with an Edited indicator while retaining its automatic source", () => {
  renderTranscript({ audioID: "audio-1", speakers: [{ id: "speaker-1", provider_label: "S1", ordinal: 0, name: null }], segments: [{ ...segment, correction: "Corrected segment" }], onSelect: vi.fn() });
  expect(screen.getByRole("heading", { name: "Editorial Transcript" })).toBeInTheDocument();
  expect(screen.getByText("Edited")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: "S1, 0:10" })).toHaveTextContent("Corrected segment");
  fireEvent.click(screen.getByText("View automatic text"));
  expect(screen.getByText("Synthetic segment")).toBeVisible();
});

it("uses an editorial Speaker overlay without replacing automatic attribution", () => {
  renderTranscript({
    audioID: "audio-1",
    speakers: [
      { id: "speaker-1", editorial_id: "editorial-1", automatic_speaker_id: "speaker-1", provider_label: "S1", ordinal: 0, name: "Journalist" },
      { id: "editorial-2", editorial_id: "editorial-2", automatic_speaker_id: null, provider_label: "Speaker", ordinal: 1, name: "Editor" }
    ],
    segments: [{ ...segment, correction: "Corrected segment", speakerCorrectionID: "editorial-2" }],
    onSelect: vi.fn()
  });

  expect(screen.getByRole("button", { name: "Editor, 0:10" })).toHaveTextContent("Corrected segment");
  fireEvent.click(screen.getByText("View automatic Speaker"));
  expect(screen.getByLabelText("Automatic Speaker")).toHaveTextContent("Journalist");
});
