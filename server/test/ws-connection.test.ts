import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import type { Socket } from "node:net";
import test from "node:test";

import { WebSocketConnection } from "../src/ws/connection.ts";

class ThrowingSocket extends EventEmitter {
  destroyed = false;
  writeErrorCode: string;

  constructor(writeErrorCode: string) {
    super();
    this.writeErrorCode = writeErrorCode;
  }

  write(): boolean {
    const error = Object.assign(new Error("socket write failed"), { code: this.writeErrorCode });
    throw error;
  }

  destroy(): this {
    this.destroyed = true;
    this.emit("close");
    return this;
  }
}

test("sendText swallows EPIPE writes and closes connection", () => {
  const socket = new ThrowingSocket("EPIPE");
  const connection = new WebSocketConnection(socket as unknown as Socket);

  let closeCount = 0;
  let errorCount = 0;
  connection.on("close", () => {
    closeCount += 1;
  });
  connection.on("error", () => {
    errorCount += 1;
  });

  assert.doesNotThrow(() => {
    connection.sendText("hello");
  });

  assert.equal(closeCount, 1);
  assert.equal(errorCount, 0);
  assert.equal(socket.destroyed, true);
});

test("sendText emits error for non-benign write failures", () => {
  const socket = new ThrowingSocket("EINVAL");
  const connection = new WebSocketConnection(socket as unknown as Socket);

  let closeCount = 0;
  let errorCount = 0;
  connection.on("close", () => {
    closeCount += 1;
  });
  connection.on("error", () => {
    errorCount += 1;
  });

  assert.doesNotThrow(() => {
    connection.sendText("hello");
  });

  assert.equal(closeCount, 1);
  assert.equal(errorCount, 1);
  assert.equal(socket.destroyed, true);
});
