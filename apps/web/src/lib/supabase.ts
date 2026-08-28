import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

export const supabase = createClient(url ?? "https://unconfigured.supabase.co", key ?? "unconfigured-key");
export const workerURL = import.meta.env.VITE_WORKER_URL ?? "";
