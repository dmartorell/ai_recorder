import { FormEvent, useState } from "react";
import { supabase } from "../lib/supabase";

export function LoginPage() {
  const [email, setEmail] = useState(""); const [message, setMessage] = useState<string>();
  async function submit(event: FormEvent) {
    event.preventDefault(); setMessage(undefined);
    const { error } = await supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: `${window.location.origin}/auth/callback` } });
    setMessage(error ? "Unable to send the sign-in link. Try again." : "Check your email for a sign-in link.");
  }
  return <main className="auth"><h1>Audio review</h1><p>Sign in to review your Audio.</p><form onSubmit={submit}><label>Email<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="email" /></label><button type="submit">Send sign-in link</button></form>{message ? <p role="status">{message}</p> : null}</main>;
}
