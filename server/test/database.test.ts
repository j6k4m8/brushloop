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

test("participants can rename artwork titles", () => {
  const dbPath = makeTmpPath("rename-artwork");
  const db = new BrushloopDatabase(dbPath);

  const user = db.createUser("rename@example.com", "Renamer", hashPassword("password123"));
  const details = db.createArtwork({
    title: "Original Title",
    mode: "real_time",
    width: 1200,
    height: 800,
    basePhotoPath: null,
    createdByUserId: user.id,
    participantUserIds: [user.id],
    turnDurationMinutes: null
  });

  db.updateArtworkTitle(details.artwork.id, user.id, "Renamed Title");

  const refreshed = db.getArtworkDetailsForUser(details.artwork.id, user.id);
  assert.equal(refreshed?.artwork.title, "Renamed Title");

  db.close();
});

test("chat helpers return direct messages and shared artwork events", () => {
  const dbPath = makeTmpPath("chat");
  const db = new BrushloopDatabase(dbPath);

  const userA = db.createUser("chat-a@example.com", "Chat A", hashPassword("password123"));
  const userB = db.createUser("chat-b@example.com", "Chat B", hashPassword("password123"));
  db.acceptInvitation(db.createContactInvitation(userA.id, userB.email).id, userB.id);

  const artwork = db.createArtwork({
    title: "Chat Shared Art",
    mode: "turn_based",
    width: 800,
    height: 600,
    basePhotoPath: null,
    createdByUserId: userA.id,
    participantUserIds: [userA.id, userB.id],
    turnDurationMinutes: null
  });

  db.createNotification({
    userId: userB.id,
    artworkId: artwork.artwork.id,
    type: "turn_started",
    payloadJson: JSON.stringify({ artworkId: artwork.artwork.id, turnNumber: 1 }),
    channel: "in_app"
  });

  db.createDirectMessage(userA.id, userB.id, "Ready to draw?");
  db.createDirectMessage(userB.id, userA.id, "Yep, let us go.");

  const contactsBeforeRead = db.listContacts(userA.id);
  assert.equal(contactsBeforeRead[0]?.unreadMessageCount, 1);

  const messages = db.listDirectMessages(userA.id, userB.id);
  assert.equal(messages.length, 2);
  assert.deepEqual(
    messages.map((message) => message.senderUserId).sort(),
    [userA.id, userB.id].sort()
  );

  db.markDirectMessagesRead(userA.id, userB.id);
  const contactsAfterRead = db.listContacts(userA.id);
  assert.equal(contactsAfterRead[0]?.unreadMessageCount, 0);

  const sharedArtworks = db.listSharedArtworksForUsers(userA.id, userB.id);
  assert.equal(sharedArtworks.length, 1);
  assert.equal(sharedArtworks[0]?.id, artwork.artwork.id);

  const creationEvents = db.listSharedArtworkCreationEvents(userA.id, userB.id);
  assert.equal(creationEvents.length, 1);
  assert.equal(creationEvents[0]?.artworkId, artwork.artwork.id);
  assert.equal(creationEvents[0]?.actorUserId, userA.id);

  const turnEvents = db.listSharedTurnStartedEvents(userA.id, userB.id);
  assert.equal(turnEvents.length, 1);
  assert.equal(turnEvents[0]?.targetUserId, userB.id);
  assert.equal(turnEvents[0]?.artworkId, artwork.artwork.id);

  db.close();
});
