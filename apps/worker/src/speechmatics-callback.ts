import type { TranscriptionIngestionStore } from "./transcription-ingester";

const providerJobID = /^[A-Za-z0-9_-]{1,128}$/;

export interface TranscriptionIngestionQueue {
  send(message: { kind: "ingest"; transcription_job_id: string }): Promise<unknown>;
}

export class SpeechmaticsCallback {
  constructor(private readonly dependencies: { bearerToken: string; jobs: TranscriptionIngestionStore; queue: TranscriptionIngestionQueue }) {}

  async handle(request: Request): Promise<Response> {
    if (request.method !== "POST") return Response.json({ error: "not_found" }, { status: 404 });
    if (!timingSafeEqual(bearerToken(request), this.dependencies.bearerToken)) return Response.json({ error: "unauthorized" }, { status: 401 });
    const url = new URL(request.url);
    const id = url.searchParams.get("id");
    if (!id || !providerJobID.test(id) || url.searchParams.get("status") !== "success" || await request.arrayBuffer().then((body) => body.byteLength !== 0)) {
      return Response.json({ error: "invalid_request" }, { status: 400 });
    }
    const job = await this.dependencies.jobs.processingJob(id);
    if (!job) return Response.json({ error: "not_found" }, { status: 404 });
    await this.dependencies.queue.send({ kind: "ingest", transcription_job_id: job.id });
    return new Response(null, { status: 204 });
  }
}

function bearerToken(request: Request): string {
  return request.headers.get("Authorization")?.match(/^Bearer (.+)$/i)?.[1] ?? "";
}

function timingSafeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index += 1) difference |= (a[index % a.length] ?? 0) ^ (b[index % b.length] ?? 0);
  return difference === 0;
}
