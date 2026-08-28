import { render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, expect, it, vi } from "vitest";

const useAudioDetail = vi.hoisted(() => vi.fn());
vi.mock("../src/features/audio/audio-queries", () => ({ useAudioDetail }));
vi.mock("../src/features/audio/private-audio-player", () => ({
  PrivateAudioPlayer: () => <p>Private player</p>
}));
vi.mock("../src/features/audio/transcript", () => ({
  Transcript: () => <p>Automatic Transcript</p>
}));

import { AudioDetailPage } from "../src/features/audio/audio-detail-page";

beforeEach(() => vi.clearAllMocks());

function renderDetail() {
  return render(
    <MemoryRouter initialEntries={["/audios/audio-1"]}>
      <Routes><Route path="/audios/:audioID" element={<AudioDetailPage />} /></Routes>
    </MemoryRouter>
  );
}

it("renders loading and unavailable detail states without exposing Audio metadata", () => {
  useAudioDetail.mockReturnValue({ isPending: true });
  const { rerender } = renderDetail();
  expect(screen.getByRole("status")).toHaveTextContent("Loading Audio");

  useAudioDetail.mockReturnValue({ isPending: false, isError: false, data: undefined });
  rerender(<MemoryRouter initialEntries={["/audios/audio-1"]}><Routes><Route path="/audios/:audioID" element={<AudioDetailPage />} /></Routes></MemoryRouter>);
  expect(screen.getByRole("alert")).toHaveTextContent("This Audio is unavailable.");
});

it("renders an owned backed-up Audio with private playback and its Automatic Transcript", () => {
  useAudioDetail.mockReturnValue({
    isPending: false,
    isError: false,
    data: {
      audio: {
        id: "audio-1",
        title_snapshot: "Synthetic Audio",
        capture_started_at: "2026-08-28T10:00:00Z",
        duration_milliseconds: 61_000,
        transcription_language: "english",
        audio_backups: { id: "backup-1", state: "backed_up" }
      },
      transcriptionState: "complete",
      speakers: [],
      segments: []
    }
  });

  renderDetail();

  expect(screen.getByRole("heading", { name: "Synthetic Audio" })).toBeInTheDocument();
  expect(screen.getByText("Cloud audio: Backed up")).toBeInTheDocument();
  expect(screen.getByText("Private player")).toBeInTheDocument();
  expect(screen.getByText("Automatic Transcript")).toBeInTheDocument();
});
