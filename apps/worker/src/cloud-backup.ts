import { createRemoteJWKSet, jwtVerify } from "jose";
import { multipartPartSize, type MultipartGateway } from "./r2-multipart";
import { BackupMetadataConflictError, SupabaseBackupStore } from "./supabase-backup-store";
import { SupabaseTranscriptionJobStore, TranscriptionJobNotRetryableError, type TranscriptionJobStore } from "./supabase-transcription-job-store";
import { SpeechmaticsCallback } from "./speechmatics-callback";

const backupPath = "/v1/audio-backups";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const sha256Pattern = /^[0-9a-f]{64}$/i;
export interface WorkerAuthenticator { authenticate(request: Request): Promise<{ userID: string }>; }
export interface BeginBackupRequest { ownerID: string; localAudioID: string; byteCount: number; sha256: string; transcriptionLanguage: "spanish" | "english" | "spanish_english"; }
export interface CloudBackup { id: string; state: "uploading"; }
export interface StoredBackup { id: string; owner_id: string; local_audio_id: string; object_key: string; byte_count: number; sha256: string; state: string; r2_upload_id: string | null; r2_upload_claim: string | null; r2_upload_claimed_at: string | null; }
export interface StoredPart { part_number: number; etag: string; byte_count: number; }
export type MultipartUploadClaim = { kind: "existing"; uploadID: string } | { kind: "claimed"; claimID: string } | { kind: "inProgress" };
export interface BackupStore { begin(request: BeginBackupRequest): Promise<CloudBackup>; get(ownerID: string, id: string): Promise<StoredBackup | undefined>; claimMultipartUpload(backup: StoredBackup): Promise<MultipartUploadClaim>; assignUploadID(backup: StoredBackup, claimID: string, uploadID: string): Promise<boolean>; releaseMultipartUploadClaim(backup: StoredBackup, claimID: string): Promise<void>; confirmedParts(backupID: string): Promise<StoredPart[]>; confirmPart(backupID: string, part: StoredPart): Promise<void>; cancel(backup: StoredBackup): Promise<void>; markBackedUp(backup: StoredBackup): Promise<void>; }
export interface TranscriptionJobQueue { send(message: { kind: "submit" | "ingest"; transcription_job_id: string }): Promise<unknown>; }
interface WorkerDependencies { authentication: WorkerAuthenticator; backups: BackupStore; transcriptionJobs?: TranscriptionJobStore; transcriptionQueue?: TranscriptionJobQueue; multipart?: MultipartGateway; }

