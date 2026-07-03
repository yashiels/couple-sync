# couple-sync-backend

Self-hosted backend for Couple Sync — replaces Firestore/Cloud Functions with **Fastify + WebSocket + Postgres**. Keeps **Firebase Auth + FCM** via the Admin SDK (Spark plan, free). Deploys as a managed Docker app behind a platform reverse proxy (Coolify/Traefik); no bundled Caddy, no host port binding.

See `docs/superpowers/specs/2026-07-02-vps-self-host-design.md` for the full design.

## Stack

- **Fastify** (HTTP REST) + `@fastify/websocket` (WS sync)
- **pg** → Postgres 16
- **firebase-admin** (verify ID tokens, send FCM)
- **node-cron** (invite cleanup)
- **pino** (logging)
- Node 22, TypeScript, pnpm

## Prerequisites

- **Docker + Docker Compose** (local dev) or a **managed Docker platform** (Coolify) for prod
- A **Firebase Spark (free) project** with:
  - Auth enabled (Email/Google/Apple sign-in providers)
  - FCM enabled (default on)
  - A **service-account JSON key** — Firebase Console → Project Settings → Service Accounts → "Generate new private key". Paste the full JSON contents into `FIREBASE_SERVICE_ACCOUNT_JSON`.
  - No Blaze plan required — Auth + FCM are free on Spark.

## Local dev

```bash
# 1. Configure env (Firebase creds; DATABASE_URL defaults to the dev postgres)
cp backend/.env.example backend/.env
#   fill in FIREBASE_PROJECT_ID + FIREBASE_SERVICE_ACCOUNT_JSON

# 2. Up the full stack (auto-merges docker-compose.override.yml → postgres + api)
docker compose up -d --build
#    api listens on http://localhost:3000 ; migrations run on container start
```

Or run the API outside Docker (faster iteration):

```bash
docker compose up postgres -d          # just the DB
cd backend && pnpm install
pnpm migrate      # applies src/migrations/001_init.sql
pnpm dev          # tsx watch src/index.ts → http://localhost:3000
```

Health check: `GET http://localhost:3000/health` → `{ "status": "ok", "time": <ms> }`.

## Deploy (Coolify / managed Docker platform)

The backend ships as a plain container app: the platform reverse proxy (Traefik on Coolify) terminates TLS and routes to the container's port 3000. **No Caddy, no host port binding** — `docker-compose.yml` only `expose`s 3000 and sets `traefik.http.services.api.loadbalancer.server.port=3000`.

1. **Provision Postgres** as a separate managed resource on the platform (Coolify: New Resource → Postgres). Note its connection string.
2. **Create the app** from this repo (Coolify: New Resource → Git → pick the `backend/Dockerfile` or the `docker-compose.yml` build pack). Connect the branch you deploy from.
3. **Set runtime env** in the service's Environment panel (not a committed .env):
   - `DATABASE_URL` — the managed Postgres connection string.
   - `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON`.
   - `ADMIN_TOKEN` (optional).
4. **Add a domain** in the platform (Coolify: Settings → Domains). The proxy issues the TLS cert automatically.
5. Push to the branch (`./deploy.sh` or `git push`) — the platform builds + rolls the container. **Migrations run automatically on start** (the image CMD runs `node dist/migrate.js` before `node dist/index.js`).
6. Health: `curl https://<your-api-domain>/health`.

### Self-managed VPS (no Coolify)

For a raw VPS using Compose directly (env-driven, still no Caddy — front it with your own reverse proxy or access `localhost:3000`):

```bash
ssh user@your-vps
cd /opt/couple-sync && git pull --ff-only
# provide env (DATABASE_URL, FIREBASE_*, ADMIN_TOKEN) via a root .env or shell
DATABASE_URL=... FIREBASE_PROJECT_ID=... FIREBASE_SERVICE_ACCOUNT_JSON=... \
  docker compose -f docker-compose.yml up -d --build
# migrations run on container start; for a one-off: docker compose exec api node dist/migrate.js
```

## Env reference

Loaded by `src/config.ts` (via `dotenv` locally; injected by the platform in prod). **No committed `.env` in prod.**

| Var | Required | Default | Notes |
|---|---|---|---|
| `DATABASE_URL` | yes | — | Postgres connection string. Injected by the platform (managed Postgres). Local dev: `postgres://couple:couple@localhost:5432/couplesync`. |
| `FIREBASE_PROJECT_ID` | yes | — | Firebase Spark project ID. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | yes | — | Stringified JSON of the service-account key. |
| `PORT` | no | `3000` | Container listen port. The platform proxy routes here. |
| `ADMIN_TOKEN` | no | `""` | Shared secret for `POST /admin/*` (manual cron triggers). When empty, admin routes respond 503. |

## API surface

### REST (HTTPS, behind the platform proxy; `Authorization: Bearer <Firebase ID token>`)

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
