import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { DatabaseSync } from "node:sqlite";

import type {
  Artwork,
  ArtworkParticipant,
  CollaborationMode,
  ContactInvitation,
  ContactRelation,
  CrdtOperation,
  Id,
  Layer,
  NotificationRecord,
  TurnState,
  UserRecord,
  UserSession
} from "../../../packages/shared/src/index.ts";
import { SCHEMA_SQL } from "./schema.ts";

export interface CreateArtworkInput {
  title: string;
  mode: CollaborationMode;
  width: number;
  height: number;
  basePhotoPath: string | null;
  createdByUserId: Id;
  participantUserIds: Id[];
  turnDurationMinutes: number | null;
}

export interface ArtworkListItemRow {
  id: Id;
  title: string;
  mode: CollaborationMode;
  participantUserIds: Id[];
  activeParticipantUserId: Id | null;
}

export interface ArtworkDetails {
  artwork: Artwork;
  participants: ArtworkParticipant[];
  layers: Layer[];
  currentTurn: TurnState | null;
}

/**
 * SQLite persistence gateway for core BrushLoop entities.
 */
export class BrushloopDatabase {
  private readonly db: DatabaseSync;

  constructor(dbPath: string) {
    const parentDir = path.dirname(dbPath);
    fs.mkdirSync(parentDir, { recursive: true });

    this.db = new DatabaseSync(dbPath);
    this.db.exec(SCHEMA_SQL);
  }

  close(): void {
    this.db.close();
  }

  createUser(email: string, displayName: string, passwordHash: string): UserRecord {
    const id = randomUUID();
    const createdAt = nowIso();

    this.db
      .prepare(
        `INSERT INTO users (id, email, display_name, password_hash, created_at)
         VALUES (?, ?, ?, ?, ?)`
      )
      .run(id, email, displayName, passwordHash, createdAt);

    return {
      id,
      email,
      displayName,
      passwordHash,
      createdAt
    };
  }

  getUserById(userId: Id): UserRecord | null {
    const row = this.db
      .prepare(
        `SELECT id, email, display_name, password_hash, created_at
         FROM users
         WHERE id = ?`
      )
      .get(userId) as
      | {
          id: string;
          email: string;
          display_name: string;
          password_hash: string;
          created_at: string;
        }
      | undefined;

    return row ? mapUserRow(row) : null;
  }

  getUserByEmail(email: string): UserRecord | null {
    const row = this.db
      .prepare(
        `SELECT id, email, display_name, password_hash, created_at
         FROM users
         WHERE email = ?`
      )
      .get(email) as
      | {
          id: string;
          email: string;
          display_name: string;
          password_hash: string;
          created_at: string;
        }
      | undefined;

    return row ? mapUserRow(row) : null;
  }

  createSession(userId: Id, ttlHours: number): UserSession {
    const token = randomUUID().replace(/-/g, "") + randomUUID().replace(/-/g, "");
    const createdAt = nowIso();
    const expiresAt = new Date(Date.now() + ttlHours * 60 * 60 * 1000).toISOString();

    this.db
      .prepare(
        `INSERT INTO sessions (token, user_id, expires_at, created_at)
         VALUES (?, ?, ?, ?)`
      )
      .run(token, userId, expiresAt, createdAt);

    return {
      token,
      userId,
      expiresAt,
      createdAt
    };
  }

  getSession(token: string): UserSession | null {
    const row = this.db
      .prepare(
        `SELECT token, user_id, expires_at, created_at
         FROM sessions
         WHERE token = ?`
      )
      .get(token) as
      | {
          token: string;
          user_id: string;
          expires_at: string;
          created_at: string;
        }
      | undefined;

    if (!row) {
      return null;
    }

    if (Date.parse(row.expires_at) <= Date.now()) {
      this.db.prepare("DELETE FROM sessions WHERE token = ?").run(token);
      return null;
    }

    return {
      token: row.token,
      userId: row.user_id,
      expiresAt: row.expires_at,
      createdAt: row.created_at
    };
  }

