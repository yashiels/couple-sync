-- Couple Sync — initial Postgres schema (see spec §5)
-- Idempotent: safe to re-run. Timestamps are bigint (UTC ms).

CREATE TABLE IF NOT EXISTS users (
  uid         TEXT PRIMARY KEY,
  email       TEXT NOT NULL,
  display_name TEXT,
  photo_url   TEXT,
  timezone    TEXT NOT NULL DEFAULT '',
  couple_id   TEXT,
  fcm_tokens  TEXT[] NOT NULL DEFAULT '{}',
  show_late_night_windows BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS couples (
  id          TEXT PRIMARY KEY,
  user_a_uid  TEXT NOT NULL REFERENCES users(uid),
  user_b_uid  TEXT NOT NULL REFERENCES users(uid),
  status      TEXT NOT NULL DEFAULT 'active',
  paired_at   BIGINT NOT NULL,
  created_at  BIGINT NOT NULL,
  unpair_history JSONB NOT NULL DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS invites (
  code         TEXT PRIMARY KEY,
  created_by_uid TEXT NOT NULL REFERENCES users(uid),
  couple_id    TEXT REFERENCES couples(id),
  expires_at   BIGINT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending',
  created_at   BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS timeblocks (
  id            TEXT PRIMARY KEY,
  couple_id     TEXT NOT NULL REFERENCES couples(id),
  user_id       TEXT NOT NULL REFERENCES users(uid),
  title         TEXT NOT NULL,
  type          TEXT NOT NULL,
  category      TEXT,
  start_utc     BIGINT NOT NULL,
  end_utc       BIGINT NOT NULL,
  timezone      TEXT NOT NULL,
  recurrence_rule TEXT,
  source        TEXT NOT NULL,
  visibility    TEXT NOT NULL,
  created_at    BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS overlaps_latest (
  couple_id     TEXT PRIMARY KEY REFERENCES couples(id),
  windows       JSONB NOT NULL,
  computed_at   BIGINT NOT NULL,
  input_hash    TEXT NOT NULL,
  computed_by   TEXT
);

CREATE INDEX IF NOT EXISTS idx_timeblocks_couple_user ON timeblocks (couple_id, user_id);
CREATE INDEX IF NOT EXISTS idx_timeblocks_couple_source ON timeblocks (couple_id, source);
CREATE INDEX IF NOT EXISTS idx_invites_status_expires ON invites (status, expires_at);
CREATE INDEX IF NOT EXISTS idx_users_couple ON users (couple_id);
