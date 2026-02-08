import test from "node:test";
import assert from "node:assert/strict";

import { hashPassword, verifyPassword } from "../src/auth/password.ts";

test("hashPassword produces verifiable argon2 hash", () => {
  const hash = hashPassword("my-very-strong-password");
  assert.equal(verifyPassword("my-very-strong-password", hash), true);
  assert.equal(verifyPassword("wrong-password", hash), false);
});

