# Managed-Platform Self-Host Backend — Design Spec

**Date:** 2026-07-02 (updated for Coolify/Traefik deployment)
**Branch:** `vps-self-host` (off `spec/edge-first-rework` — reuses the Flutter app + device-side overlap engine)
**Goal:** Replace Firestore/Cloud Functions with a self-hosted backend so the app owns its data layer and scales without Firebase free-tier ceilings. Stay on Firebase Auth + FCM (both free on Spark, no Blaze). $0/mo.

## 1. Decisions (locked)
- **Backend:** Node.js + TypeScript. Reuses the existing `redeemInvite`/`unpairCouple`/`cleanupExpiredInvites` TS logic.
- **Auth:** Keep Firebase Auth (Spark, free). Backend verifies Firebase ID tokens via Admin SDK.
- **Push:** Keep FCM (Spark, free). Backend sends via Firebase Admin SDK.
- **Real-time:** WebSocket (bidirectional, needed for two-way block sync).
- **TLS / reverse proxy:** Platform-managed (e.g. Coolify's built-in Traefik). No Caddy container.
- **Deploy:** Coolify (or any managed container platform). `docker-compose.yml` is app-only — no host-bound ports, no reverse proxy service.
- **DB:** Postgres 16.

## 2. What stays (from the prior work — do NOT rewrite)
- `lib/core/overlap/overlap_engine.dart` + `overlap_controller.dart` — pure device compute, backend-agnostic.
- All Flutter UX (Plans B/C): screens, theme, navigation, calendar service, App Check client.
- `firebase_auth` + `firebase_messaging` Flutter packages (free Spark).
- Google Calendar freebusy (device-side).

## 3. What's new
- `backend/` — a Node/TS service: Fastify (HTTP) + `ws` (WebSocket) + `pg` (Postgres) + `firebase-admin` (Auth verify + FCM) + `node-cron` (cleanup).
- Postgres schema mirroring the Firestore collections.
- `docker-compose.yml` (api only — no host 80/443, no reverse proxy, no bundled production Postgres), `Dockerfile`, `.env.example`, `deploy.sh`.
- `docker-compose.override.yml` — local dev convenience: exposes postgres on `5432` for direct client access.
- Flutter `SyncService` — replaces `FirestoreService`: WebSocket client + HTTP client + local Hive cache. The Riverpod providers + overlap controller stay; only the data source swaps.

## 4. Architecture
```
Flutter app                         Platform (Coolify / managed)
─────────────────                   ──────────────────────────────
firebase_auth ───────────────────►  Firebase Auth (Spark, free) — issues ID token
firebase_messaging ◄──────────────  FCM (Spark, free) — pushes from backend
                                        │
SyncService (WS + HTTP) ─────────►  Traefik (platform TLS) ─► API (Node/TS, :3000)
  ├─ WS: blocks + overlap stream              ├─ verify ID token (Admin SDK)
  └─ HTTP: pairing, invite, block CRUD        ├─ Postgres (blocks, couples, invites, overlaps_latest)
                                              ├─ WS broadcast to partner
                                              └─ FCM push on overlap change (Admin SDK)
```
**No Blaze. No Firestore. No Cloud Functions. No Cloud Scheduler.**

## 5. docker-compose.yml (production shape)

```yaml
services:
  api:
    build: ./backend
    environment:
      DATABASE_URL: ${DATABASE_URL}
      FIREBASE_PROJECT_ID: ${FIREBASE_PROJECT_ID}
      FIREBASE_SERVICE_ACCOUNT_JSON: ${FIREBASE_SERVICE_ACCOUNT_JSON}
      PORT: 3000
    expose:
      - "3000"           # platform reverse proxy connects here; no host binding
    labels:
      - traefik.http.services.api.loadbalancer.server.port=3000
    restart: unless-stopped
```

Key points:
- **No `caddy` service.** TLS and routing are handled by the platform (Coolify/Traefik).
- **No `ports: - "80:80"` or `"443:443"`.** The API container uses `expose: 3000`; the platform proxy routes HTTPS traffic to it.
- **No bundled production Postgres.** Provision Postgres as a managed/platform resource and inject `DATABASE_URL`.
- **Migrations run inside the Docker image startup command** (`CMD ["sh", "-c", "node dist/migrate.js && node dist/index.js"]`). No manual `docker compose exec` step needed.

## 6. docker-compose.override.yml (local dev only — not deployed)

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: couple_sync
      POSTGRES_USER: couple_sync
      POSTGRES_PASSWORD: local-password
    ports:
      - "5432:5432"   # expose locally for psql / GUI clients
    volumes:
      - postgres_data:/var/lib/postgresql/data

  api:
    environment:
      DATABASE_URL: postgresql://couple_sync:local-password@postgres:5432/couple_sync
    depends_on:
      - postgres

volumes:
  postgres_data:
```

This file is **not committed as part of the production deployment**; it only applies when running locally with `docker compose up`.

## 7. Data model (Postgres)
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

## 8. API surface

### REST (HTTPS, behind platform proxy; Bearer = Firebase ID token)
- `POST /auth/verify` — exchange Firebase ID token for a session (returns couple info + 200; creates/updates `users` row).
- `POST /invites` — create invite code (6-char, 48h expiry).
- `POST /invites/:code/redeem` — atomic pairing (port `redeemInvite`). Returns coupleId.
- `POST /couples/:id/unpair` — port `unpairCouple`.
- `GET/POST/PUT/DELETE /blocks` — block CRUD (couple-scoped; server enforces couple membership).
- `POST /blocks/batch` — atomic replace google-sourced blocks (port `atomicReplaceGoogleSourcedBlocks`).
- `GET /overlaps/latest?coupleId=X` — fetch the stored latest overlap (for reconnect after offline).

### WebSocket (`wss://api.yourdomain.tld/sync?token=<firebase id token>`)
- Auth: server verifies the token on connect; rejects on invalid.
- Subscribe to a couple's block stream.
- Messages (JSON, tagged):
  - `{"t":"block:set","block":{...}}` — a block was created/updated; server persists + broadcasts to the partner's socket.
  - `{"t":"block:del","id":"..."}` — delete.
  - `{"t":"overlap","windows":[...],"inputHash":"...","computedBy":"..."}` — a device computed overlap; server stores `overlaps_latest` (if `inputHash` differs) + pushes FCM to the partner if they're offline.
- The server does NOT compute overlap — the device does. The server only stores + fans-out + pushes for offline partners.

## 9. Auth flow
1. App signs in via `firebase_auth` → gets a Firebase ID token.
2. App opens WS with `?token=<id token>`; backend `admin.auth().verifyIdToken(token)` → `uid`. Reject on failure.
3. Backend upserts `users` row (email, display_name, photo_url from the decoded token).
4. FCM token: app registers via `firebase_messaging`, sends token to `POST /auth/fcm-token`; backend appends to `users.fcm_tokens` (dedup).

## 10. FCM push flow
- On `overlap` message where the partner has NO live WS socket: backend reads the partner's `fcm_tokens`, sends FCM via `admin.messaging().sendEachForMulticast(...)`, prunes invalid tokens.
- If the partner HAS a live socket: the WS `overlap` broadcast already reached them; no FCM.

## 11. Flutter changes
- New `lib/services/sync_service.dart` (`SyncService`): WS client (reconnect w/ backoff) + HTTP client (Bearer token) + Hive cache for offline blocks.
- `FirestoreService` retired. `firestore_provider.dart` → `sync_provider.dart`.
- Providers swap their `FirestoreService` calls for `SyncService` calls. The `overlapControllerProvider` watches `SyncService.watchBlocks(coupleId)`.
- The controller's `writeOverlapTransaction` → `SyncService.publishOverlap(result)` (sends the `overlap` WS message).
- Offline: Hive caches blocks; on reconnect, WS replays latest state; overlap recomputes locally from the cache.

## 12. Deploy (Coolify)
- **Platform:** Coolify (or any managed container platform with a built-in reverse proxy).
- `backend/Dockerfile` — multi-stage Node 22 build.
- `docker-compose.yml` — `api` only (expose :3000). No host ports, no Caddy, no bundled production Postgres.
- Platform (Coolify) handles domain routing, TLS certificate provisioning (via its Traefik instance), and proxying HTTPS → `api:3000`.
- `.env.example` — `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `DATABASE_URL`, `POSTGRES_USER`, `POSTGRES_PASSWORD`.
- `deploy.sh` — triggers a Coolify redeploy (or `git push` to the Coolify-tracked branch). Migrations run automatically inside the container start command.

## 13. Scaling
- Single node: Postgres + WS handles tens of thousands of couples on a modest ARM VPS.
- Outgrow one node: add a second `api` replica + a `redis` container for WS pub/sub fan-out (so both replicas can broadcast to a couple's sockets). Config change, not a rewrite.
- Postgres backups: `pg_dump` cron to a B2/S3 bucket (~$0 for tiny data).

## 14. Testing
- **Unit tests (`npm test`):** pairing atomicity, WS auth (reject invalid token), FCM token pruning, overlap dedup on `inputHash`. Run without Docker or Firebase emulator.
- **Emulator tests (`npm run test:emulator`):** Firestore security rule assertions. Require `firebase emulators:start --only firestore` to be running first.
- **Flutter:** `SyncService` unit tests with a mock WS/HTTP (reconnect, offline cache replay).
- **Integration:** a docker-compose `test` profile that spins up Postgres + the API and runs the WS pairing flow end-to-end.

## 15. Open questions
1. Domain for the API — configure in the Coolify dashboard under the service's domain setting.
2. Firebase service account: create in the Spark project console (Project Settings → Service Accounts → generate JSON). No Blaze needed.
