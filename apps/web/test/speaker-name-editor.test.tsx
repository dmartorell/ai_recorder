import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const from = vi.hoisted(() => vi.fn());
vi.mock("../src/lib/supabase", () => ({ supabase: { from } }));

import { SpeakerNameEditor } from "../src/features/audio/speaker-name-editor";

const speaker = { id: "automatic-speaker-1", editorial_id: "speaker-1", provider_label: "S1", ordinal: 0, name: null };

function renderEditor() {
  return render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })}>
    <SpeakerNameEditor audioID="audio-1" speaker={speaker} />
  </QueryClientProvider>);
}

beforeEach(() => vi.clearAllMocks());
afterEach(cleanup);

it("uses the provider label until a saved editorial name replaces it", async () => {
  let resolve: (value: { error: null }) => void;
  const eq = vi.fn().mockReturnValue(new Promise<{ error: null }>((complete) => { resolve = complete; }));
  from.mockReturnValue({ update: vi.fn().mockReturnValue({ eq }) });
  renderEditor();

  const input = screen.getByLabelText("Speaker name");
  expect(input).toHaveValue("S1");
  fireEvent.change(input, { target: { value: "Journalist" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));

  await waitFor(() => expect(screen.getByRole("button", { name: "Saving" })).toBeDisabled());
  resolve!({ error: null });
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Saved"));
  expect(from).toHaveBeenCalledWith("speakers");
  expect(eq).toHaveBeenCalledWith("id", "speaker-1");
});

it("keeps the local name and retries after a save failure", async () => {
  const eq = vi.fn().mockResolvedValueOnce({ error: { message: "offline" } }).mockResolvedValueOnce({ error: null });
  from.mockReturnValue({ update: vi.fn().mockReturnValue({ eq }) });
  renderEditor();

  const input = screen.getByLabelText("Speaker name");
  fireEvent.change(input, { target: { value: "Source" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));

  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Could not save."));
  expect(input).toHaveValue("Source");
  fireEvent.click(screen.getByRole("button", { name: "Retry" }));
  await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Saved"));
  expect(input).toHaveValue("Source");
});
