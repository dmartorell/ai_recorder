import { useTheme } from "./theme-provider";

export function ThemeToggle() {
  const { theme, toggleTheme } = useTheme();
  const nextTheme = theme === "dark" ? "light" : "dark";

  return <button className="theme-toggle" type="button" onClick={toggleTheme} aria-label={`Use ${nextTheme} theme`}>
    {nextTheme === "light" ? "Light theme" : "Dark theme"}
  </button>;
}
