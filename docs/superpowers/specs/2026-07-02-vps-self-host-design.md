# VPS Self-Host Backend — Design Spec

**Date:** 2026-07-02
**Branch:** `vps-self-host` (off `spec/edge-first-rework` — reuses the Flutter app + device-side overlap engine)
**Goal:** Replace Firestore/Cloud Functions with a self-hosted backend on the Oracle Always Free ARM VPS so the app owns its data layer and scales without Firebase free-tier ceilings. Stay on Firebase Auth + FCM (both free on Spark, no Blaze). $0/mo.

## 1. Decisions (locked)
- **Backend:** Node.js + TypeScript. Reuses the existing `redeemInvite`/`unpairCouple`/`cleanupExpiredInvites` TS logic.
- **Auth:** Keep Firebase Auth (Spark, free). Backend verifies Firebase ID tokens via Admin SDK.
- **Push:** Keep FCM (Spark, free). Backend sends via Firebase Admin SDK.
- **Real-time:** WebSocket (bidirectional, needed for two-way block sync).
- **TLS:** Caddy (auto Let's Encrypt on the user's domain).
- **Deploy:** Docker Compose + a `deploy.sh`. No Terraform (VPS already exists).
- **DB:** Postgres 16.

## 2. What stays (from the prior work — do NOT rewrite)
- `lib/core/overlap/overlap_engine.dart` + `overlap_controller.dart` — pure device compute, backend-agnostic.
- All Flutter UX (Plans B/C): screens, theme, navigation, calendar service, App Check client.
- `firebase_auth` + `firebase_messaging` Flutter packages (free Spark).
- Google Calendar freebusy (device-side).

## 3. What's new
- `backend/` — a Node/TS service: Fastify (HTTP) + `ws` (WebSocket) + `pg` (Postgres) + `firebase-admin` (Auth verify + FCM) + `node-cron` (cleanup).
- Postgres schema mirroring the Firestore collections.
- `docker-compose.yml` (postgres + api + caddy), `Caddyfile`, `Dockerfile`, `.env.example`, `deploy.sh`.
- Flutter `SyncService` — replaces `FirestoreService`: WebSocket client + HTTP client + local Hive cache. The Riverpod providers + overlap controller stay; only the data source swaps.

## 4. Architecture
```
Flutter app                         VPS (Docker Compose)
─────────────────                   ──────────────────────────────
firebase_auth ───────────────────►  Firebase Auth (Spark, free) — issues ID token
firebase_messaging ◄──────────────  FCM (Spark, free) — pushes from backend
                                        │
SyncService (WS + HTTP) ─────────►  Caddy (TLS) ─► API (Node/TS)
  ├─ WS: blocks + overlap stream              ├─ verify ID token (Admin SDK)
  └─ HTTP: pairing, invite, block CRUD        ├─ Postgres (blocks, couples, invites, overlaps_latest)
                                              ├─ WS broadcast to partner
                                              └─ FCM push on overlap change (Admin SDK)
```
**No Blaze. No Firestore. No Cloud Functions. No Cloud Scheduler.**

## 5. Data model (Postgres)
Mirrors the Firestore collections. Timestamps as `bigint` (UTC ms) to match the device layer's int convention.

```sql
CREATE TABLE users (
  uid         TEXT PRIMARY KEY,
  email       TEXT NOT NULL,
  display_name TEXT,
  photo_url   TEXT,
  timezone    TEXT NOT NULL DEFAULT 'UTC',
  couple_id   TEXT,
  fcm_tokens  TEXT[] NOT NULL DEFAULT '{}',
  show_late_night_windows BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  BIGINT NOT NULL
);

CREATE TABLE couples (
  id          TEXT PRIMARY KEY,           -- generated
  user_a_uid  TEXT NOT NULL REFERENCES users(uid),
  user_b_uid  TEXT NOT NULL REFERENCES users(uid),
  status      TEXT NOT NULL DEFAULT 'active',
  paired_at   BIGINT NOT NULL,
  created_at  BIGINT NOT NULL,
  unpair_history JSONB NOT NULL DEFAULT '[]'
);

CREATE TABLE invites (
  code         TEXT PRIMARY KEY,          -- 6-char
  created_by_uid TEXT NOT NULL REFERENCES users(uid),
  couple_id    TEXT REFERENCES couples(id),
  expires_at   BIGINT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending',  -- pending|redeemed|expired
  created_at   BIGINT NOT NULL
);

CREATE TABLE timeblocks (
  id            TEXT PRIMARY KEY,         -- generated
  couple_id     TEXT NOT NULL REFERENCES couples(id),
  user_id       TEXT NOT NULL REFERENCES users(uid),
  title         TEXT NOT NULL,
  type          TEXT NOT NULL,            -- busy|free|tentative
  category      TEXT,
  start_utc     BIGINT NOT NULL,
  end_utc       BIGINT NOT NULL,
  timezone      TEXT NOT NULL,
  recurrence_rule TEXT,
  source        TEXT NOT NULL,            -- google|manual
  visibility    TEXT NOT NULL,            -- bothPartners|onlyMe
  created_at    BIGINT NOT NULL
);

CREATE TABLE overlaps_latest (
  couple_id     TEXT PRIMARY KEY REFERENCES couples(id),
  windows       JSONB NOT NULL,
  computed_at   BIGINT NOT NULL,
  input_hash    TEXT NOT NULL,
  computed_by   TEXT
);

CREATE INDEX ON timeblocks (couple_id, user_id);
CREATE INDEX ON timeblocks (couple_id, source);
```

