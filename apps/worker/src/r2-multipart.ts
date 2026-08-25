import { AwsClient } from "aws4fetch";
import { sha256Stream } from "./sha256-stream";

export const multipartPartSize = 8 * 1024 * 1024;

export type ConfirmedPart = { partNumber: number; etag: string; byteCount: number };

export interface MultipartGateway {
  create(key: string, sha256: string): Promise<{ uploadID: string }>;
  signedPartURL(key: string, uploadID: string, partNumber: number, sha256: string): Promise<string>;
  signedReadURL(key: string): Promise<string>;
  listParts(key: string, uploadID: string): Promise<ConfirmedPart[]>;
  complete(key: string, uploadID: string, parts: ConfirmedPart[]): Promise<{ size: number; sha256?: string }>;
  abort(key: string, uploadID: string): Promise<void>;
}

export class R2MultipartGateway implements MultipartGateway {
  private readonly aws: AwsClient;
  private readonly endpoint: string;

  constructor({ bucket, accountID, accessKeyID, secretAccessKey, r2 }: {
    bucket: string;
    accountID: string;
    accessKeyID: string;
    secretAccessKey: string;
    r2: R2Bucket;
  }) {
    this.aws = new AwsClient({ accessKeyId: accessKeyID, secretAccessKey, service: "s3", region: "auto" });
    this.endpoint = `https://${accountID}.r2.cloudflarestorage.com/${bucket}`;
    this.r2 = r2;
  }

  private readonly r2: R2Bucket;

  async create(key: string, sha256: string): Promise<{ uploadID: string }> {
    const upload = await this.r2.createMultipartUpload(key, { customMetadata: { sha256 } });
    return { uploadID: upload.uploadId };
  }

  async signedPartURL(key: string, uploadID: string, partNumber: number, _sha256: string): Promise<string> {
    const url = this.objectURL(key);
    url.searchParams.set("partNumber", String(partNumber));
    url.searchParams.set("uploadId", uploadID);
    url.searchParams.set("X-Amz-Expires", "900");
    const signed = await this.aws.sign(url, { method: "PUT", aws: { signQuery: true } });
    return signed.url;
  }

  async signedReadURL(key: string): Promise<string> {
    const url = this.objectURL(key);
    url.searchParams.set("X-Amz-Expires", "900");
    const signed = await this.aws.sign(url, { method: "GET", aws: { signQuery: true } });
    return signed.url;
  }

  async listParts(key: string, uploadID: string): Promise<ConfirmedPart[]> {
    const url = this.objectURL(key);
    url.searchParams.set("uploadId", uploadID);
    const response = await this.aws.fetch(url, { method: "GET" });
    if (!response.ok) throw new Error("Could not verify multipart upload parts");
    return parseListParts(await response.text());
  }

  async complete(key: string, uploadID: string, parts: ConfirmedPart[]): Promise<{ size: number; sha256?: string }> {
    const upload = this.r2.resumeMultipartUpload(key, uploadID);
    const object = await upload.complete(parts.map(({ partNumber, etag }) => ({ partNumber, etag })));
    const verified = await this.r2.get(object.key);
    if (!verified) throw new Error("Completed object was not found");
    return { size: verified.size, sha256: await sha256Stream(verified.body) }
  }

  async abort(key: string, uploadID: string): Promise<void> {
    await this.r2.resumeMultipartUpload(key, uploadID).abort();
  }

  private objectURL(key: string): URL {
    return new URL(`${this.endpoint}/${key.split("/").map(encodeURIComponent).join("/")}`);
  }
}

export function parseListParts(xml: string): ConfirmedPart[] {
  return [...xml.matchAll(/<Part>([\s\S]*?)<\/Part>/g)].flatMap(([, contents]) => {
    const partNumber = contents.match(/<PartNumber>(\d+)<\/PartNumber>/)?.[1];
    const etag = contents.match(/<ETag>\s*\"?([^<\"]+)\"?\s*<\/ETag>/)?.[1];
    const byteCount = contents.match(/<Size>(\d+)<\/Size>/)?.[1];
    const normalizedETag = etag?.replaceAll("&quot;", "").replaceAll('"', "");
    return partNumber && normalizedETag && byteCount
      ? [{ partNumber: Number(partNumber), etag: normalizedETag, byteCount: Number(byteCount) }]
      : [];
  });
}

