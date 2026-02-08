/**
 * Runtime validators for external input.
 * These helpers enforce wire-level safety at API boundaries.
 */

import type {
  CollaborationClientMessage,
  ClientApplyOperationsMessage,
  ClientHelloMessage,
  ClientJoinArtworkMessage,
  ClientLeaveArtworkMessage,
  ClientRequestSyncMessage
} from "./protocol.ts";
import type {
  CreateArtworkRequest,
  InviteContactRequest,
  LoginRequest,
  RegisterRequest,
  SubmitTurnRequest
} from "./rest.ts";

function assertObject(value: unknown, context: string): asserts value is Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${context} must be an object`);
  }
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${field} must be a non-empty string`);
  }

  return value;
}

function requireNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || Number.isNaN(value)) {
    throw new Error(`${field} must be a number`);
  }

  return value;
}

function requireStringArray(value: unknown, field: string): string[] {
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string" || item.length === 0)) {
    throw new Error(`${field} must be an array of non-empty strings`);
  }

  return value;
}

/**
 * Parse and validate register request payload.
 */
export function parseRegisterRequest(input: unknown): RegisterRequest {
  assertObject(input, "register request");

  return {
    email: requireString(input.email, "email").toLowerCase(),
    password: requireString(input.password, "password"),
    displayName: requireString(input.displayName, "displayName")
  };
}

/**
 * Parse and validate login request payload.
 */
export function parseLoginRequest(input: unknown): LoginRequest {
  assertObject(input, "login request");

  return {
    email: requireString(input.email, "email").toLowerCase(),
    password: requireString(input.password, "password")
  };
}

/**
 * Parse and validate contact invite request payload.
 */
export function parseInviteContactRequest(input: unknown): InviteContactRequest {
  assertObject(input, "invite contact request");

  return {
    inviteeEmail: requireString(input.inviteeEmail, "inviteeEmail").toLowerCase()
  };
}

/**
 * Parse and validate artwork creation request payload.
 */
export function parseCreateArtworkRequest(input: unknown): CreateArtworkRequest {
  assertObject(input, "create artwork request");
  const mode = requireString(input.mode, "mode");

  if (mode !== "real_time" && mode !== "turn_based") {
    throw new Error("mode must be either real_time or turn_based");
  }

  const turnDurationMinutes = input.turnDurationMinutes;
  if (turnDurationMinutes != null && (typeof turnDurationMinutes !== "number" || turnDurationMinutes <= 0)) {
    throw new Error("turnDurationMinutes must be a positive number when provided");
  }

  return {
    title: requireString(input.title, "title"),
    mode,
    participantUserIds: requireStringArray(input.participantUserIds, "participantUserIds"),
    width: requireNumber(input.width, "width"),
    height: requireNumber(input.height, "height"),
    basePhotoPath: input.basePhotoPath == null ? null : requireString(input.basePhotoPath, "basePhotoPath"),
    turnDurationMinutes: turnDurationMinutes == null ? null : turnDurationMinutes
  };
}

/**
 * Parse and validate submit turn request payload.
 */
export function parseSubmitTurnRequest(input: unknown): SubmitTurnRequest {
  assertObject(input, "submit turn request");

  return {
    artworkId: requireString(input.artworkId, "artworkId")
  };
}

/**
 * Parse and validate a collaboration client WebSocket message.
 */
export function parseCollaborationClientMessage(input: unknown): CollaborationClientMessage {
  assertObject(input, "collaboration message");
  const type = requireString(input.type, "type");

  switch (type) {
    case "client.hello": {
      const payload: ClientHelloMessage = {
        type,
        token: requireString(input.token, "token"),
        clientId: requireString(input.clientId, "clientId")
      };
      return payload;
    }
    case "client.join_artwork": {
      const payload: ClientJoinArtworkMessage = {
        type,
        artworkId: requireString(input.artworkId, "artworkId")
      };

      if (input.sinceLamportTs != null) {
        payload.sinceLamportTs = requireNumber(input.sinceLamportTs, "sinceLamportTs");
      }

      return payload;
    }
    case "client.leave_artwork": {
      const payload: ClientLeaveArtworkMessage = {
        type,
        artworkId: requireString(input.artworkId, "artworkId")
      };
      return payload;
    }
    case "client.apply_operations": {
      if (!Array.isArray(input.operations)) {
        throw new Error("operations must be an array");
      }

      const payload: ClientApplyOperationsMessage = {
        type,
        artworkId: requireString(input.artworkId, "artworkId"),
        operations: input.operations as ClientApplyOperationsMessage["operations"]
      };
      return payload;
    }
    case "client.request_sync": {
      const payload: ClientRequestSyncMessage = {
        type,
        artworkId: requireString(input.artworkId, "artworkId")
      };
      return payload;
    }
    default:
      throw new Error(`unsupported message type: ${type}`);
  }
}
