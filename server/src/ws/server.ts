import { createHash } from "node:crypto";
import type { IncomingMessage } from "node:http";
import type { Socket } from "node:net";

import { WebSocketConnection } from "./connection.ts";

const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/**
 * Upgrade an HTTP request to a raw WebSocket connection.
 */
export function upgradeToWebSocket(
  req: IncomingMessage,
  socket: Socket,
  head: Buffer,
  onConnection: (connection: WebSocketConnection) => void
): void {
  const key = req.headers["sec-websocket-key"];
  const upgrade = req.headers.upgrade;

  if (typeof key !== "string" || upgrade?.toLowerCase() !== "websocket") {
    socket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
    socket.destroy();
    return;
  }

  const accept = createHash("sha1").update(`${key}${WS_GUID}`).digest("base64");

  socket.write(
    [
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Accept: ${accept}`,
      "\r\n"
    ].join("\r\n")
  );

  onConnection(new WebSocketConnection(socket, head));
}