export function createWorker({ authentication, backups, transcriptionJobs = new UnconfiguredTranscriptionJobStore(), transcriptionQueue, multipart }: WorkerDependencies): ExportedHandler<Env> {
  return { async fetch(request): Promise<Response> {
    const url = new URL(request.url);
    if (!url.pathname.startsWith(backupPath)) return Response.json({ error: "not_found" }, { status: 404 });
    let identity: { userID: string };
    try { identity = await authentication.authenticate(request); } catch { return Response.json({ error: "unauthorized" }, { status: 401 }); }
    const suffix = url.pathname.slice(backupPath.length);
    try {
      if (suffix === "" && request.method === "POST") return await begin(request, identity.userID, backups);
      const retryMatch = suffix.match(/^\/([0-9a-f-]{36})\/transcription\/retry$/i);
      if (retryMatch && uuidPattern.test(retryMatch[1]) && request.method === "POST") {
        const backup = await backups.get(identity.userID, retryMatch[1]);
        if (!backup) return Response.json({ error: "not_found" }, { status: 404 });
        return await retryTranscription(backup, identity.userID, transcriptionJobs, transcriptionQueue);
      }
      const match = suffix.match(/^\/([0-9a-f-]{36})(?:\/(multipart|complete|cancel|transcription)|\/parts\/(\d+)\/(url|confirm))?$/i);
      if (!match || !uuidPattern.test(match[1])) return Response.json({ error: "not_found" }, { status: 404 });
      const backup = await backups.get(identity.userID, match[1]);
      if (!backup) return Response.json({ error: "not_found" }, { status: 404 });
      if (match[2] === "transcription" && request.method === "GET") return await transcriptionStatus(backup, transcriptionJobs);
      if (!multipart) return Response.json({ error: "service_unavailable" }, { status: 503 });
      if (!match[2] && request.method === "GET") return await status(backup, backups);
      if (match[2] === "multipart" && request.method === "POST") return await initiate(backup, backups, multipart);
      if (match[2] === "cancel" && request.method === "POST") return await cancel(backup, backups, multipart);
      if (match[2] === "complete" && request.method === "POST") return await complete(backup, backups, multipart, transcriptionJobs, transcriptionQueue);
      if (match[3] && match[4] === "url" && request.method === "POST") return await signedURL(request, backup, Number(match[3]), multipart);
      if (match[3] && match[4] === "confirm" && request.method === "POST") return await confirm(request, backup, Number(match[3]), backups, multipart);
      return Response.json({ error: "not_found" }, { status: 404 });
    } catch (error) {
      if (error instanceof BackupMetadataConflictError) return Response.json({ error: "backup_metadata_conflict" }, { status: 409 });
      if (error instanceof InvalidRequestError) return Response.json({ error: "invalid_request" }, { status: 400 });
      if (error instanceof InvalidStateError || error instanceof TranscriptionJobNotRetryableError) return Response.json({ error: "invalid_state" }, { status: 409 });
      throw error;
    }
  }};
}
async function begin(request: Request, ownerID: string, backups: BackupStore): Promise<Response> { const body = await parseJSON(request); if (!isRecord(body) || typeof body.local_audio_id !== "string" || !uuidPattern.test(body.local_audio_id) || !validBytes(body.byte_count) || typeof body.sha256 !== "string" || !sha256Pattern.test(body.sha256) || (body.transcription_language !== undefined && !isTranscriptionLanguage(body.transcription_language))) throw new InvalidRequestError(); const created = await backups.begin({ ownerID, localAudioID: body.local_audio_id, byteCount: body.byte_count, sha256: body.sha256.toLowerCase(), transcriptionLanguage: body.transcription_language ?? "spanish_english" }); return Response.json(created, { status: 201 }); }
async function status(backup: StoredBackup, backups: BackupStore): Promise<Response> { return Response.json({ id: backup.id, state: backup.state, confirmed_parts: (await backups.confirmedParts(backup.id)).map(({ part_number, byte_count }) => ({ part_number, byte_count })), part_size: multipartPartSize }); }
async function initiate(backup: StoredBackup, backups: BackupStore, multipart: MultipartGateway): Promise<Response> {
  active(backup);
  const claim = await backups.claimMultipartUpload(backup);
  if (claim.kind === "inProgress") return Response.json({ error: "multipart_creation_in_progress" }, { status: 409 });
  if (claim.kind === "existing") return status({ ...backup, r2_upload_id: claim.uploadID }, backups);

  let upload: { uploadID: string } | undefined;
  let releaseClaim = { value: true };
  try {
    upload = await multipart.create(backup.object_key, backup.sha256);
    const persisted = await backups.assignUploadID(backup, claim.claimID, upload.uploadID);
    if (persisted) return status({ ...backup, r2_upload_id: upload.uploadID }, backups);
    await multipart.abort(backup.object_key, upload.uploadID);
    return Response.json({ error: "multipart_creation_in_progress" }, { status: 409 });
  } catch (error) {
    if (!upload) throw error;
    try {
      const current = await backups.get(backup.owner_id, backup.id);
      if (current?.r2_upload_id !== upload.uploadID) await multipart.abort(backup.object_key, upload.uploadID);
    } catch {
      releaseClaim.value = false;
    }
    throw error;
  } finally {
    if (releaseClaim.value) await backups.releaseMultipartUploadClaim(backup, claim.claimID).catch(() => undefined);
  }
}
async function signedURL(request: Request, backup: StoredBackup, partNumber: number, multipart: MultipartGateway): Promise<Response> { active(backup); const uploadID = uploadIDFor(backup); validatePart(backup, partNumber); const body = await parseJSON(request); if (!isRecord(body) || typeof body.sha256 !== "string" || !sha256Pattern.test(body.sha256)) throw new InvalidRequestError(); return Response.json({ url: await multipart.signedPartURL(backup.object_key, uploadID, partNumber, body.sha256.toLowerCase()), expires_in: 900 }); }
async function confirm(request: Request, backup: StoredBackup, partNumber: number, backups: BackupStore, multipart: MultipartGateway): Promise<Response> { active(backup); const uploadID = uploadIDFor(backup); validatePart(backup, partNumber); const body = await parseJSON(request); const etag = isRecord(body) ? body.etag : undefined; if (typeof etag !== "string" || !etag) throw new InvalidRequestError(); const part = (await multipart.listParts(backup.object_key, uploadID)).find((candidate) => candidate.partNumber === partNumber && candidate.etag === etag.replaceAll('"', "")); if (!part || part.byteCount !== expectedPartBytes(backup, partNumber)) throw new InvalidRequestError(); await backups.confirmPart(backup.id, { part_number: part.partNumber, etag: part.etag, byte_count: part.byteCount }); return new Response(null, { status: 204 }); }
async function complete(backup: StoredBackup, backups: BackupStore, multipart: MultipartGateway, transcriptionJobs?: TranscriptionJobStore, transcriptionQueue?: TranscriptionJobQueue): Promise<Response> { if (backup.state === "backed_up") return backedUp(backup, transcriptionJobs, transcriptionQueue); active(backup); const uploadID = uploadIDFor(backup); const parts = await backups.confirmedParts(backup.id); const count = Math.ceil(backup.byte_count / multipartPartSize); if (parts.length !== count || parts.some((part, index) => part.part_number !== index + 1 || part.byte_count !== expectedPartBytes(backup, part.part_number))) throw new InvalidRequestError(); const object = await multipart.complete(backup.object_key, uploadID, parts.map((part) => ({ partNumber: part.part_number, etag: part.etag, byteCount: part.byte_count }))); if (object.size !== backup.byte_count || object.sha256 !== backup.sha256) throw new Error("Completed object verification failed"); await backups.markBackedUp(backup); return backedUp(backup, transcriptionJobs, transcriptionQueue); }
async function backedUp(backup: StoredBackup, transcriptionJobs?: TranscriptionJobStore, transcriptionQueue?: TranscriptionJobQueue): Promise<Response> { if (transcriptionJobs && transcriptionQueue) { const job = await transcriptionJobs.enqueue(backup); await transcriptionQueue.send({ kind: "submit", transcription_job_id: job.id }); } return Response.json({ id: backup.id, state: "backed_up" }); }
async function retryTranscription(backup: StoredBackup, ownerID: string, transcriptionJobs: TranscriptionJobStore, transcriptionQueue?: TranscriptionJobQueue): Promise<Response> {
  if (!transcriptionQueue) return Response.json({ error: "service_unavailable" }, { status: 503 });
  const job = await transcriptionJobs.retryFailed(ownerID, backup.id);
  if (!job) return Response.json({ error: "not_found" }, { status: 404 });
  if (job.state !== "queued" && job.state !== "processing") throw new InvalidStateError();
  await transcriptionQueue.send({ kind: job.provider_job_id ? "ingest" : "submit", transcription_job_id: job.id });
  return new Response(null, { status: 204 });
}
async function transcriptionStatus(backup: StoredBackup, transcriptionJobs: TranscriptionJobStore): Promise<Response> {
  const job = await transcriptionJobs.get(backup.owner_id, backup.id);
  return Response.json({ state: job?.state ?? "not_started" });
}
async function cancel(backup: StoredBackup, backups: BackupStore, multipart: MultipartGateway): Promise<Response> { active(backup); if (backup.r2_upload_id) await multipart.abort(backup.object_key, backup.r2_upload_id); await backups.cancel(backup); return new Response(null, { status: 204 }); }
function active(backup: StoredBackup) { if (backup.state !== "uploading") throw new InvalidStateError(); }
function uploadIDFor(backup: StoredBackup): string { if (!backup.r2_upload_id) throw new InvalidStateError(); return backup.r2_upload_id; }
function validatePart(backup: StoredBackup, part: number) { if (!Number.isSafeInteger(part) || part < 1 || part > Math.ceil(backup.byte_count / multipartPartSize)) throw new InvalidRequestError(); }
function expectedPartBytes(backup: StoredBackup, part: number) { return Math.min(multipartPartSize, backup.byte_count - ((part - 1) * multipartPartSize)); }
function validBytes(value: unknown): value is number { return typeof value === "number" && Number.isSafeInteger(value) && value > 0; }
function isTranscriptionLanguage(value: unknown): value is "spanish" | "english" | "spanish_english" { return value === "spanish" || value === "english" || value === "spanish_english"; }
async function parseJSON(request: Request): Promise<unknown> { try { return await request.json(); } catch { throw new InvalidRequestError(); } }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
class InvalidRequestError extends Error {} class InvalidStateError extends Error {}
class SupabaseJWTAuthenticator implements WorkerAuthenticator { private readonly jwks: ReturnType<typeof createRemoteJWKSet>; private readonly issuer: string; constructor(supabaseURL: string) { const origin = new URL(supabaseURL).origin; this.issuer = `${origin}/auth/v1`; this.jwks = createRemoteJWKSet(new URL(`${this.issuer}/.well-known/jwks.json`)); } async authenticate(request: Request): Promise<{ userID: string }> { const token = request.headers.get("Authorization")?.match(/^Bearer (.+)$/i)?.[1]; if (!token) throw new Error("Missing bearer token"); const { payload } = await jwtVerify(token, this.jwks, { audience: "authenticated", issuer: this.issuer }); if (typeof payload.sub !== "string" || !payload.sub) throw new Error("Missing subject claim"); return { userID: payload.sub }; } }
const authenticators = new Map<string, SupabaseJWTAuthenticator>();
export function createDefaultWorker(supabaseURL: string, serviceRoleKey: string | undefined, multipart?: MultipartGateway, transcriptionQueue?: TranscriptionJobQueue, callback?: SpeechmaticsCallback): ExportedHandler<Env> {
  let authentication = authenticators.get(supabaseURL);
  if (!authentication) { authentication = new SupabaseJWTAuthenticator(supabaseURL); authenticators.set(supabaseURL, authentication); }
  const backupWorker = createWorker({ authentication, backups: serviceRoleKey ? new SupabaseBackupStore({ supabaseURL, serviceRoleKey }) : new UnconfiguredBackupStore(), transcriptionJobs: serviceRoleKey ? new SupabaseTranscriptionJobStore({ supabaseURL, serviceRoleKey }) : new UnconfiguredTranscriptionJobStore(), transcriptionQueue, multipart });
  return {
    async fetch(request, env, context) {
      if (new URL(request.url).pathname === "/v1/transcription-callback") return callback ? callback.handle(request) : Response.json({ error: "service_unavailable" }, { status: 503 });
      return backupWorker.fetch!(request, env, context);
    }
  };
}
class UnconfiguredBackupStore implements BackupStore { async begin(): Promise<CloudBackup> { throw new Error("service unavailable"); } async get(): Promise<undefined> { return undefined; } async claimMultipartUpload(): Promise<MultipartUploadClaim> { throw new Error("service unavailable"); } async assignUploadID(): Promise<boolean> { throw new Error("service unavailable"); } async releaseMultipartUploadClaim(): Promise<void> { throw new Error("service unavailable"); } async confirmedParts(): Promise<StoredPart[]> { return []; } async confirmPart(): Promise<void> { throw new Error("service unavailable"); } async cancel(): Promise<void> { throw new Error("service unavailable"); } async markBackedUp(): Promise<void> { throw new Error("service unavailable"); } }
class UnconfiguredTranscriptionJobStore implements TranscriptionJobStore { async enqueue(): Promise<never> { throw new Error("service unavailable"); } async get(): Promise<undefined> { return undefined; } async retryFailed(): Promise<undefined> { return undefined; } }
