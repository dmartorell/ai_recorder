import { describe, expect, it } from "vitest";
import { sha256Stream } from "../src/sha256-stream";

describe("sha256Stream", () => {
  it("hashes a stream without requiring its complete body in memory", async () => {
    const encoder = new TextEncoder();
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(encoder.encode("The quick brown "));
        controller.enqueue(encoder.encode("fox jumps over the lazy dog"));
        controller.close();
      }
    });

    await expect(sha256Stream(stream)).resolves.toBe("d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592");
  });
});
