import { render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { beforeEach, expect, it, vi } from "vitest";

const auth = vi.hoisted(() => ({
  getSession: vi.fn(),
  onAuthStateChange: vi.fn()
}));

vi.mock("../src/lib/supabase", () => ({ supabase: { auth } }));

import { RequireSession } from "../src/routes/require-session";

beforeEach(() => {
  vi.clearAllMocks();
  auth.onAuthStateChange.mockReturnValue({ data: { subscription: { unsubscribe: vi.fn() } } });
});

function renderProtectedRoute() {
  return render(
    <MemoryRouter initialEntries={["/audios"]}>
      <Routes>
        <Route element={<RequireSession />}>
          <Route path="/audios" element={<p>Private workspace</p>} />
        </Route>
        <Route path="/login" element={<p>Sign in</p>} />
      </Routes>
    </MemoryRouter>
  );
}

it("redirects an unauthenticated visitor before rendering the workspace", async () => {
  auth.getSession.mockResolvedValue({ data: { session: null } });

  renderProtectedRoute();

  expect(screen.getByRole("status")).toHaveTextContent("Loading workspace");
  expect(await screen.findByText("Sign in")).toBeInTheDocument();
  expect(screen.queryByText("Private workspace")).not.toBeInTheDocument();
});

it("renders the workspace for an authenticated visitor", async () => {
  auth.getSession.mockResolvedValue({ data: { session: { access_token: "synthetic" } } });

  renderProtectedRoute();

  await waitFor(() => expect(screen.getByText("Private workspace")).toBeInTheDocument());
});
