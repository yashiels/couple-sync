# Coolify deployment

**One app, not two.** Only the backend is deployed. The client is an Android app installed on a
device, so there is no web app, no root `Dockerfile`, and nothing that builds from `assets/` or
`web/`. (An earlier revision of this file described a Flutter web deployable; none of it exists.)

## The app

- Name: `couple-sync-api`
- Build pack: **Docker Compose**
- Compose file: `/docker-compose.yml` — it builds `./backend/Dockerfile` and carries the Traefik
  labels, so the container is never published on a host port and Traefik terminates TLS in front.
- Domain: `https://api.couple-sync.yashiel.dev`
- Repository `yashiels/couple-sync`, branch `main`, auto deploy enabled.
- Watch paths:

  ```text
  backend/**
  docker-compose.yml
  ```

Do **not** add `docker-compose.override.yml`. It is local-dev only: it publishes port 3000 and starts
a throwaway trust-auth Postgres with no volume.

## Environment

Every one of these is required, and **boot is fail-fast on all of them** — a missing or invalid value
exits the container non-zero rather than serving 401s while reporting healthy.

| Variable | Notes |
|---|---|
| `API_DOMAIN` | Hostname only, no scheme. Consumed by the Traefik router rule in `docker-compose.yml`. |
| `DATABASE_URL` | Managed Postgres 16. Boot fails if unreachable. |
| `FIREBASE_PROJECT_ID` | Must equal the service account's `project_id`, or boot fails. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | The whole service-account key file as one JSON string. Boot mints a real Google OAuth token to prove it works, so the container needs outbound access to Google's token endpoint. |
| `CORS_ORIGINS` | Comma-separated allowlist. **No default, and `*` is rejected** — `config.ts` refuses to boot on either. This file previously documented the opposite; following it produced a dead container. |
| `ADMIN_TOKEN` | Optional. Unset means `/admin/cleanup` answers 503 instead of running unauthenticated. |

The Android app talks to this host over HTTPS with a Firebase ID token in the `Authorization` header —
no cookies — so `CORS_ORIGINS` only needs the origins that actually make browser requests. There is no
browser client today, so a single placeholder origin is enough; it exists to keep the door shut, not
open.

## Migrations

`migrations/*.sql` are idempotent DDL and re-run on every boot — the container entrypoint is
`node dist/migrate.js && node dist/index.js`. There is no version table yet, so a deploy never needs a
separate migration step.

## Verify a deploy

```bash
curl https://api.couple-sync.yashiel.dev/health
```

If the container is restarting, read its logs first: a fail-fast boot names the exact variable or the
unreachable dependency. That is by design and is not a Coolify problem.
