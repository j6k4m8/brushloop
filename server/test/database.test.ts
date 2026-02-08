import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

import { hashPassword } from "../src/auth/password.ts";
import { BrushloopDatabase } from "../src/db/database.ts";

function makeTmpPath(name: string): string {
  const root = fs.mkdtempSync(path.join(process.cwd(), ".tmp-"));
  return path.join(root, `${name}.sqlite`);
}

test("database creates users and login sessions", () => {
  const dbPath = makeTmpPath("auth");
  const db = new BrushloopDatabase(dbPath);

  const user = db.createUser("a@example.com", "A", hashPassword("password123"));
  const fetched = db.getUserByEmail("a@example.com");
  assert.equal(fetched?.id, user.id);

  const session = db.createSession(user.id, 1);
  const loadedSession = db.getSession(session.token);
  assert.equal(loadedSession?.userId, user.id);

  db.close();
});

test("turn submission advances round robin", () => {
  const dbPath = makeTmpPath("turns");
  const db = new BrushloopDatabase(dbPath);

  const userA = db.createUser("a@example.com", "A", hashPassword("password123"));
  const userB = db.createUser("b@example.com", "B", hashPassword("password123"));

  db.acceptInvitation(db.createContactInvitation(userA.id, userB.email).id, userB.id);

  const details = db.createArtwork({
    title: "Turn Art",
    mode: "turn_based",
    width: 100,
    height: 100,
    basePhotoPath: null,
    createdByUserId: userA.id,
    participantUserIds: [userA.id, userB.id],
    turnDurationMinutes: null
  });

  const nextTurn = db.submitTurn(details.artwork.id, details.currentTurn!.activeParticipantUserId);
  assert.equal(nextTurn.activeParticipantUserId, userB.id);
  assert.equal(nextTurn.turnNumber, 2);

  db.close();
});

test("database allows creating a solo artwork", () => {
  const dbPath = makeTmpPath("solo");
  const db = new BrushloopDatabase(dbPath);

  const user = db.createUser("solo@example.com", "Solo", hashPassword("password123"));

  const details = db.createArtwork({
    title: "Solo Art",
    mode: "real_time",
    width: 800,
    height: 600,
    basePhotoPath: null,
    createdByUserId: user.id,
    participantUserIds: [user.id],
    turnDurationMinutes: null
  });

  assert.equal(details.participants.length, 1);
  assert.equal(details.participants[0]?.userId, user.id);
  assert.equal(details.artwork.mode, "real_time");

  db.close();
});

test("declining an invitation marks it declined and does not create contacts", () => {
  const dbPath = makeTmpPath("decline-invite");
  const db = new BrushloopDatabase(dbPath);

  const inviter = db.createUser("inviter@example.com", "Inviter", hashPassword("password123"));
  const invitee = db.createUser("invitee@example.com", "Invitee", hashPassword("password123"));

  const invitation = db.createContactInvitation(inviter.id, invitee.email);
  const declined = db.declineInvitation(invitation.id, invitee.id);

  assert.equal(declined.status, "declined");
  assert.equal(declined.inviteeUserId, invitee.id);
  assert.equal(db.isContactPair(inviter.id, invitee.id), false);

  db.close();
});

test("creating multiple layers increments sort order", () => {
  const dbPath = makeTmpPath("layers");
  const db = new BrushloopDatabase(dbPath);

  const user = db.createUser("layers@example.com", "Layers", hashPassword("password123"));
  const details = db.createArtwork({
    title: "Layered Art",
    mode: "real_time",
    width: 1200,
    height: 800,
    basePhotoPath: null,
    createdByUserId: user.id,
    participantUserIds: [user.id],
    turnDurationMinutes: null
  });

  const firstAdded = db.createLayer(details.artwork.id, user.id);
  const secondAdded = db.createLayer(details.artwork.id, user.id, "Highlights");

  assert.equal(firstAdded.sortOrder + 1, secondAdded.sortOrder);
  assert.equal(secondAdded.name, "Highlights");

  const refreshed = db.getArtworkDetailsForUser(details.artwork.id, user.id);
  assert.equal(refreshed?.layers.length, 3);

  db.close();
});