## 6. API surface

### REST (HTTPS, behind Caddy; Bearer = Firebase ID token)
- `POST /auth/verify` — exchange Firebase ID token for a session (returns couple info + 200; creates/updates `users` row).
- `POST /invites` — create invite code (6-char, 48h expiry).
- `POST /invites/:code/redeem` — atomic pairing (port `redeemInvite`). Returns coupleId.
- `POST /couples/:id/unpair` — port `unpairCouple`.
- `GET/POST/PUT/DELETE /blocks` — block CRUD (couple-scoped; server enforces couple membership).
- `POST /blocks/batch` — atomic replace google-sourced blocks (port `atomicReplaceGoogleSourcedBlocks`).
- `GET /overlaps/latest?coupleId=X` — fetch the stored latest overlap (for reconnect after offline).

### WebSocket (`wss://api.../sync?token=<firebase id token>`)
- Auth: server verifies the token on connect; rejects on invalid.
- Subscribe to a couple's block stream.
- Messages (JSON, tagged):
  - `{"t":"block:set","block":{...}}` — a block was created/updated; server persists + broadcasts to the partner's socket + stores.
  - `{"t":"block:del","id":"..."}` — delete.
  - `{"t":"overlap","windows":[...],"inputHash":"...","computedBy":"..."}` — a device computed overlap; server stores `overlaps_latest` (if `inputHash` differs) + pushes FCM to the partner if they're offline (or no-ops if the partner's socket is live — they got the WS broadcast already).
- The server does NOT compute overlap — the device does. The server only stores + fans-out + pushes for offline partners.

## 7. Auth flow
1. App signs in via `firebase_auth` → gets a Firebase ID token.
2. App opens WS with `?token=<id token>`; backend `admin.auth().verifyIdToken(token)` → `uid`. Reject on failure.
3. Backend upserts `users` row (email, display_name, photo_url from the decoded token).
4. FCM token: app registers via `firebase_messaging`, sends token to `POST /auth/fcm-token`; backend appends to `users.fcm_tokens` (dedup).

## 8. FCM push flow
- On `overlap` message where the partner has NO live WS socket: backend reads the partner's `fcm_tokens`, sends FCM via `admin.messaging().sendEachForMulticast(...)`, prunes invalid tokens (port `filterInvalidFcmTokens` from `onOverlapWrite.ts`).
- If the partner HAS a live socket: the WS `overlap` broadcast already reached them; no FCM.

## 9. Flutter changes
- New `lib/services/sync_service.dart` (`SyncService`): WS client (reconnect w/ backoff) + HTTP client (Bearer token) + Hive cache for offline blocks.
- `FirestoreService` retired. `firestore_provider.dart` → `sync_provider.dart`.
- Providers (`couple_providers`, `calendar_provider`, etc.) swap their `FirestoreService` calls for `SyncService` calls. The `overlapControllerProvider` watches `SyncService.watchBlocks(coupleId)` instead of `FirestoreService.watchBlocks`.
- The controller's `writeOverlapTransaction` → `SyncService.publishOverlap(result)` (sends the `overlap` WS message; no Firestore transaction — the server does the dedup via `inputHash`).
- Offline: Hive caches blocks; on reconnect, WS replays latest state; overlap recomputes locally from the cache.

## 10. Deploy
- `backend/Dockerfile` — multi-stage Node 22 build.
- `docker-compose.yml` — `postgres` (named volume), `api` (depends on postgres), `caddy` (ports 80/443, fronts api).
- `Caddyfile` — `api.yourdomain.tld { reverse_proxy api:3000 }` → auto-TLS.
- `.env.example` — `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON` (the Spark project's service account key), `DATABASE_URL`, `JWT_AUD`, `DOMAIN`.
- `deploy.sh` — `ssh vps "cd /opt/couple-sync && git pull && docker compose up -d --build && docker compose exec api pnpm migrate"`.

## 11. Scaling
- Single VPS: Postgres + WS on 24 GB ARM handles tens of thousands of couples.
- Outgrow one box: add a second `api` replica + a `redis` container for WS pub/sub fan-out (so both replicas can broadcast to a couple's sockets). Config change, not a rewrite.
- Postgres backups: `pg_dump` cron to a B2/S3 bucket (~$0 for tiny data).

## 12. Testing
- Backend: unit tests for pairing atomicity (port the jest tests), WS auth (reject invalid token), FCM token pruning, overlap dedup on `inputHash`.
- Flutter: `SyncService` unit tests with a mock WS/HTTP (reconnect, offline cache replay).
- Integration: a docker-compose `test` profile that spins up Postgres + the API and runs the WS pairing flow end-to-end.

## 13. Open questions
1. Domain for the API (you confirmed you have one) — what is it? (Used in `Caddyfile` + Flutter `baseUrl`.)
2. Firebase service account: you'll create one in the Spark project console (Project Settings → Service Accounts → generate JSON). No Blaze needed.
3. Package manager: `pnpm` (fast, disk-efficient) vs `npm`. Default `pnpm`.
