/**
 * WebSocket message contracts for collaboration.
 */

import type { CrdtOperation, Id, IsoDateTime } from "./models.ts";

export interface ClientHelloMessage {
  type: "client.hello";
  token: string;
  clientId: string;
}

export interface ClientJoinArtworkMessage {
  type: "client.join_artwork";
  artworkId: Id;
  sinceLamportTs?: number;
}

export interface ClientLeaveArtworkMessage {
  type: "client.leave_artwork";
  artworkId: Id;
}

export interface ClientApplyOperationsMessage {
  type: "client.apply_operations";
  artworkId: Id;
  operations: CrdtOperation[];
}

export interface ClientRequestSyncMessage {
  type: "client.request_sync";
  artworkId: Id;
}

export type CollaborationClientMessage =
  | ClientHelloMessage
  | ClientJoinArtworkMessage
  | ClientLeaveArtworkMessage
  | ClientApplyOperationsMessage
  | ClientRequestSyncMessage;

export interface ServerHelloAckMessage {
  type: "server.hello_ack";
  userId: Id;
  serverTime: IsoDateTime;
}

export interface ServerPresenceMessage {
  type: "server.presence";
  artworkId: Id;
  onlineUserIds: Id[];
}

export interface ServerOperationsMessage {
  type: "server.operations";
  artworkId: Id;
  operations: CrdtOperation[];
}

export interface ServerSnapshotMessage {
  type: "server.snapshot";
  artworkId: Id;
  versionNumber: number;
  stateJson: string;
}

export interface ServerTurnAdvancedMessage {
  type: "server.turn_advanced";
  artworkId: Id;
  activeParticipantUserId: Id;
  turnNumber: number;
  dueAt: IsoDateTime | null;
}

export interface ServerErrorMessage {
  type: "server.error";
  code: string;
  message: string;
}

export type CollaborationServerMessage =
  | ServerHelloAckMessage
  | ServerPresenceMessage
  | ServerOperationsMessage
  | ServerSnapshotMessage
  | ServerTurnAdvancedMessage
  | ServerErrorMessage;
