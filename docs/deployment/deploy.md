# Deployment

**One app, not two.** Only the backend is deployed. The client is an Android app installed on a
device — there is no web app, no root `Dockerfile`, and nothing that builds from `assets/` or `web/`.

## How it ships

1. **CI builds and publishes an image.** `.github/workflows/docker-publish.yml` builds
   `backend/Dockerfile` on every push to `main` and pushes
   `ghcr.io/yashiels/couple-sync-backend:latest` (public image).
2. **A self-hosted Docker host pulls it.** The backend runs as a small Compose stack (api +
   Postgres 16 + a Cloudflare Tunnel) on a self-hosted box. A poller pulls the new image and
   recreates the api container automatically — no code is ever pushed *into* the host.
3. **A Cloudflare Tunnel fronts it.** TLS terminates at the Cloudflare edge and the tunnel forwards
   `couple-sync.yashiel.dev → http://api:3000`. The host binds no public port (works behind CGNAT).

The Compose stack, tunnel wiring, and secret sourcing live in a private ops repo — not here.

## Environment

Every variable is required and **boot is fail-fast** — a missing or invalid value exits the
container non-zero rather than serving 401s while reporting healthy.

| Variable | Notes |
|---|---|
| `DATABASE_URL` | Postgres 16. Boot fails if unreachable. |
| `FIREBASE_PROJECT_ID` | Must equal the service account's `project_id`, or boot fails. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | The whole service-account key file as one JSON string. Boot mints a real Google OAuth token to prove it works, so the container needs outbound access to Google's token endpoint. |
| `CORS_ORIGINS` | Comma-separated allowlist. **No default, and `*` is rejected** — `config.ts` refuses to boot on either. |
| `ADMIN_TOKEN` | Optional. Unset means `/admin/cleanup` answers 503 instead of running unauthenticated. |

The Android app talks to this host over HTTPS with a Firebase ID token in the `Authorization` header
— no cookies — so `CORS_ORIGINS` only needs origins that make browser requests. There is no browser
client today, so a single placeholder origin is enough; it exists to keep the door shut, not open.

Locally, resolve env with `op inject -i backend/.env.tpl -o backend/.env` (see the repo README).

## Migrations

`migrations/*.sql` are idempotent DDL and re-run on every boot — the container entrypoint is
`node dist/migrate.js && node dist/index.js`. There is no version table yet, so a deploy never needs a
separate migration step.

## Verify a deploy

```bash
curl https://couple-sync.yashiel.dev/health   # {"status":"ok",...}
```

If the container is restarting, read its logs first: a fail-fast boot names the exact variable or the
unreachable dependency. That is by design.
