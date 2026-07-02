# couple-sync-backend

Self-hosted backend for Couple Sync — replaces Firestore/Cloud Functions with **Fastify + WebSocket + Postgres**, on a single VPS. Keeps **Firebase Auth + FCM** via the Admin SDK (Spark plan, free). $0/mo on an Oracle Always Free ARM box.

See `docs/superpowers/specs/2026-07-02-vps-self-host-design.md` for the full design.

## Stack

- **Fastify** (HTTP REST) + `@fastify/websocket` (WS sync)
- **pg** → Postgres 16
- **firebase-admin** (verify ID tokens, send FCM)
- **node-cron** (invite cleanup)
- **pino** (logging)
- Node 22, TypeScript, pnpm

## Prerequisites

- **Node 22** + **pnpm** (local dev only; the VPS runs everything in Docker)
- **Docker + Docker Compose** on the VPS
- A **Firebase Spark (free) project** with:
  - Auth enabled (Email/Google/Apple sign-in providers)
  - FCM enabled (default on)
  - A **service-account JSON key** — Firebase Console → Project Settings → Service Accounts → "Generate new private key". Paste the full JSON contents into `FIREBASE_SERVICE_ACCOUNT_JSON` (see `.env.example`).
  - No Blaze plan required — Auth + FCM are free on Spark.

## Local dev

```bash
# 1. Start a local Postgres (the compose `postgres` service, no api/caddy yet)
docker compose up postgres -d

# 2. Configure env
cd backend
cp .env.example .env
# fill in FIREBASE_PROJECT_ID + FIREBASE_SERVICE_ACCOUNT_JSON
# DATABASE_URL should point at the local container (default works)

# 3. Install + migrate + run
pnpm install
pnpm migrate      # applies src/migrations/001_init.sql
pnpm dev          # tsx watch src/index.ts  → http://localhost:3000
```

Health check: `GET http://localhost:3000/health` → `{ "status": "ok", "time": <ms> }`.

## Deploy to the VPS

Easiest: from repo root,

```bash
VPS_HOST=user@your-vps-host ./deploy.sh
```

`deploy.sh` is idempotent and safe to re-run. It:
1. `ssh`es to the VPS,
2. `cd /opt/couple-sync && git pull --ff-only`,
3. `docker compose up -d --build` (rebuilds api + restarts postgres + caddy),
4. waits for postgres to be healthy, then `docker compose exec api pnpm migrate`.

One-time bootstrap on the VPS (first deploy only):

```bash
ssh user@your-vps-host
sudo mkdir -p /opt/couple-sync && sudo chown -R $USER /opt/couple-sync
git clone <your-repo-url> /opt/couple-sync
cd /opt/couple-sync
cp backend/.env.example backend/.env
# edit backend/.env — fill in FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT_JSON, DOMAIN
# log out, then locally: VPS_HOST=user@your-vps-host ./deploy.sh
```

Manual equivalent of `deploy.sh`:

```bash
ssh user@your-vps-host
cd /opt/couple-sync
git pull --ff-only
docker compose up -d --build
docker compose exec api pnpm migrate
```

Caddy fronts `{$DOMAIN}` → `api:3000` with auto-TLS. Point your domain's A/AAAA record at the VPS IP first (see `docs/MANUAL_STEPS.md` → "VPS self-host setup").

## Env reference

All vars live in `backend/.env` (loaded by `src/config.ts` via `dotenv`). The Docker compose `api` service reads this file via `env_file`.

| Var | Required | Default | Notes |
|---|---|---|---|
| `DATABASE_URL` | yes | — | Postgres connection string. Compose overrides to `postgres://couple:couple@postgres:5432/couplesync`. |
| `FIREBASE_PROJECT_ID` | yes | — | Firebase Spark project ID. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | yes | — | Stringified JSON of the service-account key (Project Settings → Service Accounts → generate). |
| `DOMAIN` | no | `api.example.com` | Domain Caddy serves on. Also drives the Flutter `baseUrl`. |
| `PORT` | no | `3000` | Port the api container listens on. Caddy reverse-proxies to this. |
| `ADMIN_TOKEN` | no | `""` | Shared secret for `POST /admin/*` (manual cron triggers). When empty, admin routes respond 503. |

## API surface

