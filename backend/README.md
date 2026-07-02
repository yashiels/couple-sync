# couple-sync-backend

Self-hosted backend for Couple Sync. Replaces Firestore/Cloud Functions with Fastify + WebSocket + Postgres. Keeps Firebase Auth + FCM via the Admin SDK (Spark, free).

## Stack

- **Fastify** (HTTP) + `@fastify/websocket` (WS sync)
- **pg** (Postgres 16)
- **firebase-admin** (verify ID tokens, send FCM)
- **node-cron** (invite cleanup)
- **pino** (logging)
- Node 22, TypeScript, pnpm

## Env setup

Copy `.env.example` → `.env` and fill in:

- `DATABASE_URL` — Postgres connection string
- `FIREBASE_PROJECT_ID` — Spark project ID
- `FIREBASE_SERVICE_ACCOUNT_JSON` — stringified JSON service account key (Project Settings → Service Accounts → generate new key)
- `DOMAIN` — the domain Caddy will serve on (used in `Caddyfile`)
- `PORT` — default 3000

## Local dev

```bash
pnpm install
pnpm migrate      # runs 001_init.sql against the configured DATABASE_URL
pnpm dev          # tsx watch src/index.ts
```

Health check: `GET http://localhost:3000/health`

## Docker deploy

From repo root (where `docker-compose.yml` + `Caddyfile` live):

```bash
cp backend/.env.example backend/.env   # fill in
docker compose up -d --build
docker compose exec api pnpm migrate
```

Caddy fronts `api` on `{$DOMAIN}` with auto-TLS. Point your domain's A/AAAA record at the VPS first.

## Layout

```
backend/
├── src/
│   ├── index.ts            # Fastify + ws + cron bootstrap
│   ├── config.ts           # env validation
│   ├── db.ts               # pg.Pool singleton + query helper
│   ├── firebase.ts         # Admin SDK init (Auth + FCM)
│   ├── migrate.ts          # runs migrations/001_init.sql
│   └── migrations/
│       └── 001_init.sql    # users, couples, invites, timeblocks, overlaps_latest
├── Dockerfile              # multi-stage Node 22
├── tsconfig.json
├── vitest.config.ts
└── package.json
```

Routes (auth, blocks, invites, overlap WS) land in subsequent tasks — see `docs/superpowers/specs/2026-07-02-vps-self-host-design.md`.
