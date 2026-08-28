import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const from = vi.hoisted(() => vi.fn());
vi.mock("../src/lib/supabase", () => ({ supabase: { from } }));

import { AddSpeakerForm } from "../src/features/audio/add-speaker-form";

function renderForm() {
  return render(<QueryClientProvider client={new QueryClient({ defaultOptions: { mutations: { retry: false } } })}>
    <AddSpeakerForm audioID="audio-1" />
  </QueryClientProvider>);
}

beforeEach(() => vi.clearAllMocks());
afterEach(cleanup);

it("adds a non-empty named Speaker to the current Audio", async () => {
  const single = vi.fn().mockResolvedValue({
    data: { id: "editorial-3", automatic_speaker_id: null, name: "Editor" },
    error: null
  });
  const select = vi.fn().mockReturnValue({ single });
  const insert = vi.fn().mockReturnValue({ select });
  from.mockReturnValue({ insert });
  renderForm();

  fireEvent.click(screen.getByRole("button", { name: "Add Speaker" }));
  expect(screen.getByRole("alert")).toHaveTextContent("Enter a Speaker name.");
  fireEvent.change(screen.getByLabelText("New Speaker name"), { target: { value: " Editor " } });
  fireEvent.click(screen.getByRole("button", { name: "Add Speaker" }));

  await waitFor(() => expect(insert).toHaveBeenCalledWith({ audio_id: "audio-1", name: "Editor" }));
  expect(select).toHaveBeenCalledWith("id,automatic_speaker_id,name");
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Saved"));
  expect(screen.getByLabelText("New Speaker name")).toHaveValue("");
});

it("retains a failed Speaker name and retries with generic error copy", async () => {
  const single = vi.fn()
    .mockResolvedValueOnce({ data: null, error: { message: "offline" } })
    .mockResolvedValueOnce({ data: { id: "editorial-3", automatic_speaker_id: null, name: "Editor" }, error: null });
  const select = vi.fn().mockReturnValue({ single });
  const insert = vi.fn().mockReturnValue({ select });
  from.mockReturnValue({ insert });
  renderForm();

  fireEvent.change(screen.getByLabelText("New Speaker name"), { target: { value: "Editor" } });
  fireEvent.click(screen.getByRole("button", { name: "Add Speaker" }));
  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Could not save."));
  expect(screen.getByLabelText("New Speaker name")).toHaveValue("Editor");
  fireEvent.click(screen.getByRole("button", { name: "Retry" }));
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Saved"));
});
