import { useEffect, useState } from "react";
import { Navigate, Outlet } from "react-router-dom";
import { supabase } from "../lib/supabase";

export function RequireSession() {
  const [ready, setReady] = useState(false);
  const [signedIn, setSignedIn] = useState(false);
  useEffect(() => {
    let active = true;
    void supabase.auth.getSession().then(({ data }) => { if (active) { setSignedIn(Boolean(data.session)); setReady(true); } });
    const { data } = supabase.auth.onAuthStateChange((_event, session) => { if (active) { setSignedIn(Boolean(session)); setReady(true); } });
    return () => { active = false; data.subscription.unsubscribe(); };
  }, []);
  if (!ready) return <p role="status">Loading workspace…</p>;
  return signedIn ? <Outlet /> : <Navigate to="/login" replace />;
}
