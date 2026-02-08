import { argon2Sync, randomBytes, timingSafeEqual } from "node:crypto";

const ARGON2_MEMORY = 65_536;
const ARGON2_PASSES = 3;
const ARGON2_PARALLELISM = 1;
const ARGON2_TAG_LENGTH = 32;

/**
 * Hash a plaintext password using Argon2id.
 */
export function hashPassword(plaintext: string): string {
  if (plaintext.length < 8) {
    throw new Error("password must be at least 8 characters");
  }

  const nonce = randomBytes(16);
  const hash = argon2Sync("argon2id", {
    message: plaintext,
    nonce,
    memory: ARGON2_MEMORY,
    passes: ARGON2_PASSES,
    parallelism: ARGON2_PARALLELISM,
    tagLength: ARGON2_TAG_LENGTH
  });

  return [
    "argon2id",
    `m=${ARGON2_MEMORY},t=${ARGON2_PASSES},p=${ARGON2_PARALLELISM},l=${ARGON2_TAG_LENGTH}`,
    nonce.toString("hex"),
    hash.toString("hex")
  ].join("$");
}

/**
 * Verify a plaintext password against the encoded Argon2id hash string.
 */
export function verifyPassword(plaintext: string, encodedHash: string): boolean {
  const parts = encodedHash.split("$");
  if (parts.length !== 4 || parts[0] !== "argon2id") {
    return false;
  }

  const settings = parseSettings(parts[1]);
  if (!settings) {
    return false;
  }

  const nonce = Buffer.from(parts[2], "hex");
  const expected = Buffer.from(parts[3], "hex");
  const actual = argon2Sync("argon2id", {
    message: plaintext,
    nonce,
    memory: settings.memory,
    passes: settings.passes,
    parallelism: settings.parallelism,
    tagLength: settings.tagLength
  });

  if (actual.length !== expected.length) {
    return false;
  }

  return timingSafeEqual(actual, expected);
}

function parseSettings(value: string): {
  memory: number;
  passes: number;
  parallelism: number;
  tagLength: number;
} | null {
  const entries = new Map<string, number>();

  for (const item of value.split(",")) {
    const [key, raw] = item.split("=");
    if (!key || !raw) {
      return null;
    }

    const numeric = Number(raw);
    if (!Number.isFinite(numeric) || numeric <= 0) {
      return null;
    }

    entries.set(key, numeric);
  }

  const memory = entries.get("m");
  const passes = entries.get("t");
  const parallelism = entries.get("p");
  const tagLength = entries.get("l");
  if (!memory || !passes || !parallelism || !tagLength) {
    return null;
  }

  return { memory, passes, parallelism, tagLength };
}
