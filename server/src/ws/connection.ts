import { EventEmitter } from "node:events";
import type { Socket } from "node:net";

interface Frame {
  opcode: number;
  payload: Buffer;
}

/**
 * Minimal RFC6455 text-oriented WebSocket connection.
 * It supports JSON text frames, ping/pong, and close handling.
 */
export class WebSocketConnection extends EventEmitter {
  private buffer = Buffer.alloc(0);
  private closed = false;
  private readonly socket: Socket;

  constructor(socket: Socket, initialData?: Buffer) {
    super();
    this.socket = socket;

    this.socket.on("data", (chunk) => this.handleData(chunk));
    this.socket.on("error", (error) => {
      this.emit("error", error);
      this.close();
    });
    this.socket.on("close", () => {
      if (!this.closed) {
        this.closed = true;
        this.emit("close");
      }
    });

    if (initialData && initialData.length > 0) {
      this.handleData(initialData);
    }
  }

  sendJson(payload: unknown): void {
    this.sendText(JSON.stringify(payload));
  }

  sendText(text: string): void {
    if (this.closed) {
      return;
    }

    const payload = Buffer.from(text, "utf8");
    this.writeFrame(encodeFrame(0x1, payload));
  }

  close(): void {
    if (this.closed) {
      return;
    }

    this.closed = true;
    try {
      this.socket.write(encodeFrame(0x8, Buffer.alloc(0)));
    } catch {
      // Ignore close-frame write failures. The socket is already unusable.
    }
    this.socket.destroy();
    this.emit("close");
  }

  private handleData(chunk: Buffer): void {
    this.buffer = Buffer.concat([this.buffer, chunk]);

    while (true) {
      const frame = tryDecodeFrame(this.buffer);
      if (!frame) {
        return;
      }

      this.buffer = this.buffer.subarray(frame.consumedBytes);
      this.handleFrame(frame.frame);
    }
  }

  private handleFrame(frame: Frame): void {
    switch (frame.opcode) {
      case 0x1:
        this.emit("text", frame.payload.toString("utf8"));
        break;
      case 0x8:
        this.close();
        break;
      case 0x9:
        this.writeFrame(encodeFrame(0xa, frame.payload));
        break;
      case 0xa:
        break;
      default:
        this.emit("error", new Error(`unsupported opcode ${frame.opcode}`));
    }
  }

  private writeFrame(frame: Buffer): void {
    if (this.closed) {
      return;
    }

    try {
      this.socket.write(frame);
    } catch (error) {
      if (!isBenignSocketWriteError(error)) {
        this.emit("error", error);
      }
      this.close();
    }
  }
}

export function encodeFrame(opcode: number, payload: Buffer): Buffer {
  const finAndOpcode = 0x80 | (opcode & 0x0f);

  if (payload.length < 126) {
    return Buffer.concat([Buffer.from([finAndOpcode, payload.length]), payload]);
  }

  if (payload.length < 65_536) {
    const header = Buffer.alloc(4);
    header[0] = finAndOpcode;
    header[1] = 126;
    header.writeUInt16BE(payload.length, 2);
    return Buffer.concat([header, payload]);
  }

  const header = Buffer.alloc(10);
  header[0] = finAndOpcode;
  header[1] = 127;
  header.writeBigUInt64BE(BigInt(payload.length), 2);
  return Buffer.concat([header, payload]);
}

export function tryDecodeFrame(buffer: Buffer): { frame: Frame; consumedBytes: number } | null {
  if (buffer.length < 2) {
    return null;
  }

  const firstByte = buffer[0];
  const secondByte = buffer[1];
  const opcode = firstByte & 0x0f;
  const masked = (secondByte & 0x80) !== 0;
  let payloadLength = secondByte & 0x7f;
  let offset = 2;

  if (payloadLength === 126) {
    if (buffer.length < offset + 2) {
      return null;
    }
    payloadLength = buffer.readUInt16BE(offset);
    offset += 2;
  } else if (payloadLength === 127) {
    if (buffer.length < offset + 8) {
      return null;
    }

    const bigLength = buffer.readBigUInt64BE(offset);
    if (bigLength > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new Error("frame payload too large");
    }

    payloadLength = Number(bigLength);
    offset += 8;
  }

  let mask = Buffer.alloc(0);
  if (masked) {
    if (buffer.length < offset + 4) {
      return null;
    }
    mask = buffer.subarray(offset, offset + 4);
    offset += 4;
  }

  if (buffer.length < offset + payloadLength) {
    return null;
  }

  const payload = Buffer.from(buffer.subarray(offset, offset + payloadLength));

  if (masked) {
    for (let index = 0; index < payload.length; index += 1) {
      payload[index] = payload[index] ^ mask[index % 4];
    }
  }

  return {
    frame: {
      opcode,
      payload
    },
    consumedBytes: offset + payloadLength
  };
}

function isBenignSocketWriteError(error: unknown): boolean {
  const code = typeof error === "object" && error !== null && "code" in error ? (error as { code?: string }).code : undefined;
  return code === "EPIPE" || code === "ECONNRESET" || code === "ERR_STREAM_DESTROYED";
}
