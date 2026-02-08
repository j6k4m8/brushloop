import test from "node:test";
import assert from "node:assert/strict";

import {
  parseCollaborationClientMessage,
  parseCreateArtworkRequest,
  parseLoginRequest,
  parseRegisterRequest
} from "../src/index.ts";

test("parseRegisterRequest normalizes email", () => {
  const parsed = parseRegisterRequest({
    email: "USER@Example.COM",
    password: "secret123",
    displayName: "Painter"
  });

  assert.equal(parsed.email, "user@example.com");
  assert.equal(parsed.displayName, "Painter");
});

test("parseLoginRequest rejects missing password", () => {
  assert.throws(
    () => parseLoginRequest({ email: "user@example.com", password: "" }),
    /password must be a non-empty string/
  );
});

test("parseCreateArtworkRequest validates mode", () => {
  assert.throws(
    () =>
      parseCreateArtworkRequest({
        title: "New Art",
        mode: "unknown",
        participantUserIds: ["u1", "u2"],
        width: 1024,
        height: 768
      }),
    /mode must be either real_time or turn_based/
  );
});

test("parseCreateArtworkRequest parses turn-based payload", () => {
  const parsed = parseCreateArtworkRequest({
    title: "Round Robin",
    mode: "turn_based",
    participantUserIds: ["u1", "u2"],
    firstTurnUserId: "u2",
    width: 1920,
    height: 1080,
    turnDurationMinutes: 60
  });

  assert.equal(parsed.mode, "turn_based");
  assert.equal(parsed.firstTurnUserId, "u2");
  assert.equal(parsed.turnDurationMinutes, 60);
  assert.deepEqual(parsed.participantUserIds, ["u1", "u2"]);
});

test("parseCollaborationClientMessage validates hello message", () => {
  const parsed = parseCollaborationClientMessage({
    type: "client.hello",
    token: "abc",
    clientId: "device-1"
  });

  assert.equal(parsed.type, "client.hello");
});

test("parseCollaborationClientMessage rejects unknown type", () => {
  assert.throws(
    () =>
      parseCollaborationClientMessage({
        type: "client.unknown"
      }),
    /unsupported message type/
  );
});