  createContactInvitation(inviterUserId: Id, inviteeEmail: string): ContactInvitation {
    const inviteeUser = this.getUserByEmail(inviteeEmail);
    const id = randomUUID();
    const createdAt = nowIso();

    this.db
      .prepare(
        `INSERT INTO contact_invitations (
          id, inviter_user_id, invitee_email, invitee_user_id, status, created_at, responded_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)`
      )
      .run(id, inviterUserId, inviteeEmail, inviteeUser?.id ?? null, "pending", createdAt, null);

    return {
      id,
      inviterUserId,
      inviteeEmail,
      inviteeUserId: inviteeUser?.id ?? null,
      status: "pending",
      createdAt,
      respondedAt: null
    };
  }

  listPendingInvitationsForUser(userId: Id, email: string): ContactInvitation[] {
    const rows = this.db
      .prepare(
        `SELECT id, inviter_user_id, invitee_email, invitee_user_id, status, created_at, responded_at
         FROM contact_invitations
         WHERE status = 'pending' AND (invitee_user_id = ? OR invitee_email = ?)
         ORDER BY created_at DESC`
      )
      .all(userId, email) as Array<{
      id: string;
      inviter_user_id: string;
      invitee_email: string;
      invitee_user_id: string | null;
      status: string;
      created_at: string;
      responded_at: string | null;
    }>;

    return rows.map((row) => ({
      id: row.id,
      inviterUserId: row.inviter_user_id,
      inviteeEmail: row.invitee_email,
      inviteeUserId: row.invitee_user_id,
      status: row.status as ContactInvitation["status"],
      createdAt: row.created_at,
      respondedAt: row.responded_at
    }));
  }

  acceptInvitation(invitationId: Id, accepterUserId: Id): ContactRelation {
    const invitation = this.db
      .prepare(
        `SELECT id, inviter_user_id, invitee_email, invitee_user_id, status
         FROM contact_invitations
         WHERE id = ?`
      )
      .get(invitationId) as
      | {
          id: string;
          inviter_user_id: string;
          invitee_email: string;
          invitee_user_id: string | null;
          status: string;
        }
      | undefined;

    if (!invitation) {
      throw new Error("invitation not found");
    }

    if (invitation.status !== "pending") {
      throw new Error("invitation is not pending");
    }

    const accepter = this.getUserById(accepterUserId);
    if (!accepter) {
      throw new Error("accepter user not found");
    }

    if (
      invitation.invitee_user_id &&
      invitation.invitee_user_id !== accepterUserId
    ) {
      throw new Error("invitation is not assigned to this user");
    }

    if (!invitation.invitee_user_id && invitation.invitee_email !== accepter.email) {
      throw new Error("invitation email does not match accepter");
    }

    const sorted = [invitation.inviter_user_id, accepterUserId].sort();
    const existing = this.db
      .prepare(
        `SELECT id, user_a_id, user_b_id, created_at
         FROM contacts
         WHERE user_a_id = ? AND user_b_id = ?`
      )
      .get(sorted[0], sorted[1]) as
      | {
          id: string;
          user_a_id: string;
          user_b_id: string;
          created_at: string;
        }
      | undefined;

    this.db
      .prepare(
        `UPDATE contact_invitations
         SET status = 'accepted', invitee_user_id = ?, responded_at = ?
         WHERE id = ?`
      )
      .run(accepterUserId, nowIso(), invitationId);

    if (existing) {
      return {
        id: existing.id,
        userAId: existing.user_a_id,
        userBId: existing.user_b_id,
        createdAt: existing.created_at
      };
    }

    const id = randomUUID();
    const createdAt = nowIso();
    this.db
      .prepare(
        `INSERT INTO contacts (id, user_a_id, user_b_id, created_at)
         VALUES (?, ?, ?, ?)`
      )
      .run(id, sorted[0], sorted[1], createdAt);

    return {
      id,
      userAId: sorted[0],
      userBId: sorted[1],
      createdAt
    };
  }

