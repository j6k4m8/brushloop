import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { Socket } from "node:net";

import {
  parseCreateArtworkRequest,
  parseInviteContactRequest,
  parseLoginRequest,
  parseRegisterRequest,
  parseSendChatMessageRequest,
  parseUpdateProfileRequest,
  parseSubmitTurnRequest,
  parseUpdateArtworkTitleRequest
} from "../../packages/shared/src/index.ts";
import { hashPassword, verifyPassword } from "./auth/password.ts";
import { CollaborationHub } from "./collab/hub.ts";
import { loadConfig } from "./config.ts";
import { BrushloopDatabase } from "./db/database.ts";
import { Router } from "./http/router.ts";
import { applyCors, readBinaryBody, readJsonBody, writeBinary, writeJson } from "./http/utils.ts";
import { NotificationDispatcher } from "./notifications/dispatcher.ts";
import { LocalNotificationAdapter } from "./notifications/local-adapter.ts";
import { createStorageAdapter } from "./storage/factory.ts";
import { TurnExpiryWorker } from "./turns/expiry-worker.ts";

interface AppServer {
  start: () => Promise<void>;
  stop: () => Promise<void>;
  db: BrushloopDatabase;
}

/**
 * Build and configure the HTTP application server.
 */
export function createAppServer(): AppServer {
  const config = loadConfig();
  const db = new BrushloopDatabase(config.sqlitePath);
  const storageAdapter = createStorageAdapter(config);
  const collaborationHub = new CollaborationHub(db);
  const notificationDispatcher = new NotificationDispatcher(
    db,
    new LocalNotificationAdapter(config.notificationLogPath),
    config.notificationDispatchIntervalMs
  );
  const turnExpiryWorker = new TurnExpiryWorker({
    db,
    intervalMs: config.turnExpiryCheckIntervalMs,
    snapshotEveryTurns: config.snapshotEveryTurns,
    onTurnAdvanced: (turn) => {
      collaborationHub.broadcastTurnAdvanced(
        turn.artworkId,
        turn.activeParticipantUserId,
        turn.turnNumber,
        turn.dueAt
      );
    }
  });
  const router = new Router();
  const activeSockets = new Set<Socket>();

  router.register("GET", "/health", ({ res }) => {
    writeJson(res, 200, {
      ok: true,
      service: "brushloop-server",
      timestamp: new Date().toISOString()
    });
  });

  router.register("POST", "/api/auth/register", async ({ req, res }) => {
    const payload = parseRegisterRequest(await readJsonBody(req));
    const existing = db.getUserByEmail(payload.email);
    if (existing) {
      writeJson(res, 409, { error: "email_already_registered" });
      return;
    }

    const user = db.createUser(payload.email, payload.displayName, hashPassword(payload.password));
    const session = db.createSession(user.id, config.sessionTtlHours);

    writeJson(res, 201, {
      token: session.token,
      userId: session.userId,
      expiresAt: session.expiresAt,
      user: {
        id: user.id,
        email: user.email,
        displayName: user.displayName
      }
    });
  });

  router.register("POST", "/api/auth/login", async ({ req, res }) => {
    const payload = parseLoginRequest(await readJsonBody(req));
    const user = db.getUserByEmail(payload.email);

    if (!user || !verifyPassword(payload.password, user.passwordHash)) {
      writeJson(res, 401, { error: "invalid_credentials" });
      return;
    }

    const session = db.createSession(user.id, config.sessionTtlHours);
    writeJson(res, 200, {
      token: session.token,
      userId: session.userId,
      expiresAt: session.expiresAt,
      user: {
        id: user.id,
        email: user.email,
        displayName: user.displayName
      }
    });
  });

  router.register("GET", "/api/auth/me", ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    writeJson(res, 200, {
      id: auth.user.id,
      email: auth.user.email,
      displayName: auth.user.displayName
    });
  });

  router.register("POST", "/api/auth/me", async ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const payload = parseUpdateProfileRequest(await readJsonBody(req));
    try {
      const updated = db.updateUserDisplayName(auth.user.id, payload.displayName);
      writeJson(res, 200, {
        id: updated.id,
        email: updated.email,
        displayName: updated.displayName
      });
    } catch (error) {
      writeJson(res, 400, {
        error: "failed_to_update_profile",
        message: error instanceof Error ? error.message : "unknown error"
      });
    }
  });

  router.register("POST", "/api/contacts/invite", async ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const payload = parseInviteContactRequest(await readJsonBody(req));
    if (payload.inviteeEmail === auth.user.email) {
      writeJson(res, 400, { error: "cannot_invite_self" });
      return;
    }

    const invitation = db.createContactInvitation(auth.user.id, payload.inviteeEmail);
    if (invitation.inviteeUserId) {
      db.createNotification({
        userId: invitation.inviteeUserId,
        artworkId: null,
        type: "invite_received",
        payloadJson: JSON.stringify({ invitationId: invitation.id, inviterUserId: auth.user.id }),
        channel: "in_app"
      });
    }

    writeJson(res, 201, invitation);
  });

  router.register("GET", "/api/contacts/invitations", ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const invitations = db.listPendingInvitationsForUser(auth.user.id, auth.user.email);
    const payload = invitations.map((invitation) => {
      const inviter = db.getUserById(invitation.inviterUserId);
      return {
        ...invitation,
        inviterDisplayName: inviter?.displayName ?? "Unknown",
        inviterEmail: inviter?.email ?? null
      };
    });

    writeJson(res, 200, payload);
  });

  router.register("POST", "/api/contacts/invitations/:invitationId/accept", ({ req, res, params }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const invitationId = params.invitationId;
    if (!invitationId) {
      writeJson(res, 400, { error: "invitation_id_required" });
      return;
    }

    try {
      const relation = db.acceptInvitation(invitationId, auth.user.id);
      writeJson(res, 200, relation);
    } catch (error) {
      writeJson(res, 400, {
        error: "failed_to_accept_invite",
        message: error instanceof Error ? error.message : "unknown error"
      });
    }
  });

  router.register("POST", "/api/contacts/invitations/:invitationId/decline", ({ req, res, params }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const invitationId = params.invitationId;
    if (!invitationId) {
      writeJson(res, 400, { error: "invitation_id_required" });
      return;
    }

    try {
      const invitation = db.declineInvitation(invitationId, auth.user.id);
      writeJson(res, 200, invitation);
    } catch (error) {
      writeJson(res, 400, {
        error: "failed_to_decline_invite",
        message: error instanceof Error ? error.message : "unknown error"
      });
    }
  });

  router.register("GET", "/api/contacts", ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    writeJson(res, 200, db.listContacts(auth.user.id));
  });

  router.register("GET", "/api/chats/:contactUserId", ({ req, res, params }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const contactUserId = params.contactUserId;
    if (!contactUserId) {
      writeJson(res, 400, { error: "contact_user_id_required" });
      return;
    }

    if (!db.isContactPair(auth.user.id, contactUserId)) {
      writeJson(res, 403, { error: "contact_required_for_chat" });
      return;
    }

    const contact = db.getUserById(contactUserId);
    if (!contact) {
      writeJson(res, 404, { error: "contact_not_found" });
      return;
    }

    db.markDirectMessagesRead(auth.user.id, contactUserId);

    const artworks = db.listSharedArtworksForUsers(auth.user.id, contactUserId);
    const messages = db.listDirectMessages(auth.user.id, contactUserId);
    const artworkCreatedEvents = db.listSharedArtworkCreationEvents(auth.user.id, contactUserId);
    const turnStartedEvents = db.listSharedTurnStartedEvents(auth.user.id, contactUserId);

    const timeline = [
      ...messages.map((message) => ({
        id: `message:${message.id}`,
        kind: "message",
        createdAt: message.createdAt,
        senderUserId: message.senderUserId,
        recipientUserId: message.recipientUserId,
        body: message.body
      })),
      ...artworkCreatedEvents.map((event) => ({
        id: `event:artwork_created:${event.id}`,
        kind: "event",
        eventType: "artwork_created",
        createdAt: event.createdAt,
        artworkId: event.artworkId,
        artworkTitle: event.artworkTitle,
        actorUserId: event.actorUserId
      })),
      ...turnStartedEvents.map((event) => ({
        id: `event:turn_started:${event.id}`,
        kind: "event",
        eventType: "turn_started",
        createdAt: event.createdAt,
        artworkId: event.artworkId,
        artworkTitle: event.artworkTitle,
        targetUserId: event.targetUserId
      }))
    ].sort((left, right) => {
      if (left.createdAt === right.createdAt) {
        return left.id.localeCompare(right.id);
      }
      return left.createdAt.localeCompare(right.createdAt);
    });

    writeJson(res, 200, {
      contact: {
        userId: contact.id,
        displayName: contact.displayName,
        email: contact.email,
        unreadMessageCount: 0
      },
      artworks,
      timeline
    });
  });

  router.register("POST", "/api/chats/:contactUserId/messages", async ({ req, res, params }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const contactUserId = params.contactUserId;
    if (!contactUserId) {
      writeJson(res, 400, { error: "contact_user_id_required" });
      return;
    }

    const payload = parseSendChatMessageRequest(await readJsonBody(req));

    try {
      const message = db.createDirectMessage(auth.user.id, contactUserId, payload.body);
      writeJson(res, 201, message);
    } catch (error) {
      writeJson(res, 400, {
        error: "failed_to_send_chat_message",
        message: error instanceof Error ? error.message : "unknown error"
      });
    }
  });

  router.register("POST", "/api/media/upload", async ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const contentTypeHeader = req.headers["content-type"];
    const rawContentType = Array.isArray(contentTypeHeader) ? contentTypeHeader[0] : contentTypeHeader;
    const contentType = rawContentType?.split(";")[0]?.trim().toLowerCase() ?? "";
    if (!contentType.startsWith("image/")) {
      writeJson(res, 400, { error: "content_type_must_be_image" });
      return;
    }

    const fileNameHeader = req.headers["x-file-name"];
    const originalFilename =
      (Array.isArray(fileNameHeader) ? fileNameHeader[0] : fileNameHeader)?.trim() || "upload.jpg";

    let payload: Buffer;
    try {
      payload = await readBinaryBody(req, config.maxMediaUploadBytes);
    } catch (error) {
      writeJson(res, 413, {
        error: "payload_too_large",
        message: error instanceof Error ? error.message : "payload too large"
      });
      return;
    }

    if (payload.length === 0) {
      writeJson(res, 400, { error: "empty_payload" });
      return;
    }

    try {
      const storedObject = await storageAdapter.putMediaObject({
        ownerUserId: auth.user.id,
        originalFilename,
        mimeType: contentType,
        bytes: payload
      });

      const asset = db.createMediaAsset({
        ownerUserId: auth.user.id,
        storageDriver: config.storageDriver,
        storageKey: storedObject.storageKey,
        mimeType: storedObject.mimeType,
        originalFilename: storedObject.originalFilename,
        byteSize: storedObject.byteSize
      });

      writeJson(res, 201, {
        id: asset.id,
        contentPath: `/api/media/${asset.id}/content`,
        mimeType: asset.mimeType,
        originalFilename: asset.originalFilename,
        byteSize: asset.byteSize
      });
    } catch (error) {
      writeJson(res, 500, {
        error: "media_upload_failed",
        message: error instanceof Error ? error.message : "media upload failed"
      });
    }
  });

  router.register("GET", "/api/media/:mediaId/content", async ({ req, res, params }) => {
    const auth = requireAuth(req, res, db, { allowQueryToken: true });
    if (!auth) {
      return;
    }

    const mediaId = params.mediaId;
    if (!mediaId) {
      writeJson(res, 400, { error: "media_id_required" });
      return;
    }

    const asset = db.getMediaAssetById(mediaId);
    if (!asset) {
      writeJson(res, 404, { error: "media_not_found" });
      return;
    }

    try {
      const mediaObject = await storageAdapter.getMediaObject(asset.storageKey);
      writeBinary(res, 200, mediaObject.bytes, asset.mimeType);
    } catch (error) {
      writeJson(res, 500, {
        error: "media_read_failed",
        message: error instanceof Error ? error.message : "media read failed"
      });
    }
  });

  router.register("POST", "/api/artworks", async ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const payload = parseCreateArtworkRequest(await readJsonBody(req));
    const participantSet = new Set(payload.participantUserIds);
    participantSet.add(auth.user.id);
    const participantUserIds = [...participantSet];
    const firstTurnUserId = payload.firstTurnUserId ?? auth.user.id;

    for (const participantId of participantUserIds) {
      const participant = db.getUserById(participantId);
      if (!participant) {
        writeJson(res, 400, { error: `participant_not_found:${participantId}` });
        return;
      }

      if (!db.isContactPair(auth.user.id, participantId)) {
        writeJson(res, 400, { error: `participant_not_a_contact:${participantId}` });
        return;
      }
    }

    const orderedParticipantUserIds =
      payload.mode !== "turn_based"
        ? participantUserIds
        : (() => {
            if (!participantSet.has(firstTurnUserId)) {
              writeJson(res, 400, { error: `invalid_first_turn_user:${firstTurnUserId}` });
              return null;
            }

            return [
              firstTurnUserId,
              ...participantUserIds.filter((userId) => userId !== firstTurnUserId)
            ];
          })();

    if (orderedParticipantUserIds == null) {
      return;
    }

    try {
      const details = db.createArtwork({
        title: payload.title,
        mode: payload.mode,
        width: payload.width,
        height: payload.height,
        basePhotoPath: payload.basePhotoPath ?? null,
        createdByUserId: auth.user.id,
        participantUserIds: orderedParticipantUserIds,
        turnDurationMinutes: payload.turnDurationMinutes ?? null
      });

      if (details.currentTurn) {
        if (config.snapshotEveryTurns > 0 && details.currentTurn.turnNumber % config.snapshotEveryTurns === 0) {
          db.createSnapshot(details.artwork.id, "periodic", JSON.stringify({}));
        }

        db.createNotification({
          userId: details.currentTurn.activeParticipantUserId,
          artworkId: details.artwork.id,
          type: "turn_started",
          payloadJson: JSON.stringify({
            artworkId: details.artwork.id,
            turnNumber: details.currentTurn.turnNumber
          }),
          channel: "in_app"
        });

        collaborationHub.broadcastTurnAdvanced(
          details.artwork.id,
          details.currentTurn.activeParticipantUserId,
          details.currentTurn.turnNumber,
          details.currentTurn.dueAt
        );
      }

      writeJson(res, 201, details);
    } catch (error) {
      writeJson(res, 400, {
        error: "failed_to_create_artwork",
        message: error instanceof Error ? error.message : "unknown error"
      });
    }
  });

  router.register("GET", "/api/artworks", ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    writeJson(res, 200, db.listArtworksForUser(auth.user.id));
  });

  router.register("GET", "/api/artworks/:artworkId", ({ req, res, params }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const artworkId = params.artworkId;
    if (!artworkId) {
      writeJson(res, 400, { error: "artwork_id_required" });
      return;
    }

    const details = db.getArtworkDetailsForUser(artworkId, auth.user.id);
    if (!details) {
      writeJson(res, 404, { error: "artwork_not_found" });
      return;
    }

    writeJson(res, 200, details);
  });

  router.register("POST", "/api/artworks/:artworkId/title", async ({ req, res, params }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const artworkId = params.artworkId;
    if (!artworkId) {
      writeJson(res, 400, { error: "artwork_id_required" });
      return;
    }

    const payload = parseUpdateArtworkTitleRequest(await readJsonBody(req));

    try {
      db.updateArtworkTitle(artworkId, auth.user.id, payload.title);
      const refreshed = db.getArtworkDetailsForUser(artworkId, auth.user.id);
      if (!refreshed) {
        writeJson(res, 404, { error: "artwork_not_found" });
        return;
      }
      writeJson(res, 200, refreshed);
    } catch (error) {
      writeJson(res, 400, {
        error: "failed_to_update_artwork_title",
        message: error instanceof Error ? error.message : "unknown error"
      });
    }
  });

  router.register("POST", "/api/artworks/:artworkId/layers", async ({ req, res, params }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const artworkId = params.artworkId;
    if (!artworkId) {
      writeJson(res, 400, { error: "artwork_id_required" });
      return;
    }

    const body = await readJsonBody(req);
    let layerName: string | undefined;
    if (body != null) {
      if (typeof body !== "object" || Array.isArray(body)) {
        writeJson(res, 400, { error: "invalid_payload" });
        return;
      }

      const candidate = (body as Record<string, unknown>).name;
      if (candidate != null) {
        if (typeof candidate !== "string") {
          writeJson(res, 400, { error: "name_must_be_string" });
          return;
        }
        layerName = candidate;
      }
    }

    try {
      const layer = db.createLayer(artworkId, auth.user.id, layerName);
      writeJson(res, 201, layer);
    } catch (error) {
      writeJson(res, 400, {
        error: "create_layer_failed",
        message: error instanceof Error ? error.message : "unknown error"
      });
    }
  });

  router.register("POST", "/api/turns/submit", async ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const payload = parseSubmitTurnRequest(await readJsonBody(req));

    try {
      const nextTurn = db.submitTurn(payload.artworkId, auth.user.id);
      db.createSnapshot(payload.artworkId, "turn_submitted", JSON.stringify({}));
      if (config.snapshotEveryTurns > 0 && nextTurn.turnNumber % config.snapshotEveryTurns === 0) {
        db.createSnapshot(payload.artworkId, "periodic", JSON.stringify({}));
      }
      db.createNotification({
        userId: nextTurn.activeParticipantUserId,
        artworkId: payload.artworkId,
        type: "turn_started",
        payloadJson: JSON.stringify({ artworkId: payload.artworkId, turnNumber: nextTurn.turnNumber }),
        channel: "native_push"
      });
      collaborationHub.broadcastTurnAdvanced(
        payload.artworkId,
        nextTurn.activeParticipantUserId,
        nextTurn.turnNumber,
        nextTurn.dueAt
      );

      writeJson(res, 200, nextTurn);
    } catch (error) {
      writeJson(res, 400, {
        error: "turn_submit_failed",
        message: error instanceof Error ? error.message : "unknown error"
      });
    }
  });

  const httpServer = createServer(async (req, res) => {
    try {
      applyCors(res);
      if (req.method === "OPTIONS") {
        res.statusCode = 204;
        res.end();
        return;
      }

      const handled = await router.dispatch(req, res);
      if (!handled) {
        writeJson(res, 404, { error: "not_found" });
      }
    } catch (error) {
      writeJson(res, 500, {
        error: "internal_error",
        message: error instanceof Error ? error.message : "unexpected error"
      });
    }
  });

  httpServer.on("connection", (socket) => {
    activeSockets.add(socket);
    socket.on("close", () => {
      activeSockets.delete(socket);
    });
  });

  httpServer.on("upgrade", (req, socket, head) => {
    const requestPath = (req.url ?? "").split("?")[0];
    if (requestPath !== "/ws") {
      socket.destroy();
      return;
    }

    collaborationHub.handleUpgrade(req, socket, head);
  });

  return {
    db,
    start: async () => {
      await new Promise<void>((resolve) => {
        httpServer.listen(config.port, config.host, () => {
          console.log(`BrushLoop server listening on http://${config.host}:${config.port}`);
          resolve();
        });
      });
      notificationDispatcher.start();
      turnExpiryWorker.start();
    },
    stop: async () => {
      notificationDispatcher.stop();
      turnExpiryWorker.stop();
      for (const socket of activeSockets) {
        socket.destroy();
      }
      activeSockets.clear();
      await new Promise<void>((resolve, reject) => {
        httpServer.close((error) => {
          if (error) {
            reject(error);
            return;
          }

          resolve();
        });
      });
      db.close();
    }
  };
}

