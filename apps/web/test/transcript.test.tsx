import { fireEvent, render, screen } from "@testing-library/react";
import { expect, it, vi } from "vitest";
import { Transcript } from "../src/features/audio/transcript";
const segment = { id: "segment-1", automatic_speaker_id: "speaker-1", ordinal: 0, content: "Synthetic segment", start_time_ms: 10_000, end_time_ms: 12_000 };
it("seeks when a Transcript Segment is selected and identifies the active segment", () => { const select = vi.fn(); render(<Transcript audioID="audio-1" speakers={[{ id: "speaker-1", provider_label: "S1", ordinal: 0, name: null }]} segments={[segment]} activeID="segment-1" onSelect={select} />); const button = screen.getByRole("button", { name: "S1, 0:10" }); expect(button.closest("li")).toHaveClass("active"); fireEvent.click(button); expect(select).toHaveBeenCalledWith(segment); });
it("uses the editorial name when one exists", () => { render(<Transcript audioID="audio-1" speakers={[{ id: "speaker-1", provider_label: "S1", ordinal: 0, name: "Journalist" }]} segments={[segment]} onSelect={vi.fn()} />); expect(screen.getByRole("button", { name: "Journalist, 0:10" })).toBeInTheDocument(); });
