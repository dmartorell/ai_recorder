import { render, screen, waitFor } from "@testing-library/react";
import { BrowserRouter } from "react-router-dom";
import { beforeEach, expect, it, vi } from "vitest";
const auth = vi.hoisted(() => ({ exchangeCodeForSession: vi.fn(), getSession: vi.fn() }));
vi.mock("../src/lib/supabase", () => ({ supabase: { auth } }));
import { AuthCallbackPage } from "../src/routes/auth-callback-page";

beforeEach(() => { vi.clearAllMocks(); window.history.replaceState({}, "", "/auth/callback#access_token=synthetic"); });
it("accepts the session supplied by an implicit magic-link callback", async () => {
  auth.getSession.mockResolvedValue({ data: { session: { access_token: "synthetic" } }, error: null });
  render(<BrowserRouter><AuthCallbackPage /></BrowserRouter>);
  await waitFor(() => expect(auth.getSession).toHaveBeenCalledOnce());
  expect(auth.exchangeCodeForSession).not.toHaveBeenCalled();
  await waitFor(() => expect(window.location.pathname).toBe("/audios"));
});