function requireAuth(
  req: IncomingMessage,
  res: ServerResponse,
  db: BrushloopDatabase,
  options?: { allowQueryToken?: boolean }
): {
  user: {
    id: string;
    email: string;
    displayName: string;
  };
} | null {
  const token = readAuthToken(req, Boolean(options?.allowQueryToken));
  if (!token) {
    writeJson(res, 401, { error: "missing_or_invalid_authorization_header" });
    return null;
  }

  const session = db.getSession(token);
  if (!session) {
    writeJson(res, 401, { error: "invalid_or_expired_session" });
    return null;
  }

  const user = db.getUserById(session.userId);
  if (!user) {
    writeJson(res, 401, { error: "session_user_missing" });
    return null;
  }

  return {
    user: {
      id: user.id,
      email: user.email,
      displayName: user.displayName
    }
  };
}

function readAuthToken(req: IncomingMessage, allowQueryToken: boolean): string | null {
  const header = req.headers.authorization;
  if (header && header.startsWith("Bearer ")) {
    const token = header.slice("Bearer ".length).trim();
    if (token.length > 0) {
      return token;
    }
  }

  if (!allowQueryToken) {
    return null;
  }

  const base = `http://${req.headers.host ?? "localhost"}`;
  const url = new URL(req.url ?? "/", base);
  const token = url.searchParams.get("token")?.trim();
  return token && token.length > 0 ? token : null;
}
