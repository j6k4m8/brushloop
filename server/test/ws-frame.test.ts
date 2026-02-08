import test from "node:test";
import assert from "node:assert/strict";

import { encodeFrame, tryDecodeFrame } from "../src/ws/connection.ts";

function maskPayload(payload: Buffer, mask: Buffer): Buffer {
  const masked = Buffer.from(payload);
  for (let index = 0; index < masked.length; index += 1) {
    masked[index] ^= mask[index % mask.length];
  }
  return masked;
}

test("encodeFrame/tryDecodeFrame roundtrip for server text frame", () => {
  const payload = Buffer.from("hello", "utf8");
  const encoded = encodeFrame(0x1, payload);
  const decoded = tryDecodeFrame(encoded);

  assert.ok(decoded);
  assert.equal(decoded?.frame.opcode, 0x1);
  assert.equal(decoded?.frame.payload.toString("utf8"), "hello");
});

test("tryDecodeFrame decodes masked client frame", () => {
  const payload = Buffer.from("brushloop", "utf8");
  const mask = Buffer.from([0xaa, 0xbb, 0xcc, 0xdd]);
  const maskedPayload = maskPayload(payload, mask);

  const header = Buffer.from([0x81, 0x80 | payload.length]);
  const frame = Buffer.concat([header, mask, maskedPayload]);

  const decoded = tryDecodeFrame(frame);
  assert.ok(decoded);
  assert.equal(decoded?.frame.payload.toString("utf8"), "brushloop");
});
