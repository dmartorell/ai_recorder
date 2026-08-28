import { Navigate, Route, Routes } from "react-router-dom";
import { AudioDetailPage } from "./features/audio/audio-detail-page";
import { AudioLibraryPage } from "./features/audio/audio-library-page";
import { AuthCallbackPage } from "./routes/auth-callback-page";
import { LoginPage } from "./routes/login-page";
import { RequireSession } from "./routes/require-session";
import { ThemeProvider } from "./features/theme/theme-provider";
import { ThemeToggle } from "./features/theme/theme-toggle";

export function App() {
  return <ThemeProvider>
    <ThemeToggle />
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/auth/callback" element={<AuthCallbackPage />} />
      <Route element={<RequireSession />}>
        <Route path="/audios" element={<AudioLibraryPage />} />
        <Route path="/audios/:audioID" element={<AudioDetailPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/audios" replace />} />
    </Routes>
  </ThemeProvider>;
}
