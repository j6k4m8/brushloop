import type { IncomingMessage, ServerResponse } from "node:http";

/**
 * Parse request body as JSON or return null for empty body.
 */
export async function readJsonBody(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];

  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }

  if (chunks.length === 0) {
    return null;
  }

  const text = Buffer.concat(chunks).toString("utf8").trim();
  if (text.length === 0) {
    return null;
  }

  return JSON.parse(text);
}

/**
 * Parse request body as binary with max-size guard.
 */
export async function readBinaryBody(req: IncomingMessage, maxBytes: number): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let receivedBytes = 0;

  for await (const chunk of req) {
    const chunkBuffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    receivedBytes += chunkBuffer.length;

    if (receivedBytes > maxBytes) {
      throw new Error(`payload exceeds max size of ${maxBytes} bytes`);
    }

    chunks.push(chunkBuffer);
  }

  return Buffer.concat(chunks);
}

/**
 * Serialize a JSON response with status code.
 */
export function writeJson(res: ServerResponse, statusCode: number, payload: unknown): void {
  const body = JSON.stringify(payload);
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Content-Length", Buffer.byteLength(body));
  res.end(body);
}

/**
 * Serialize a binary response with status code and MIME type.
 */
export function writeBinary(
  res: ServerResponse,
  statusCode: number,
  payload: Buffer,
  mimeType: string
): void {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", mimeType);
  res.setHeader("Content-Length", payload.length);
  res.end(payload);
}

/**
 * Apply permissive CORS headers for local/mobile client usage.
 */
export function applyCors(res: ServerResponse): void {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-File-Name");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
}
