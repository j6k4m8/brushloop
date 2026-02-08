# BrushLoop MVP Architecture

## Top-Level Components

- Flutter client (`app/`)
  - Auth flow (email/password).
  - Home dashboard for contacts and artworks.
  - Artwork editor with layers, tool selection, local undo/redo, and collaboration socket wiring.
- Node.js server (`server/`)
  - REST API for auth, contacts, artwork management, and turn submission.
  - WebSocket collaboration hub for artwork presence, sync, and operation broadcast.
  - Background workers for turn expiry and notification dispatch.
- Shared contracts (`packages/shared/`)
  - Cross-package models, DTO contracts, protocol message types, and runtime validators.

## Persistence

- SQLite database (`data/brushloop.sqlite`) with tables:
  - `users`, `sessions`
  - `contact_invitations`, `contacts`
  - `artworks`, `artwork_modes`, `artwork_participants`
  - `layers`, `crdt_operations`, `snapshots`
  - `turns`, `notifications`
- Local file storage for media/snapshot payload references.

## Collaboration Flow

1. Client authenticates over REST and receives bearer token.
2. Client opens `/ws`, sends `client.hello`, then `client.join_artwork`.
3. Server verifies membership, sends snapshot + operations for sync.
4. Client emits `client.apply_operations` for new vector ops.
5. Server persists ops and broadcasts `server.operations` to room members.
6. Turn-based mode enforces active participant on server before accepting ops.

## Turn System

- Turn-based artworks create an initial active turn.
- `POST /api/turns/submit` advances to next participant.
- `TurnExpiryWorker` scans due turns and auto-advances timed-out turns.
- Snapshot creation:
  - Every submitted turn (`turn_submitted`).
  - Periodically every `BRUSHLOOP_SNAPSHOT_EVERY_TURNS` turns (`periodic`).

## Notifications

- Notification events are persisted in `notifications`.
- `NotificationDispatcher` drains undelivered records and forwards to `NotificationAdapter`.
- MVP adapter (`LocalNotificationAdapter`) writes deliveries to local JSONL log.
