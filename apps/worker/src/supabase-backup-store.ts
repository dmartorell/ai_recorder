import type { BackupStore, BeginBackupRequest, CloudBackup, MultipartUploadClaim, StoredBackup, StoredPart } from "./cloud-backup";

const audioBackupsPath = "rest/v1/audio_backups";
const audioBackupPartsPath = "rest/v1/audio_backup_parts";
const beginBackupPath = "rest/v1/rpc/begin_audio_backup";
const selectedColumns = "id,owner_id,local_audio_id,object_key,byte_count,sha256,state,r2_upload_id,r2_upload_claim,r2_upload_claimed_at";
const multipartClaimExpiryMilliseconds = 8 * 24 * 60 * 60 * 1_000;
export type BackupStoreFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
export class BackupMetadataConflictError extends Error {}

export class SupabaseBackupStore implements BackupStore {
  private readonly endpoint: URL;
  private readonly partsEndpoint: URL;
  private readonly beginEndpoint: URL;
  private readonly fetch: BackupStoreFetch;
  private readonly headers: HeadersInit;

  constructor({ supabaseURL, serviceRoleKey, fetch = (input, init) => globalThis.fetch(input, init) }: {
    supabaseURL: string; serviceRoleKey: string; fetch?: BackupStoreFetch;
  }) {
    this.endpoint = new URL(audioBackupsPath, withTrailingSlash(supabaseURL));
    this.partsEndpoint = new URL(audioBackupPartsPath, withTrailingSlash(supabaseURL));
    this.beginEndpoint = new URL(beginBackupPath, withTrailingSlash(supabaseURL));
    this.fetch = (input, init) => fetch(input, init);
    this.headers = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` };
  }

  async begin(request: BeginBackupRequest): Promise<CloudBackup> {
    const response = await this.fetch(this.beginEndpoint, {
      method: "POST",
      headers: { ...this.headers, "Content-Type": "application/json" },
      body: JSON.stringify({
        p_owner_id: request.ownerID,
        p_local_audio_id: request.localAudioID,
        p_byte_count: request.byteCount,
        p_sha256: request.sha256,
        p_transcription_language: request.transcriptionLanguage
      })
    });
    if (!response.ok) {
      if (response.status === 400 || response.status === 409) throw new BackupMetadataConflictError();
      throw new Error("Could not persist the audio backup");
    }
    const rows: unknown = await response.json();
    if (!Array.isArray(rows) || rows.length !== 1 || !isStoredBackup(rows[0])) {
      throw new Error("Audio backup persistence returned an invalid record");
    }
    return this.reuse(rows[0], request);
  }

  async get(ownerID: string, id: string): Promise<StoredBackup | undefined> {
    return this.find(new URLSearchParams({ id: `eq.${id}`, owner_id: `eq.${ownerID}` }));
  }

  async claimMultipartUpload(backup: StoredBackup): Promise<MultipartUploadClaim> {
    if (backup.r2_upload_id) return { kind: "existing", uploadID: backup.r2_upload_id };
    const claimID = crypto.randomUUID();
    const url = new URL(this.endpoint);
    url.search = new URLSearchParams({
      id: `eq.${backup.id}`,
      owner_id: `eq.${backup.owner_id}`,
      state: "eq.uploading",
      r2_upload_id: "is.null",
      or: `(r2_upload_claim.is.null,r2_upload_claimed_at.lt.${new Date(Date.now() - multipartClaimExpiryMilliseconds).toISOString()})`,
      select: selectedColumns
    }).toString();
    const response = await this.fetch(url, {
      method: "PATCH",
      headers: { ...this.headers, "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify({ r2_upload_claim: claimID, r2_upload_claimed_at: new Date().toISOString() })
    });
    if (!response.ok) throw new Error("Could not claim multipart upload creation");
    const rows: unknown = await response.json();
    if (Array.isArray(rows) && rows.length === 1 && isStoredBackup(rows[0])) return { kind: "claimed", claimID };

    const current = await this.get(backup.owner_id, backup.id);
    if (!current || current.state !== "uploading") throw new BackupMetadataConflictError();
    if (current.r2_upload_id) return { kind: "existing", uploadID: current.r2_upload_id };
    return { kind: "inProgress" };
  }

  async assignUploadID(backup: StoredBackup, claimID: string, uploadID: string): Promise<boolean> {
    const url = new URL(this.endpoint);
    url.search = new URLSearchParams({
      id: `eq.${backup.id}`,
      owner_id: `eq.${backup.owner_id}`,
      r2_upload_claim: `eq.${claimID}`,
      r2_upload_id: "is.null"
    }).toString();
    const response = await this.fetch(url, {
      method: "PATCH",
      headers: { ...this.headers, "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify({ r2_upload_id: uploadID, r2_upload_claim: null, r2_upload_claimed_at: null })
    });
    if (!response.ok) throw new Error("Could not persist multipart upload ID");
    const rows: unknown = await response.json();
    return Array.isArray(rows) && rows.length === 1;
  }

  async releaseMultipartUploadClaim(backup: StoredBackup, claimID: string): Promise<void> {
    const url = new URL(this.endpoint);
    url.search = new URLSearchParams({
      id: `eq.${backup.id}`,
      owner_id: `eq.${backup.owner_id}`,
      r2_upload_claim: `eq.${claimID}`,
      r2_upload_id: "is.null"
    }).toString();
    const response = await this.fetch(url, {
      method: "PATCH",
      headers: { ...this.headers, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({ r2_upload_claim: null, r2_upload_claimed_at: null })
    });
    if (!response.ok) throw new Error("Could not release multipart upload creation claim");
  }

  async confirmedParts(backupID: string): Promise<StoredPart[]> {
    const url = new URL(this.partsEndpoint);
    url.search = new URLSearchParams({ backup_id: `eq.${backupID}`, select: "part_number,etag,byte_count", order: "part_number.asc" }).toString();
    const response = await this.fetch(url, { headers: this.headers });
    if (!response.ok) throw new Error("Could not read audio backup parts");
    const rows: unknown = await response.json();
    if (!Array.isArray(rows) || !rows.every(isStoredPart)) throw new Error("Audio backup parts were invalid");
    return rows;
  }

  async confirmPart(backupID: string, part: StoredPart): Promise<void> {
    const response = await this.fetch(this.partsEndpoint, { method: "POST", headers: { ...this.headers, "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify({ backup_id: backupID, part_number: part.part_number, etag: part.etag, byte_count: part.byte_count }) });
    if (!response.ok) throw new Error("Could not persist audio backup part");
  }

  async cancel(backup: StoredBackup): Promise<void> { await this.patch(backup, { state: "cancelled", r2_upload_id: null, r2_upload_claim: null }); }
  async markBackedUp(backup: StoredBackup): Promise<void> { await this.patch(backup, { state: "backed_up", completed_at: new Date().toISOString() }); }

  private async find(filters: URLSearchParams): Promise<StoredBackup | undefined> {
    const url = new URL(this.endpoint);
    filters.set("select", selectedColumns);
    url.search = filters.toString();
    const response = await this.fetch(url, { headers: this.headers });
    if (!response.ok) throw new Error("Could not read the audio backup");
    const rows: unknown = await response.json();
    if (!Array.isArray(rows) || rows.length > 1 || (rows.length === 1 && !isStoredBackup(rows[0]))) throw new Error("Audio backup persistence returned an invalid record");
    return rows[0];
  }

  private async patch(backup: StoredBackup, values: Record<string, unknown>): Promise<void> {
    const url = new URL(this.endpoint);
    url.search = new URLSearchParams({ id: `eq.${backup.id}`, owner_id: `eq.${backup.owner_id}` }).toString();
    const response = await this.fetch(url, { method: "PATCH", headers: { ...this.headers, "Content-Type": "application/json", Prefer: "return=minimal" }, body: JSON.stringify(values) });
    if (!response.ok) throw new Error("Could not update the audio backup");
  }

  private reuse(stored: StoredBackup, request: BeginBackupRequest): CloudBackup {
    if (stored.byte_count !== request.byteCount || stored.sha256 !== request.sha256 || stored.state !== "uploading") throw new BackupMetadataConflictError();
    return { id: stored.id, state: "uploading" };
  }
}
function withTrailingSlash(url: string): string { return url.endsWith("/") ? url : `${url}/`; }
function isStoredBackup(value: unknown): value is StoredBackup { return isRecord(value) && typeof value.id === "string" && typeof value.owner_id === "string" && typeof value.local_audio_id === "string" && typeof value.object_key === "string" && typeof value.byte_count === "number" && typeof value.sha256 === "string" && typeof value.state === "string" && (typeof value.r2_upload_id === "string" || value.r2_upload_id === null) && (typeof value.r2_upload_claim === "string" || value.r2_upload_claim === null) && (typeof value.r2_upload_claimed_at === "string" || value.r2_upload_claimed_at === null); }
function isStoredPart(value: unknown): value is StoredPart { return isRecord(value) && Number.isInteger(value.part_number) && typeof value.etag === "string" && typeof value.byte_count === "number"; }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
