import { randomBytes } from "node:crypto";

/**
 * Create a cryptographically random bearer token.
 */
export function generateBearerToken(): string {
  return randomBytes(32).toString("base64url");
}
