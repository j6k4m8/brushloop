import { createServer, type IncomingMessage, type ServerResponse } from "node:http";

import {
  parseCreateArtworkRequest,
  parseInviteContactRequest,
  parseLoginRequest,
  parseRegisterRequest,
  parseSubmitTurnRequest
} from "../../packages/shared/src/index.ts";
import { hashPassword, verifyPassword } from "./auth/password.ts";
import { CollaborationHub } from "./collab/hub.ts";
import { loadConfig } from "./config.ts";
import { BrushloopDatabase } from "./db/database.ts";
import { Router } from "./http/router.ts";
import { applyCors, readJsonBody, writeJson } from "./http/utils.ts";

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
  const collaborationHub = new CollaborationHub(db);
  const router = new Router();

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

    writeJson(res, 200, db.listPendingInvitationsForUser(auth.user.id, auth.user.email));
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

  router.register("GET", "/api/contacts", ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    writeJson(res, 200, db.listContacts(auth.user.id));
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

    if (participantUserIds.length < 2) {
      writeJson(res, 400, { error: "an_artwork_requires_at_least_two_participants" });
      return;
    }

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

    try {
      const details = db.createArtwork({
        title: payload.title,
        mode: payload.mode,
        width: payload.width,
        height: payload.height,
        basePhotoPath: payload.basePhotoPath ?? null,
        createdByUserId: auth.user.id,
        participantUserIds,
        turnDurationMinutes: payload.turnDurationMinutes ?? null
      });

      if (details.currentTurn) {
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

  router.register("POST", "/api/turns/submit", async ({ req, res }) => {
    const auth = requireAuth(req, res, db);
    if (!auth) {
      return;
    }

    const payload = parseSubmitTurnRequest(await readJsonBody(req));

    try {
      const nextTurn = db.submitTurn(payload.artworkId, auth.user.id);
      db.createSnapshot(payload.artworkId, "turn_submitted", JSON.stringify({}));
      db.createNotification({
        userId: nextTurn.activeParticipantUserId,
        artworkId: payload.artworkId,
        type: "turn_started",
        payloadJson: JSON.stringify({ artworkId: payload.artworkId, turnNumber: nextTurn.turnNumber }),
        channel: "in_app"
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
    },
    stop: async () => {
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

function requireAuth(req: IncomingMessage, res: ServerResponse, db: BrushloopDatabase): {
  user: {
    id: string;
    email: string;
    displayName: string;
  };
} | null {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) {
    writeJson(res, 401, { error: "missing_or_invalid_authorization_header" });
    return null;
  }

  const token = header.slice("Bearer ".length).trim();
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
