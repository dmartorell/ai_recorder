import { createHash, randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";

const configuration = loadConfiguration();
const test = configuration ? it : it.skip;

describe("staging editorial corrections", () => {
  test("keeps owner corrections private and preserves the automatic source", async () => {
    const source = await getSource(configuration!.ownerToken);
    const correctionID = randomUUID();
    const speakerID = await editorialSpeakerID();
    let attributionCreated = false;

    try {
      const correction = await request("transcript_text_corrections", {
        method: "POST",
        token: configuration!.ownerToken,
        body: [{ id: correctionID, transcript_segment_id: configuration!.segmentID, content: "Editorial correction" }]
      });
      expect(correction.status).toBe(201);

      const attribution = await request("transcript_speaker_corrections", {
        method: "POST",
        token: configuration!.ownerToken,
        body: [{ transcript_segment_id: configuration!.segmentID, speaker_id: speakerID }]
      });
      expect(attribution.status).toBe(201);
      attributionCreated = true;

      expect((await request(`transcript_text_corrections?transcript_segment_id=eq.${configuration!.segmentID}`, { token: configuration!.ownerToken })).status).toBe(200);
      expect((await request(`transcript_speaker_corrections?transcript_segment_id=eq.${configuration!.segmentID}`, { token: configuration!.ownerToken })).status).toBe(200);

      await expect(readRows("transcript_text_corrections", configuration!.otherOwnerToken).then((rows) => rows.length)).resolves.toBe(0);
      await expect(readRows("transcript_speaker_corrections", configuration!.otherOwnerToken).then((rows) => rows.length)).resolves.toBe(0);
      await expect(readRows(`speakers?id=eq.${speakerID}`, configuration!.otherOwnerToken).then((rows) => rows.length)).resolves.toBe(0);

      const sourceMutation = await request(`transcript_segments?id=eq.${configuration!.segmentID}`, {
        method: "PATCH",
        token: configuration!.ownerToken,
        body: { content: "Mutation must fail" }
      });
      expect(sourceMutation.status).toBeGreaterThanOrEqual(400);
      expect(sourceMutation.status).toBeLessThan(500);
    } finally {
      if (attributionCreated) {
        await request(`transcript_speaker_corrections?transcript_segment_id=eq.${configuration!.segmentID}`, {
          method: "DELETE", token: configuration!.ownerToken
        });
      }
      await request(`transcript_text_corrections?id=eq.${correctionID}`, { method: "DELETE", token: configuration!.ownerToken });
    }

    expect(fingerprint(await getSource(configuration!.ownerToken))).toBe(fingerprint(source));
  });
});

function loadConfiguration() {
  const supabaseURL = process.env.EDITORIAL_TEST_SUPABASE_URL;
  const publishableKey = process.env.EDITORIAL_TEST_SUPABASE_PUBLISHABLE_KEY;
  const ownerToken = process.env.EDITORIAL_TEST_OWNER_TOKEN;
  const otherOwnerToken = process.env.EDITORIAL_TEST_OTHER_OWNER_TOKEN;
  const audioID = process.env.EDITORIAL_TEST_AUDIO_ID;
  const segmentID = process.env.EDITORIAL_TEST_SEGMENT_ID;
  if (!supabaseURL || !publishableKey || !ownerToken || !otherOwnerToken || !audioID || !segmentID) return undefined;
  return { supabaseURL: new URL(supabaseURL), publishableKey, ownerToken, otherOwnerToken, audioID, segmentID };
}

async function editorialSpeakerID() {
  const response = await request(`speakers?audio_id=eq.${configuration!.audioID}&select=id&limit=1`, { token: configuration!.ownerToken });
  expect(response.status).toBe(200);
  const speakers = await response.json() as Array<{ id: string }>;
  expect(speakers).toHaveLength(1);
  return speakers[0]!.id;
}

function fingerprint(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

async function getSource(token: string) {
  const response = await request(`transcript_segments?id=eq.${configuration!.segmentID}&select=id,content,automatic_speaker_id,ordinal,start_time_ms,end_time_ms`, { token });
  expect(response.status).toBe(200);
  const rows = await response.json() as unknown[];
  expect(rows).toHaveLength(1);
  return rows[0];
}

async function readRows(tableAndFilter: string, token: string) {
  const response = await request(`${tableAndFilter}${tableAndFilter.includes("?") ? "&" : "?"}select=id`, { token });
  expect(response.status).toBe(200);
  return response.json() as Promise<unknown[]>;
}

function request(path: string, options: { method?: string; token: string; body?: unknown }) {
  const url = new URL(`rest/v1/${path}`, configuration!.supabaseURL);
  return fetch(url, {
    method: options.method,
    headers: {
      apikey: configuration!.publishableKey,
      Authorization: `Bearer ${options.token}`,
      Prefer: "return=representation",
      ...(options.body ? { "Content-Type": "application/json" } : {})
    },
    body: options.body ? JSON.stringify(options.body) : undefined
  });
}
