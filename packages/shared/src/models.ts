/**
 * Shared domain model types for BrushLoop.
 */

export type Id = string;
export type IsoDateTime = string;

export type CollaborationMode = "real_time" | "turn_based";

export type InvitationStatus = "pending" | "accepted" | "declined";

export interface UserRecord {
  id: Id;
  email: string;
  displayName: string;
  passwordHash: string;
  createdAt: IsoDateTime;
}

export interface UserSession {
  token: string;
  userId: Id;
  expiresAt: IsoDateTime;
  createdAt: IsoDateTime;
}

export interface ContactInvitation {
  id: Id;
  inviterUserId: Id;
  inviteeEmail: string;
  inviteeUserId: Id | null;
  status: InvitationStatus;
  createdAt: IsoDateTime;
  respondedAt: IsoDateTime | null;
}

export interface ContactRelation {
  id: Id;
  userAId: Id;
  userBId: Id;
  createdAt: IsoDateTime;
}

export interface Artwork {
  id: Id;
  title: string;
  mode: CollaborationMode;
  width: number;
  height: number;
  basePhotoPath: string | null;
  createdByUserId: Id;
  createdAt: IsoDateTime;
  updatedAt: IsoDateTime;
}

export interface ArtworkParticipant {
  id: Id;
  artworkId: Id;
  userId: Id;
  turnIndex: number;
  joinedAt: IsoDateTime;
}

export interface Layer {
  id: Id;
  artworkId: Id;
  name: string;
  sortOrder: number;
  isVisible: boolean;
  isLocked: boolean;
  createdByUserId: Id;
  createdAt: IsoDateTime;
}

export type VectorPoint = {
  x: number;
  y: number;
  pressure?: number;
};

export interface StrokePayload {
  strokeId: Id;
  tool: "brush" | "eraser";
  color: string;
  size: number;
  opacity: number;
  points: VectorPoint[];
}

export interface CrdtOperation {
  id: Id;
  artworkId: Id;
  layerId: Id;
  actorUserId: Id;
  clientId: string;
  sequence: number;
  lamportTs: number;
  type: "stroke.add" | "stroke.erase" | "layer.toggle_visibility" | "layer.reorder";
  payload: StrokePayload | Record<string, unknown>;
  createdAt: IsoDateTime;
}

export interface ArtworkSnapshot {
  id: Id;
  artworkId: Id;
  versionNumber: number;
  reason: "turn_submitted" | "periodic" | "manual";
  stateJson: string;
  createdAt: IsoDateTime;
}

export interface TurnState {
  id: Id;
  artworkId: Id;
  activeParticipantUserId: Id;
  roundNumber: number;
  turnNumber: number;
  startedAt: IsoDateTime;
  dueAt: IsoDateTime | null;
  completedAt: IsoDateTime | null;
}

export type NotificationChannel = "native_push" | "in_app";

export interface NotificationRecord {
  id: Id;
  userId: Id;
  artworkId: Id | null;
  type: "turn_started" | "turn_expired" | "invite_received";
  payloadJson: string;
  channel: NotificationChannel;
  deliveredAt: IsoDateTime | null;
  createdAt: IsoDateTime;
}