  listContacts(userId: Id): Array<{ userId: Id; displayName: string; email: string }> {
    const rows = this.db
      .prepare(
        `SELECT
           CASE WHEN c.user_a_id = ? THEN c.user_b_id ELSE c.user_a_id END AS contact_user_id,
           u.display_name,
           u.email
         FROM contacts c
         INNER JOIN users u
           ON u.id = CASE WHEN c.user_a_id = ? THEN c.user_b_id ELSE c.user_a_id END
         WHERE c.user_a_id = ? OR c.user_b_id = ?
         ORDER BY u.display_name ASC`
      )
      .all(userId, userId, userId, userId) as Array<{
      contact_user_id: string;
      display_name: string;
      email: string;
    }>;

    return rows.map((row) => ({
      userId: row.contact_user_id,
      displayName: row.display_name,
      email: row.email
    }));
  }

  isContactPair(userAId: Id, userBId: Id): boolean {
    if (userAId === userBId) {
      return true;
    }

    const sorted = [userAId, userBId].sort();
    const row = this.db
      .prepare(
        `SELECT id
         FROM contacts
         WHERE user_a_id = ? AND user_b_id = ?`
      )
      .get(sorted[0], sorted[1]) as { id: string } | undefined;

    return Boolean(row);
  }

  createArtwork(input: CreateArtworkInput): ArtworkDetails {
    const artworkId = randomUUID();
    const createdAt = nowIso();

    const createArtworkStmt = this.db.prepare(
      `INSERT INTO artworks (
         id, title, width, height, base_photo_path, created_by_user_id, created_at, updated_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    );

    const createModeStmt = this.db.prepare(
      `INSERT INTO artwork_modes (artwork_id, mode, turn_duration_minutes)
       VALUES (?, ?, ?)`
    );

    const createParticipantStmt = this.db.prepare(
      `INSERT INTO artwork_participants (id, artwork_id, user_id, turn_index, joined_at)
       VALUES (?, ?, ?, ?, ?)`
    );

    const createLayerStmt = this.db.prepare(
      `INSERT INTO layers (
         id, artwork_id, name, sort_order, is_visible, is_locked, created_by_user_id, created_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    );

    this.db.exec("BEGIN");
    try {
      createArtworkStmt.run(
        artworkId,
        input.title,
        input.width,
        input.height,
        input.basePhotoPath,
        input.createdByUserId,
        createdAt,
        createdAt
      );
      createModeStmt.run(artworkId, input.mode, input.turnDurationMinutes);

      const participants: ArtworkParticipant[] = [];
      for (let index = 0; index < input.participantUserIds.length; index += 1) {
        const userId = input.participantUserIds[index];
        const id = randomUUID();
        createParticipantStmt.run(id, artworkId, userId, index, createdAt);
        participants.push({
          id,
          artworkId,
          userId,
          turnIndex: index,
          joinedAt: createdAt
        });
      }

      const layers: Layer[] = [];
      if (input.basePhotoPath) {
        const baseLayerId = randomUUID();
        createLayerStmt.run(baseLayerId, artworkId, "Base Photo", 0, 1, 1, input.createdByUserId, createdAt);
        layers.push({
          id: baseLayerId,
          artworkId,
          name: "Base Photo",
          sortOrder: 0,
          isVisible: true,
          isLocked: true,
          createdByUserId: input.createdByUserId,
          createdAt
        });
      }

      const drawLayerId = randomUUID();
      createLayerStmt.run(drawLayerId, artworkId, "Layer 1", layers.length, 1, 0, input.createdByUserId, createdAt);
      layers.push({
        id: drawLayerId,
        artworkId,
        name: "Layer 1",
        sortOrder: layers.length,
        isVisible: true,
        isLocked: false,
        createdByUserId: input.createdByUserId,
        createdAt
      });

      let currentTurn: TurnState | null = null;
      if (input.mode === "turn_based") {
        const firstParticipantId = participants[0]?.userId;
        if (!firstParticipantId) {
          throw new Error("turn-based artwork requires participants");
        }

        const dueAt =
          input.turnDurationMinutes == null
            ? null
            : new Date(Date.now() + input.turnDurationMinutes * 60 * 1000).toISOString();

        const turnId = randomUUID();
        this.db
          .prepare(
            `INSERT INTO turns (
               id, artwork_id, turn_number, round_number, active_participant_user_id, started_at, due_at, completed_at, completion_reason
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
          )
          .run(turnId, artworkId, 1, 1, firstParticipantId, createdAt, dueAt, null, null);

        currentTurn = {
          id: turnId,
          artworkId,
          activeParticipantUserId: firstParticipantId,
          roundNumber: 1,
          turnNumber: 1,
          startedAt: createdAt,
          dueAt,
          completedAt: null
        };
      }

      this.db.exec("COMMIT");

      return {
        artwork: {
          id: artworkId,
          title: input.title,
          mode: input.mode,
          width: input.width,
          height: input.height,
          basePhotoPath: input.basePhotoPath,
          createdByUserId: input.createdByUserId,
          createdAt,
          updatedAt: createdAt
        },
        participants,
        layers,
        currentTurn
      };
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  getArtworkMode(artworkId: Id): { mode: CollaborationMode; turnDurationMinutes: number | null } | null {
    const row = this.db
      .prepare(
        `SELECT mode, turn_duration_minutes
         FROM artwork_modes
         WHERE artwork_id = ?`
      )
      .get(artworkId) as
      | {
          mode: CollaborationMode;
          turn_duration_minutes: number | null;
        }
      | undefined;

    if (!row) {
      return null;
    }

    return {
      mode: row.mode,
      turnDurationMinutes: row.turn_duration_minutes
    };
  }

  listArtworksForUser(userId: Id): ArtworkListItemRow[] {
    const rows = this.db
      .prepare(
        `SELECT a.id, a.title, am.mode
         FROM artworks a
         INNER JOIN artwork_modes am ON am.artwork_id = a.id
         INNER JOIN artwork_participants ap ON ap.artwork_id = a.id
         WHERE ap.user_id = ?
         ORDER BY a.updated_at DESC`
      )
      .all(userId) as Array<{
      id: string;
      title: string;
      mode: CollaborationMode;
    }>;

    return rows.map((row) => {
      const participantRows = this.db
        .prepare(
          `SELECT user_id
           FROM artwork_participants
           WHERE artwork_id = ?
           ORDER BY turn_index ASC`
        )
        .all(row.id) as Array<{ user_id: string }>;

      const turnRow = this.db
        .prepare(
          `SELECT active_participant_user_id
           FROM turns
           WHERE artwork_id = ? AND completed_at IS NULL
           ORDER BY turn_number DESC
           LIMIT 1`
        )
        .get(row.id) as { active_participant_user_id: string } | undefined;

      return {
        id: row.id,
        title: row.title,
        mode: row.mode,
        participantUserIds: participantRows.map((item) => item.user_id),
        activeParticipantUserId: turnRow?.active_participant_user_id ?? null
      };
    });
  }

  getArtworkDetailsForUser(artworkId: Id, userId: Id): ArtworkDetails | null {
    const member = this.db
      .prepare(
        `SELECT id
         FROM artwork_participants
         WHERE artwork_id = ? AND user_id = ?`
      )
      .get(artworkId, userId) as { id: string } | undefined;

    if (!member) {
      return null;
    }

    const artworkRow = this.db
      .prepare(
        `SELECT a.id, a.title, a.width, a.height, a.base_photo_path, a.created_by_user_id, a.created_at, a.updated_at, am.mode
         FROM artworks a
         INNER JOIN artwork_modes am ON am.artwork_id = a.id
         WHERE a.id = ?`
      )
      .get(artworkId) as
      | {
          id: string;
          title: string;
          width: number;
          height: number;
          base_photo_path: string | null;
          created_by_user_id: string;
          created_at: string;
          updated_at: string;
          mode: CollaborationMode;
        }
      | undefined;

    if (!artworkRow) {
      return null;
    }

    const participants = this.db
      .prepare(
        `SELECT id, artwork_id, user_id, turn_index, joined_at
         FROM artwork_participants
         WHERE artwork_id = ?
         ORDER BY turn_index ASC`
      )
      .all(artworkId) as Array<{
      id: string;
      artwork_id: string;
      user_id: string;
      turn_index: number;
      joined_at: string;
    }>;

    const layers = this.db
      .prepare(
        `SELECT id, artwork_id, name, sort_order, is_visible, is_locked, created_by_user_id, created_at
         FROM layers
         WHERE artwork_id = ?
         ORDER BY sort_order ASC`
      )
      .all(artworkId) as Array<{
      id: string;
      artwork_id: string;
      name: string;
      sort_order: number;
      is_visible: number;
      is_locked: number;
      created_by_user_id: string;
      created_at: string;
    }>;

    const turnRow = this.db
      .prepare(
        `SELECT id, artwork_id, active_participant_user_id, round_number, turn_number, started_at, due_at, completed_at
         FROM turns
         WHERE artwork_id = ? AND completed_at IS NULL
         ORDER BY turn_number DESC
         LIMIT 1`
      )
      .get(artworkId) as
      | {
          id: string;
          artwork_id: string;
          active_participant_user_id: string;
          round_number: number;
          turn_number: number;
          started_at: string;
          due_at: string | null;
          completed_at: string | null;
        }
      | undefined;

    return {
      artwork: {
        id: artworkRow.id,
        title: artworkRow.title,
        mode: artworkRow.mode,
        width: artworkRow.width,
        height: artworkRow.height,
        basePhotoPath: artworkRow.base_photo_path,
        createdByUserId: artworkRow.created_by_user_id,
        createdAt: artworkRow.created_at,
        updatedAt: artworkRow.updated_at
      },
      participants: participants.map((item) => ({
        id: item.id,
        artworkId: item.artwork_id,
        userId: item.user_id,
        turnIndex: item.turn_index,
        joinedAt: item.joined_at
      })),
      layers: layers.map((item) => ({
        id: item.id,
        artworkId: item.artwork_id,
        name: item.name,
        sortOrder: item.sort_order,
        isVisible: item.is_visible === 1,
        isLocked: item.is_locked === 1,
        createdByUserId: item.created_by_user_id,
        createdAt: item.created_at
      })),
      currentTurn: turnRow
        ? {
            id: turnRow.id,
            artworkId: turnRow.artwork_id,
            activeParticipantUserId: turnRow.active_participant_user_id,
            roundNumber: turnRow.round_number,
            turnNumber: turnRow.turn_number,
            startedAt: turnRow.started_at,
            dueAt: turnRow.due_at,
            completedAt: turnRow.completed_at
          }
        : null
    };
  }

  submitTurn(
    artworkId: Id,
    actorUserId: Id,
    completionReason: "submitted" | "expired" = "submitted"
  ): TurnState {
    const mode = this.getArtworkMode(artworkId);
    if (!mode || mode.mode !== "turn_based") {
      throw new Error("artwork is not turn-based");
    }

    const currentTurn = this.db
      .prepare(
        `SELECT id, turn_number, round_number, active_participant_user_id
         FROM turns
         WHERE artwork_id = ? AND completed_at IS NULL
         ORDER BY turn_number DESC
         LIMIT 1`
      )
      .get(artworkId) as
      | {
          id: string;
          turn_number: number;
          round_number: number;
          active_participant_user_id: string;
        }
      | undefined;

    if (!currentTurn) {
      throw new Error("no active turn");
    }

    if (currentTurn.active_participant_user_id !== actorUserId) {
      throw new Error("only the active participant can submit a turn");
    }

    const participants = this.db
      .prepare(
        `SELECT user_id, turn_index
         FROM artwork_participants
         WHERE artwork_id = ?
         ORDER BY turn_index ASC`
      )
      .all(artworkId) as Array<{ user_id: string; turn_index: number }>;

    const currentIndex = participants.findIndex((item) => item.user_id === actorUserId);
    if (currentIndex === -1) {
      throw new Error("active participant is not a participant");
    }

    const nextIndex = (currentIndex + 1) % participants.length;
    const nextUserId = participants[nextIndex]?.user_id;
    if (!nextUserId) {
      throw new Error("unable to determine next participant");
    }

    const now = nowIso();
    const nextTurnNumber = currentTurn.turn_number + 1;
    const nextRoundNumber =
      nextIndex === 0 ? currentTurn.round_number + 1 : currentTurn.round_number;
    const dueAt =
      mode.turnDurationMinutes == null
        ? null
        : new Date(Date.now() + mode.turnDurationMinutes * 60 * 1000).toISOString();

    const nextTurnId = randomUUID();
    this.db.exec("BEGIN");
    try {
      this.db
        .prepare(
          `UPDATE turns
           SET completed_at = ?, completion_reason = ?
           WHERE id = ?`
        )
        .run(now, completionReason, currentTurn.id);

      this.db
        .prepare(
          `INSERT INTO turns (
             id, artwork_id, turn_number, round_number, active_participant_user_id, started_at, due_at, completed_at, completion_reason
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
        )
        .run(nextTurnId, artworkId, nextTurnNumber, nextRoundNumber, nextUserId, now, dueAt, null, null);

      this.db
        .prepare(
          `UPDATE artworks
           SET updated_at = ?
           WHERE id = ?`
        )
        .run(now, artworkId);

      this.db.exec("COMMIT");
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }

    return {
      id: nextTurnId,
      artworkId,
      activeParticipantUserId: nextUserId,
      roundNumber: nextRoundNumber,
      turnNumber: nextTurnNumber,
      startedAt: now,
      dueAt,
      completedAt: null
    };
  }

  listDueTurns(asOfIso: string): Array<{ artworkId: Id; activeParticipantUserId: Id }> {
    const rows = this.db
      .prepare(
        `SELECT artwork_id, active_participant_user_id
         FROM turns
         WHERE completed_at IS NULL AND due_at IS NOT NULL AND due_at <= ?`
      )
      .all(asOfIso) as Array<{ artwork_id: string; active_participant_user_id: string }>;

    return rows.map((item) => ({
      artworkId: item.artwork_id,
      activeParticipantUserId: item.active_participant_user_id
    }));
  }

  advanceTurnByExpiry(artworkId: Id): TurnState {
    const currentTurn = this.db
      .prepare(
        `SELECT active_participant_user_id
         FROM turns
         WHERE artwork_id = ? AND completed_at IS NULL
         ORDER BY turn_number DESC
         LIMIT 1`
      )
      .get(artworkId) as { active_participant_user_id: string } | undefined;

    if (!currentTurn) {
      throw new Error("no active turn to expire");
    }

    return this.submitTurn(artworkId, currentTurn.active_participant_user_id, "expired");
  }

  createSnapshot(artworkId: Id, reason: "turn_submitted" | "periodic" | "manual", stateJson: string): number {
    const row = this.db
      .prepare(
        `SELECT COALESCE(MAX(version_number), 0) AS max_version
         FROM snapshots
         WHERE artwork_id = ?`
      )
      .get(artworkId) as { max_version: number };

    const nextVersion = row.max_version + 1;
    this.db
      .prepare(
        `INSERT INTO snapshots (id, artwork_id, version_number, reason, state_json, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .run(randomUUID(), artworkId, nextVersion, reason, stateJson, nowIso());

    return nextVersion;
  }

  createNotification(record: Omit<NotificationRecord, "id" | "createdAt" | "deliveredAt">): NotificationRecord {
    const id = randomUUID();
    const createdAt = nowIso();

    this.db
      .prepare(
        `INSERT INTO notifications (
           id, user_id, artwork_id, type, payload_json, channel, delivered_at, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(id, record.userId, record.artworkId, record.type, record.payloadJson, record.channel, null, createdAt);

    return {
      id,
      createdAt,
      deliveredAt: null,
      ...record
    };
  }

  markNotificationDelivered(notificationId: Id): void {
    this.db
      .prepare(
        `UPDATE notifications
         SET delivered_at = ?
         WHERE id = ?`
      )
      .run(nowIso(), notificationId);
  }

  listPendingNotifications(limit: number = 100): NotificationRecord[] {
    const rows = this.db
      .prepare(
        `SELECT id, user_id, artwork_id, type, payload_json, channel, delivered_at, created_at
         FROM notifications
         WHERE delivered_at IS NULL
         ORDER BY created_at ASC
         LIMIT ?`
      )
      .all(limit) as Array<{
      id: string;
      user_id: string;
      artwork_id: string | null;
      type: NotificationRecord["type"];
      payload_json: string;
      channel: NotificationRecord["channel"];
      delivered_at: string | null;
      created_at: string;
    }>;

    return rows.map((row) => ({
      id: row.id,
      userId: row.user_id,
      artworkId: row.artwork_id,
      type: row.type,
      payloadJson: row.payload_json,
      channel: row.channel,
      deliveredAt: row.delivered_at,
      createdAt: row.created_at
    }));
  }

  addCrdtOperation(operation: Omit<CrdtOperation, "id" | "createdAt">): CrdtOperation {
    const id = randomUUID();
    const createdAt = nowIso();

    this.db
      .prepare(
        `INSERT INTO crdt_operations (
           id, artwork_id, layer_id, actor_user_id, client_id, sequence, lamport_ts, type, payload_json, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        id,
        operation.artworkId,
        operation.layerId,
        operation.actorUserId,
        operation.clientId,
        operation.sequence,
        operation.lamportTs,
        operation.type,
        JSON.stringify(operation.payload),
        createdAt
      );

    return {
      ...operation,
      id,
      createdAt
    };
  }

  getOperationsSince(artworkId: Id, sinceLamportTs: number): CrdtOperation[] {
    const rows = this.db
      .prepare(
        `SELECT id, artwork_id, layer_id, actor_user_id, client_id, sequence, lamport_ts, type, payload_json, created_at
         FROM crdt_operations
         WHERE artwork_id = ? AND lamport_ts > ?
         ORDER BY lamport_ts ASC, created_at ASC`
      )
      .all(artworkId, sinceLamportTs) as Array<{
      id: string;
      artwork_id: string;
      layer_id: string;
      actor_user_id: string;
      client_id: string;
      sequence: number;
      lamport_ts: number;
      type: CrdtOperation["type"];
      payload_json: string;
      created_at: string;
    }>;

    return rows.map((row) => ({
      id: row.id,
      artworkId: row.artwork_id,
      layerId: row.layer_id,
      actorUserId: row.actor_user_id,
      clientId: row.client_id,
      sequence: row.sequence,
      lamportTs: row.lamport_ts,
      type: row.type,
      payload: JSON.parse(row.payload_json) as CrdtOperation["payload"],
      createdAt: row.created_at
    }));
  }

  getLatestSnapshot(artworkId: Id): { versionNumber: number; stateJson: string } | null {
    const row = this.db
      .prepare(
        `SELECT version_number, state_json
         FROM snapshots
         WHERE artwork_id = ?
         ORDER BY version_number DESC
         LIMIT 1`
      )
      .get(artworkId) as { version_number: number; state_json: string } | undefined;

    if (!row) {
      return null;
    }

    return {
      versionNumber: row.version_number,
      stateJson: row.state_json
    };
  }
}

function nowIso(): string {
  return new Date().toISOString();
}

function mapUserRow(row: {
  id: string;
  email: string;
  display_name: string;
  password_hash: string;
  created_at: string;
}): UserRecord {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    passwordHash: row.password_hash,
    createdAt: row.created_at
  };
}