### REST (HTTPS, behind Caddy; `Authorization: Bearer <Firebase ID token>`)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Liveness (no auth). |
| `POST` | `/auth/verify` | Exchange Firebase ID token for a session; upserts `users` row. |
| `POST` | `/auth/fcm-token` | Register/refresh the device's FCM token. |
| `GET` | `/blocks?coupleId=X` | All blocks for the couple (both partners). |
| `POST` | `/blocks` | Create a block; broadcasts `block:set` to the partner. |
| `GET` | `/blocks/:id?coupleId=X` | Single block. |
| `PUT` | `/blocks/:id` | Partial update; broadcasts `block:set`. |
| `DELETE` | `/blocks/:id` | Delete; broadcasts `block:del`. |
| `POST` | `/blocks/batch` | Atomic replace of google-sourced blocks for a user. |
| `GET` | `/overlaps/latest?coupleId=X` | Stored latest overlap (reconnect after offline). 404 → null. |
| `GET` | `/couples/:id` | Couple doc (membership enforced). |
| `POST` | `/couples/:id/unpair` | Unpair (sets inactive, clears couple_id, deletes shared blocks + overlap). |
| `POST` | `/invites` | Create a 6-char invite code (48h expiry). |
| `POST` | `/invites/:code/redeem` | Atomic pairing. Returns `coupleId`. |
| `POST` | `/admin/cleanup-invites` | Manual invite-cleanup trigger (needs `ADMIN_TOKEN`). |

### WebSocket (`wss://api.../sync?token=<Firebase ID token>`)

Auth: the token is verified on connect; the socket is closed with code `4001` on invalid token. The authed `uid` is stashed on the socket and used to authorize every incoming message.

Messages (JSON, tagged by `t`):

| Direction | `t` | Shape | Server action |
|---|---|---|---|
| server → client | `hello` | `{ t, uid, coupleId }` | Sent on connect. |
| server → client | `block:set` | `{ t, block }` | A block was created/updated. |
| server → client | `block:del` | `{ t, id }` | A block was deleted. |
| server → client | `overlap` | `{ t, coupleId, windows, inputHash, computedBy }` | Forwarded partner-computed overlap. |
| server → client | `unpair` | `{ t, coupleId }` | The couple was unpaired. |
| client → server | `overlap` | `{ t, coupleId, windows, inputHash, computedBy }` | Device-computed overlap. Server asserts `computedBy === socket.uid` (V8), stores `overlaps_latest` (dedup on `inputHash`), and either forwards to the partner's live socket or sends an FCM push if the partner is offline. |

The server does **not** compute overlap — the device does. The server only stores, fans-out, and pushes for offline partners.

## Layout

```
backend/
├── src/
│   ├── index.ts            # Fastify + ws + cron bootstrap
│   ├── config.ts           # env validation
│   ├── db.ts               # pg.Pool singleton + query helper
│   ├── firebase.ts         # Admin SDK init (Auth + FCM)
│   ├── auth.ts             # verifyIdToken (Bearer header or ?token=)
│   ├── couples.ts          # assertMember + getCoupleOr404
│   ├── overlap.ts          # V5 overlap WS handler + FCM push
│   ├── cron.ts             # admin routes + invite cleanup cron
│   ├── migrate.ts          # runs migrations/001_init.sql
│   ├── migrations/
│   │   └── 001_init.sql    # users, couples, invites, timeblocks, overlaps_latest
│   └── routes/
│       ├── auth.ts         # /auth/verify, /auth/fcm-token
│       ├── sync.ts         # /sync (WS) + authorizeOverlapMessage (V8)
│       ├── blocks.ts       # /blocks CRUD + batch
│       ├── overlaps.ts     # /overlaps/latest (V8)
│       ├── users.ts        # user profile GET/PATCH
│       ├── couples.ts      # /couples/:id, /couples/:id/unpair
│       └── invites.ts      # /invites, /invites/:code/redeem
├── Dockerfile              # multi-stage Node 22
├── tsconfig.json
├── vitest.config.ts
└── package.json
```

## Tests

```bash
cd backend && pnpm test
```

Covers: auth verify, block CRUD + broadcast, pairing atomicity + unpair, overlap WS handler (validate/dedup/broadcast/push/token-prune), `GET /overlaps/latest`, and the `computedBy === socket-uid` assertion.
