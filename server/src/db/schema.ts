/**
 * Canonical SQLite schema for BrushLoop MVP.
 */
export const SCHEMA_SQL = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS contact_invitations (
  id TEXT PRIMARY KEY,
  inviter_user_id TEXT NOT NULL,
  invitee_email TEXT NOT NULL,
  invitee_user_id TEXT,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  responded_at TEXT,
  FOREIGN KEY (inviter_user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (invitee_user_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS contacts (
  id TEXT PRIMARY KEY,
  user_a_id TEXT NOT NULL,
  user_b_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE (user_a_id, user_b_id),
  FOREIGN KEY (user_a_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (user_b_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS artworks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  width INTEGER NOT NULL,
  height INTEGER NOT NULL,
  base_photo_path TEXT,
  created_by_user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS artwork_modes (
  artwork_id TEXT PRIMARY KEY,
  mode TEXT NOT NULL,
  turn_duration_minutes INTEGER,
  FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS artwork_participants (
  id TEXT PRIMARY KEY,
  artwork_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  turn_index INTEGER NOT NULL,
  joined_at TEXT NOT NULL,
  UNIQUE (artwork_id, user_id),
  FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS layers (
  id TEXT PRIMARY KEY,
  artwork_id TEXT NOT NULL,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  is_visible INTEGER NOT NULL,
  is_locked INTEGER NOT NULL,
  created_by_user_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS crdt_operations (
  id TEXT PRIMARY KEY,
  artwork_id TEXT NOT NULL,
  layer_id TEXT NOT NULL,
  actor_user_id TEXT NOT NULL,
  client_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  lamport_ts INTEGER NOT NULL,
  type TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE CASCADE,
  FOREIGN KEY (layer_id) REFERENCES layers(id) ON DELETE CASCADE,
  FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS snapshots (
  id TEXT PRIMARY KEY,
  artwork_id TEXT NOT NULL,
  version_number INTEGER NOT NULL,
  reason TEXT NOT NULL,
  state_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS turns (
  id TEXT PRIMARY KEY,
  artwork_id TEXT NOT NULL,
  turn_number INTEGER NOT NULL,
  round_number INTEGER NOT NULL,
  active_participant_user_id TEXT NOT NULL,
  started_at TEXT NOT NULL,
  due_at TEXT,
  completed_at TEXT,
  completion_reason TEXT,
  UNIQUE (artwork_id, turn_number),
  FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE CASCADE,
  FOREIGN KEY (active_participant_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  artwork_id TEXT,
  type TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  channel TEXT NOT NULL,
  delivered_at TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (artwork_id) REFERENCES artworks(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS media_assets (
  id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  storage_driver TEXT NOT NULL,
  storage_key TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  original_filename TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id TEXT PRIMARY KEY,
  sender_user_id TEXT NOT NULL,
  recipient_user_id TEXT NOT NULL,
  body TEXT NOT NULL,
  read_at TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (sender_user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (recipient_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_invitations_email ON contact_invitations(invitee_email);
CREATE INDEX IF NOT EXISTS idx_participants_artwork ON artwork_participants(artwork_id);
CREATE INDEX IF NOT EXISTS idx_participants_user ON artwork_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_turns_artwork_completed ON turns(artwork_id, completed_at);
CREATE INDEX IF NOT EXISTS idx_ops_artwork_lamport ON crdt_operations(artwork_id, lamport_ts);
CREATE INDEX IF NOT EXISTS idx_snapshots_artwork_version ON snapshots(artwork_id, version_number);
CREATE INDEX IF NOT EXISTS idx_notifications_user_delivered ON notifications(user_id, delivered_at);
CREATE INDEX IF NOT EXISTS idx_media_assets_owner ON media_assets(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender_recipient_created
  ON chat_messages(sender_user_id, recipient_user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_messages_recipient_sender_created
  ON chat_messages(recipient_user_id, sender_user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_messages_recipient_sender_read
  ON chat_messages(recipient_user_id, sender_user_id, read_at);
`;
