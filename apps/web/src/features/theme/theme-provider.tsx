import { createContext, type ReactNode, useContext, useEffect, useState } from "react";

type Theme = "dark" | "light";

type ThemeContextValue = {
  theme: Theme;
  toggleTheme: () => void;
};

const ThemeContext = createContext<ThemeContextValue | undefined>(undefined);

function savedTheme(): Theme {
  return localStorage.getItem("theme") === "light" ? "light" : "dark";
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<Theme>(savedTheme);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem("theme", theme);
  }, [theme]);

  return <ThemeContext value={{ theme, toggleTheme: () => setTheme((current) => current === "dark" ? "light" : "dark") }}>{children}</ThemeContext>;
}

export function useTheme() {
  const theme = useContext(ThemeContext);
  if (!theme) throw new Error("useTheme must be used within ThemeProvider");
  return theme;
}
