import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "../lib/supabase";

export function AuthCallbackPage() {
  const navigate = useNavigate(); const [failed, setFailed] = useState(false);
  useEffect(() => { const code = new URLSearchParams(window.location.search).get("code"); if (!code) { setFailed(true); return; }
    void supabase.auth.exchangeCodeForSession(code).then(({ error }) => error ? setFailed(true) : navigate("/audios", { replace: true }));
  }, [navigate]);
  return failed ? <main><p role="alert">That sign-in link is invalid or expired.</p></main> : <p role="status">Signing you in…</p>;
}
