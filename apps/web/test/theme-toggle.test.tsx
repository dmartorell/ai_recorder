import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it } from "vitest";
import { ThemeProvider } from "../src/features/theme/theme-provider";
import { ThemeToggle } from "../src/features/theme/theme-toggle";

afterEach(() => {
  localStorage.clear();
  document.documentElement.removeAttribute("data-theme");
});

describe("ThemeToggle", () => {
  it("uses the dark theme by default and switches to light", async () => {
    const user = userEvent.setup();
    render(<ThemeProvider><ThemeToggle /></ThemeProvider>);

    expect(document.documentElement).toHaveAttribute("data-theme", "dark");
    await user.click(screen.getByRole("button", { name: "Use light theme" }));

    expect(document.documentElement).toHaveAttribute("data-theme", "light");
    expect(localStorage.getItem("theme")).toBe("light");
  });

  it("restores the saved theme", () => {
    localStorage.setItem("theme", "light");
    render(<ThemeProvider><ThemeToggle /></ThemeProvider>);

    expect(document.documentElement).toHaveAttribute("data-theme", "light");
  });
});
