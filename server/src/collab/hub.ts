import type { IncomingMessage } from "node:http";
import type { Socket } from "node:net";

import {
  parseCollaborationClientMessage,
  type CollaborationClientMessage,
  type CollaborationMode,
  type CollaborationServerMessage,
  type CrdtOperation,
  type Id,
  type UserRecord
} from "../../../packages/shared/src/index.ts";
import type { BrushloopDatabase } from "../db/database.ts";
import { upgradeToWebSocket } from "../ws/server.ts";
import type { WebSocketConnection } from "../ws/connection.ts";

interface ConnectionContext {
  user: UserRecord;
  clientId: string;
  joinedArtworkIds: Set<Id>;
}

/**
 * Collaboration hub for authenticated WebSocket connections.
 */
export class CollaborationHub {
  private readonly contexts = new Map<WebSocketConnection, ConnectionContext>();
  private readonly rooms = new Map<Id, Set<WebSocketConnection>>();
  private readonly db: BrushloopDatabase;

  constructor(db: BrushloopDatabase) {
    this.db = db;
  }

  handleUpgrade(req: IncomingMessage, socket: Socket, head: Buffer): void {
    upgradeToWebSocket(req, socket, head, (connection) => this.attachConnection(connection));
  }

  private attachConnection(connection: WebSocketConnection): void {
    connection.on("text", (text: string) => {
      void this.handleMessage(connection, text);
    });
    connection.on("close", () => {
      this.removeConnection(connection);
    });
    connection.on("error", (error: unknown) => {
      console.error("WebSocket error:", error);
      this.removeConnection(connection);
    });

    connection.sendJson({
      type: "server.hello_ack",
      userId: "",
      serverTime: new Date().toISOString(),
      needsAuth: true
    });
  }

  private async handleMessage(connection: WebSocketConnection, rawMessage: string): Promise<void> {
    let message: CollaborationClientMessage;
    try {
      message = parseCollaborationClientMessage(JSON.parse(rawMessage));
    } catch (error) {
      this.sendError(connection, "invalid_message", error instanceof Error ? error.message : "invalid message");
      return;
    }

    const context = this.contexts.get(connection);
    if (!context) {
      if (message.type !== "client.hello") {
        this.sendError(connection, "auth_required", "client.hello is required before other messages");
        return;
      }

      const session = this.db.getSession(message.token);
      if (!session) {
        this.sendError(connection, "invalid_session", "session is invalid or expired");
        connection.close();
        return;
      }

      const user = this.db.getUserById(session.userId);
      if (!user) {
        this.sendError(connection, "invalid_session_user", "session user not found");
        connection.close();
        return;
      }

      this.contexts.set(connection, {
        user,
        clientId: message.clientId,
        joinedArtworkIds: new Set()
      });
      this.send(connection, {
        type: "server.hello_ack",
        userId: user.id,
        serverTime: new Date().toISOString()
      });
      return;
    }

    if (message.type === "client.hello") {
      this.sendError(connection, "already_authenticated", "connection is already authenticated");
      return;
    }

    switch (message.type) {
      case "client.join_artwork":
        this.joinArtwork(connection, context, message.artworkId, message.sinceLamportTs ?? 0);
        return;
      case "client.leave_artwork":
        this.leaveArtwork(connection, context, message.artworkId);
        return;
      case "client.request_sync":
        this.sendArtworkSync(connection, context.user.id, message.artworkId, 0);
        return;
      case "client.apply_operations":
        this.applyOperations(connection, context, message);
        return;
      default:
        this.sendError(connection, "unsupported_message", `unsupported message type ${(message as { type: string }).type}`);
    }
  }

  private joinArtwork(connection: WebSocketConnection, context: ConnectionContext, artworkId: Id, sinceLamportTs: number): void {
    const details = this.db.getArtworkDetailsForUser(artworkId, context.user.id);
    if (!details) {
      this.sendError(connection, "artwork_access_denied", "cannot join artwork");
      return;
    }

    const room = this.rooms.get(artworkId) ?? new Set<WebSocketConnection>();
    room.add(connection);
    this.rooms.set(artworkId, room);
    context.joinedArtworkIds.add(artworkId);

    this.sendArtworkSync(connection, context.user.id, artworkId, sinceLamportTs);
    this.broadcastPresence(artworkId);
  }

  private leaveArtwork(connection: WebSocketConnection, context: ConnectionContext, artworkId: Id): void {
    const room = this.rooms.get(artworkId);
    if (!room) {
      return;
    }

    room.delete(connection);
    context.joinedArtworkIds.delete(artworkId);

    if (room.size === 0) {
      this.rooms.delete(artworkId);
      return;
    }

    this.broadcastPresence(artworkId);
  }

