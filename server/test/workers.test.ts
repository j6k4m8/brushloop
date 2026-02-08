import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

import { hashPassword } from "../src/auth/password.ts";
import { BrushloopDatabase } from "../src/db/database.ts";
import { NotificationDispatcher } from "../src/notifications/dispatcher.ts";
import type { NotificationAdapter } from "../src/notifications/adapter.ts";
import { TurnExpiryWorker } from "../src/turns/expiry-worker.ts";
import type { NotificationRecord } from "../../packages/shared/src/index.ts";

function makeTmpPath(name: string): string {
  const root = fs.mkdtempSync(path.join(process.cwd(), ".tmp-"));
  return path.join(root, `${name}.sqlite`);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

class MemoryNotificationAdapter implements NotificationAdapter {
  readonly delivered: string[] = [];

  async dispatch(notification: NotificationRecord): Promise<void> {
    this.delivered.push(notification.id);
  }
}

test("NotificationDispatcher delivers pending notifications", async () => {
  const db = new BrushloopDatabase(makeTmpPath("notify"));
  const user = db.createUser("notify@example.com", "Notify", hashPassword("password123"));

  const created = db.createNotification({
    userId: user.id,
    artworkId: null,
    type: "invite_received",
    payloadJson: JSON.stringify({}),
    channel: "in_app"
  });

  const adapter = new MemoryNotificationAdapter();
  const dispatcher = new NotificationDispatcher(db, adapter, 20);
  dispatcher.start();

  await sleep(100);
  dispatcher.stop();

  assert.deepEqual(adapter.delivered, [created.id]);
  assert.equal(db.listPendingNotifications().length, 0);

  db.close();
});

test("TurnExpiryWorker advances expired turns and emits notifications", async () => {
  const db = new BrushloopDatabase(makeTmpPath("turn-expiry"));

  const userA = db.createUser("ta@example.com", "TA", hashPassword("password123"));
  const userB = db.createUser("tb@example.com", "TB", hashPassword("password123"));

  db.acceptInvitation(db.createContactInvitation(userA.id, userB.email).id, userB.id);

  const details = db.createArtwork({
    title: "Timed Turn",
    mode: "turn_based",
    width: 200,
    height: 200,
    basePhotoPath: null,
    createdByUserId: userA.id,
    participantUserIds: [userA.id, userB.id],
    turnDurationMinutes: 0.0005
  });

  const turns: number[] = [];
  const worker = new TurnExpiryWorker({
    db,
    intervalMs: 20,
    snapshotEveryTurns: 3,
    onTurnAdvanced: (turn) => {
      turns.push(turn.turnNumber);
    }
  });

  worker.start();
  await sleep(200);
  worker.stop();

  const refreshed = db.getArtworkDetailsForUser(details.artwork.id, userA.id);
  assert.ok(refreshed?.currentTurn);
  assert.ok(refreshed!.currentTurn!.turnNumber > 1);

  const pending = db.listPendingNotifications();
  assert.ok(pending.some((item) => item.type === "turn_expired"));
  assert.ok(pending.some((item) => item.type === "turn_started"));
  assert.ok(turns.length > 0);

  db.close();
});
