import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { expect, it, vi } from "vitest";
const useAudios = vi.hoisted(() => vi.fn());
vi.mock("../src/features/audio/audio-queries", () => ({ useAudios }));
import { AudioLibraryPage } from "../src/features/audio/audio-library-page";
it("renders owner-visible Audio metadata", () => { useAudios.mockReturnValue({ isPending: false, isError: false, data: [{ id: "audio-1", title_snapshot: "Synthetic Audio", capture_started_at: "2026-08-28T10:00:00Z", duration_milliseconds: 61_000, transcription_language: "english", audio_backups: [{ state: "backed_up" }] }] }); render(<MemoryRouter><AudioLibraryPage /></MemoryRouter>); expect(screen.getByRole("link", { name: /Synthetic Audio/ })).toHaveAttribute("href", "/audios/audio-1"); expect(screen.getByText("Backed up")).toBeInTheDocument(); });
it("renders empty and loading states", () => { useAudios.mockReturnValue({ isPending: true }); const { rerender } = render(<MemoryRouter><AudioLibraryPage /></MemoryRouter>); expect(screen.getByRole("status")).toHaveTextContent("Loading"); useAudios.mockReturnValue({ isPending: false, isError: false, data: [] }); rerender(<MemoryRouter><AudioLibraryPage /></MemoryRouter>); expect(screen.getByText("No Audio is available yet.")).toBeInTheDocument(); });
