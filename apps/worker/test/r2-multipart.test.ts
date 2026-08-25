import { describe, expect, it } from "vitest";
import { parseListParts, R2MultipartGateway } from "../src/r2-multipart";

describe("R2MultipartGateway", () => {
  it("does not sign unsupported checksum headers for multipart part uploads", async () => {
    const gateway = new R2MultipartGateway({
      bucket: "original-audio",
      accountID: "a712b19a210fbbaa8dd78678c1fa8f73",
      accessKeyID: "access-key",
      secretAccessKey: "secret-key",
      r2: {} as R2Bucket
    });

    const url = new URL(await gateway.signedPartURL("original-audio/object", "upload-id", 1, "a".repeat(64)));

    expect(url.searchParams.get("X-Amz-SignedHeaders")).toBe("host");
  });

  it("creates a short-lived signed GET URL for private Original Audio", async () => {
    const gateway = new R2MultipartGateway({
      bucket: "original-audio",
      accountID: "a712b19a210fbbaa8dd78678c1fa8f73",
      accessKeyID: "access-key",
      secretAccessKey: "secret-key",
      r2: {} as R2Bucket
    });

    const url = new URL(await gateway.signedReadURL("original-audio/object"));

    expect(url.searchParams.get("X-Amz-Expires")).toBe("900");
    expect(url.searchParams.get("X-Amz-SignedHeaders")).toBe("host");
  });

  it("parses a part when R2 includes checksum metadata and an XML-escaped ETag", () => {
    const parts = parseListParts(`
      <ListPartsResult><Part>
        <PartNumber>1</PartNumber>
        <LastModified>2026-08-25T00:00:00.000Z</LastModified>
        <ETag>&quot;r2-etag&quot;</ETag>
        <ChecksumCRC64NVME>checksum</ChecksumCRC64NVME>
        <Size>74891</Size>
      </Part></ListPartsResult>
    `);

    expect(parts).toEqual([{ partNumber: 1, etag: "r2-etag", byteCount: 74891 }]);
  });
});
