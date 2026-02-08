import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

import { hashPassword } from "../src/auth/password.ts";
import { BrushloopDatabase } from "../src/db/database.ts";
import { LocalStorageAdapter } from "../src/storage/local-storage.ts";

function makeTmpRoot(prefix: string): string {
  return fs.mkdtempSync(path.join(process.cwd(), `.tmp-${prefix}-`));
}

test("LocalStorageAdapter writes and reads media bytes", async () => {
  const root = makeTmpRoot("storage");
  const adapter = new LocalStorageAdapter(path.join(root, "media"));
  const bytes = Buffer.from("fake-image-data", "utf8");

  const stored = await adapter.putMediaObject({
    ownerUserId: "user-1",
    originalFilename: "photo.jpg",
    mimeType: "image/jpeg",
    bytes
  });

  assert.equal(stored.byteSize, bytes.length);
  assert.equal(stored.mimeType, "image/jpeg");
  assert.ok(stored.storageKey.endsWith(".jpg"));

  const loaded = await adapter.getMediaObject(stored.storageKey);
  assert.equal(loaded.bytes.toString("utf8"), "fake-image-data");
  assert.equal(loaded.mimeType, "image/jpeg");
});

test("database persists media asset metadata", () => {
  const root = makeTmpRoot("db-media");
  const db = new BrushloopDatabase(path.join(root, "brushloop.sqlite"));

  const owner = db.createUser("media@example.com", "Media User", hashPassword("password123"));

  const created = db.createMediaAsset({
    ownerUserId: owner.id,
    storageDriver: "local",
    storageKey: "2026-02-08/some-key.jpg",
    mimeType: "image/jpeg",
    originalFilename: "capture.jpg",
    byteSize: 2048
  });

  const loaded = db.getMediaAssetById(created.id);
  assert.ok(loaded);
  assert.equal(loaded?.ownerUserId, owner.id);
  assert.equal(loaded?.storageKey, "2026-02-08/some-key.jpg");
  assert.equal(loaded?.originalFilename, "capture.jpg");

  db.close();
});
