-- Schema per docs/REBUILD-SPEC.md §2. All timestamps are UTC epoch milliseconds (BIGINT).
--
-- There is no schema_migrations version table yet, so migrate.ts re-runs every file on every boot
-- and every statement here must stay idempotent (IF NOT EXISTS / IF EXISTS). Ceiling: the first
-- change that cannot be expressed idempotently (a column rename, a data backfill) needs a real
-- version table — add schema_migrations(filename PK, applied_at) and skip already-applied files.

CREATE TABLE IF NOT EXISTS couples (
  id            TEXT PRIMARY KEY,
  user_a_uid    TEXT NOT NULL,
  user_b_uid    TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  paired_at     BIGINT NOT NULL,
  created_at    BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  uid                      TEXT PRIMARY KEY,
  email                    TEXT NOT NULL,
  display_name             TEXT,
  photo_url                TEXT,
  -- NULL until the user confirms it in onboarding. Do NOT default to 'UTC':
  -- the router guard is `!user.timezone -> /timezone-setup`, and a NOT NULL DEFAULT
  -- makes that guard permanently false, so onboarding becomes unreachable.
  -- Safe to be null: a couple cannot exist before pairing, and pairing is gated behind
  -- timezone setup, so the overlap engine never sees a null zone.
  timezone                 TEXT,
  couple_id                TEXT REFERENCES couples(id) ON DELETE SET NULL,
  fcm_tokens               TEXT[] NOT NULL DEFAULT '{}',
  show_late_night_windows  BOOLEAN NOT NULL DEFAULT FALSE,
  notifications_enabled    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at               BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS invites (
  code            TEXT PRIMARY KEY,
  created_by_uid  TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  couple_id       TEXT REFERENCES couples(id) ON DELETE SET NULL,
  expires_at      BIGINT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','accepted','expired')),
  created_at      BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS timeblocks (
  id               TEXT PRIMARY KEY,
  couple_id        TEXT NOT NULL REFERENCES couples(id) ON DELETE CASCADE,
  user_id          TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  title            TEXT NOT NULL,
  type             TEXT NOT NULL CHECK (type IN ('busy','free','tentative')),
  category         TEXT,
  start_utc        BIGINT NOT NULL,
  end_utc          BIGINT NOT NULL,
  timezone         TEXT NOT NULL,
  recurrence_rule  TEXT,
  source           TEXT NOT NULL
                   CONSTRAINT timeblocks_source_check CHECK (source IN ('google','manual','device')),
  visibility       TEXT NOT NULL DEFAULT 'bothPartners'
                   CHECK (visibility IN ('bothPartners','onlyMe')),
  created_at       BIGINT NOT NULL,
  CONSTRAINT timeblocks_end_after_start CHECK (end_utc > start_utc)
);

CREATE TABLE IF NOT EXISTS overlaps_latest (
  couple_id    TEXT PRIMARY KEY REFERENCES couples(id) ON DELETE CASCADE,
  windows      JSONB NOT NULL,
  computed_at  BIGINT NOT NULL,
  input_hash   TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS timeblocks_couple_user_idx   ON timeblocks (couple_id, user_id);
CREATE INDEX IF NOT EXISTS timeblocks_couple_source_idx ON timeblocks (couple_id, source);
CREATE INDEX IF NOT EXISTS invites_status_expires_idx   ON invites (status, expires_at);
CREATE INDEX IF NOT EXISTS users_couple_idx             ON users (couple_id);

-- Widen source to allow 'device' on databases created before it existed. The CREATE TABLE above only
-- affects fresh DBs (IF NOT EXISTS), so an existing table keeps its old two-value constraint until this
-- runs. Migrations re-run on every boot with no version table, so this must be idempotent; the advisory
-- lock (held for the surrounding per-file transaction) also serialises concurrent instance boots so the
-- DROP/ADD pair cannot race.
SELECT pg_advisory_xact_lock(hashtext('timeblocks_source_check'));
ALTER TABLE timeblocks DROP CONSTRAINT IF EXISTS timeblocks_source_check;
ALTER TABLE timeblocks ADD  CONSTRAINT timeblocks_source_check CHECK (source IN ('google','manual','device'));
