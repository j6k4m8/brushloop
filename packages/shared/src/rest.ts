/**
 * REST DTO contracts used by the BrushLoop client and server.
 */

import type { CollaborationMode, Id } from "./models.ts";

export interface RegisterRequest {
  email: string;
  password: string;
  displayName: string;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface SessionResponse {
  token: string;
  userId: Id;
  expiresAt: string;
}

export interface InviteContactRequest {
  inviteeEmail: string;
}

export interface AcceptInviteRequest {
  invitationId: Id;
}

export interface CreateArtworkRequest {
  title: string;
  mode: CollaborationMode;
  participantUserIds: Id[];
  firstTurnUserId?: Id | null;
  width: number;
  height: number;
  basePhotoPath?: string | null;
  turnDurationMinutes?: number | null;
}

export interface SubmitTurnRequest {
  artworkId: Id;
}

export interface ArtworkListItem {
  id: Id;
  title: string;
  mode: CollaborationMode;
  participantUserIds: Id[];
  activeParticipantUserId: Id | null;
}
