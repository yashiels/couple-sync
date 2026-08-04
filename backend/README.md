# Couple Sync backend

Fastify + Postgres + WebSocket. Computes overlap windows server-side and fans them out over WS and
FCM. Node 22, ESM, **pnpm** (never npm/yarn).

## Environment

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | Postgres connection string. Boot fails if unreachable. |
| `FIREBASE_PROJECT_ID` | yes | Must equal the service account's `project_id`, or boot fails. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | yes | The whole service-account key file as one JSON string. Boot mints a real Google OAuth token to prove it works. |
| `CORS_ORIGINS` | yes | Comma-separated allowlist. No default, and `*` is refused. |
| `ADMIN_TOKEN` | no | Unset means `/admin/cleanup` answers 503 instead of running unauthenticated. |
| `PORT` | no | Defaults to `3000`. |

Boot is fail-fast on every one of the required vars, on an unreachable database, and on an unusable
Firebase credential. The container exits non-zero rather than serving 401s while looking healthy — so
a real service account with outbound access to Google's token endpoint is a prerequisite for the
container to start at all, locally included.

## Run locally

From the repo root:

```bash
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --build
curl localhost:3000/health
```

The override adds a throwaway `postgres:16` (trust auth, no volume) and publishes port 3000.
`FIREBASE_PROJECT_ID` and `FIREBASE_SERVICE_ACCOUNT_JSON` must be exported in your shell first.
Tear down with `down -v`.

Without Docker: `pnpm install && pnpm dev` (tsx watch), with the same env vars set.

## Migrations

`migrations/*.sql` are idempotent DDL and re-run on every boot — there is no version table yet. The
container entrypoint is `node dist/migrate.js && node dist/index.js`.

Standalone, needing only `DATABASE_URL` (`migrate.ts` deliberately does not import `config.ts`):

```bash
pnpm build && DATABASE_URL=postgres://… node dist/migrate.js
```

## Deploy

Push to `main`. Coolify builds `backend/Dockerfile` via `docker-compose.yml` and Traefik terminates
TLS in front of it, so the container is never published on a host port. Env vars come from the
Coolify app's environment. See `docs/deployment/coolify.md`.

## Tests

```bash
pnpm build && pnpm test
```

Always both, in that order: `src/__tests__/boot-esm.test.ts` imports the **built** output to catch
CJS/ESM interop breakage that `tsc` and vitest alone do not see.