  private applyOperations(
    connection: WebSocketConnection,
    context: ConnectionContext,
    message: Extract<CollaborationClientMessage, { type: "client.apply_operations" }>
  ): void {
    if (!context.joinedArtworkIds.has(message.artworkId)) {
      this.sendError(connection, "not_joined", "join artwork before applying operations");
      return;
    }

    const details = this.db.getArtworkDetailsForUser(message.artworkId, context.user.id);
    if (!details) {
      this.sendError(connection, "artwork_access_denied", "artwork not available");
      return;
    }

    const mode = details.artwork.mode as CollaborationMode;
    if (mode === "turn_based" && details.currentTurn && details.currentTurn.activeParticipantUserId !== context.user.id) {
      this.sendError(connection, "turn_locked", "it is not your turn");
      return;
    }

    const layerIds = new Set(details.layers.map((layer) => layer.id));
    const persisted: CrdtOperation[] = [];

    for (const operation of message.operations) {
      if (!layerIds.has(operation.layerId)) {
        this.sendError(connection, "invalid_layer", `layer ${operation.layerId} is not part of this artwork`);
        return;
      }

      if (operation.actorUserId !== context.user.id) {
        this.sendError(connection, "invalid_actor", "operation actor must match authenticated user");
        return;
      }

      const stored = this.db.addCrdtOperation({
        artworkId: message.artworkId,
        layerId: operation.layerId,
        actorUserId: context.user.id,
        clientId: context.clientId,
        sequence: operation.sequence,
        lamportTs: operation.lamportTs,
        type: operation.type,
        payload: operation.payload
      });
      persisted.push(stored);
    }

    this.broadcast(message.artworkId, {
      type: "server.operations",
      artworkId: message.artworkId,
      operations: persisted
    });
  }

  private sendArtworkSync(connection: WebSocketConnection, userId: Id, artworkId: Id, sinceLamportTs: number): void {
    const details = this.db.getArtworkDetailsForUser(artworkId, userId);
    if (!details) {
      this.sendError(connection, "artwork_access_denied", "cannot sync artwork");
      return;
    }

    const snapshot = this.db.getLatestSnapshot(artworkId);
    if (snapshot) {
      this.send(connection, {
        type: "server.snapshot",
        artworkId,
        versionNumber: snapshot.versionNumber,
        stateJson: snapshot.stateJson
      });
    }

    const operations = this.db.getOperationsSince(artworkId, sinceLamportTs);
    if (operations.length > 0) {
      this.send(connection, {
        type: "server.operations",
        artworkId,
        operations
      });
    }

    if (details.currentTurn) {
      this.send(connection, {
        type: "server.turn_advanced",
        artworkId,
        activeParticipantUserId: details.currentTurn.activeParticipantUserId,
        turnNumber: details.currentTurn.turnNumber,
        dueAt: details.currentTurn.dueAt
      });
    }
  }

  private broadcastPresence(artworkId: Id): void {
    const room = this.rooms.get(artworkId);
    if (!room) {
      return;
    }

    const onlineUserIds = [...room]
      .map((connection) => this.contexts.get(connection)?.user.id)
      .filter((id): id is Id => Boolean(id));

    this.broadcast(artworkId, {
      type: "server.presence",
      artworkId,
      onlineUserIds
    });
  }

  broadcastTurnAdvanced(artworkId: Id, activeParticipantUserId: Id, turnNumber: number, dueAt: string | null): void {
    this.broadcast(artworkId, {
      type: "server.turn_advanced",
      artworkId,
      activeParticipantUserId,
      turnNumber,
      dueAt
    });
  }

  private broadcast(artworkId: Id, payload: CollaborationServerMessage): void {
    const room = this.rooms.get(artworkId);
    if (!room) {
      return;
    }

    for (const connection of room) {
      this.send(connection, payload);
    }
  }

  private send(connection: WebSocketConnection, payload: CollaborationServerMessage): void {
    try {
      connection.sendJson(payload);
    } catch (error) {
      if (!isBenignSocketWriteError(error)) {
        console.error("WebSocket send failed:", error);
      }
      connection.close();
    }
  }

  private sendError(connection: WebSocketConnection, code: string, message: string): void {
    this.send(connection, {
      type: "server.error",
      code,
      message
    });
  }

  private removeConnection(connection: WebSocketConnection): void {
    const context = this.contexts.get(connection);
    if (context) {
      for (const artworkId of context.joinedArtworkIds) {
        const room = this.rooms.get(artworkId);
        if (!room) {
          continue;
        }

        room.delete(connection);
        if (room.size === 0) {
          this.rooms.delete(artworkId);
        } else {
          this.broadcastPresence(artworkId);
        }
      }
    }

    this.contexts.delete(connection);
  }
}

function isBenignSocketWriteError(error: unknown): boolean {
  const code = typeof error === "object" && error !== null && "code" in error ? (error as { code?: string }).code : undefined;
  return code === "EPIPE" || code === "ECONNRESET" || code === "ERR_STREAM_DESTROYED";
}
