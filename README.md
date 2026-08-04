# Couple Sync

An Android app for long-distance couples to find mutual free time. You sign in with Google — the same
consent grants read-only calendar access — and the backend pulls your busy/free intervals, merges them
with any manual blocks you add, computes the windows where you are *both* free, and pushes them to
both partners in real time.

Privacy: the Google Calendar integration is **freebusy-only**. Event titles are never requested,
stored, logged, or displayed.

## Layout

Two deployables in one repo. Do not mix the package managers.

| | | |
|---|---|---|
| Expo React Native app | repo root (`app/`, `src/`) | **npm** |
| Fastify + Postgres backend | `backend/` | **pnpm** |

The app is a thin client: it renders windows the server computed and holds no interval math. See
`docs/REBUILD-SPEC.md` for the spec and `AGENTS.md` for the conventions.

## Run the backend

Export a real Firebase service account first (see [Setup](#setup-humans-only) — the container proves
the credential at boot and exits rather than serving 401s), then, from the repo root:

```bash
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --build
curl localhost:3000/health
```

That brings up the API on port 3000 plus a throwaway `postgres:16` (trust auth, no volume). Tear it
down with `... down -v`. Migrations run on every boot. Details in `backend/README.md`.

## Run the app

```bash
npm install
cp .env.example .env      # then fill in both values
npx expo run:android      # builds and installs a dev build on the emulator/device
npm start                 # subsequent runs: just the bundler
```

A **development build** is required — `@react-native-firebase/*` ships native modules and remote push
needs a real build, so Expo Go cannot load this app. iOS is deliberately out of scope for v1.

## Environment variables

**App** — `.env` at the repo root, read by `app.config.ts`. Neither has a default; a missing value
fails loudly rather than pointing at localhost or hanging a sign-in.

| Variable | Notes |
|---|---|
| `API_BASE_URL` | No trailing slash. An Android emulator reaches your host at `10.0.2.2`, never `localhost`. |
| `GOOGLE_WEB_CLIENT_ID` | The **Web** OAuth client id, not the Android one. |

**Backend** — from the shell or the Coolify app environment.

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes | Boot fails if unreachable. |
| `FIREBASE_PROJECT_ID` | yes | Must equal the service account's `project_id`. |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | yes | The whole key file as one JSON string. |
| `CORS_ORIGINS` | yes | Comma-separated allowlist. No default, and `*` is refused. |
| `ADMIN_TOKEN` | no | Unset means `/admin/cleanup` answers 503 instead of running unauthenticated. |
| `PORT` | no | Defaults to `3000`. |

## Setup (humans only)

None of this can be scripted, and nearly all of it fails *silently*. The app cannot run on a device
until every row is done.

| Step | Symptom when missing |
|---|---|
| Download `google-services.json` from the Firebase console to the repo root (gitignored) | prebuild throws, or Firebase no-ops at runtime |
| Enable the **Google** sign-in provider in Firebase Auth — it is off by default | sign-in rejected with an opaque error |
| Configure the OAuth consent screen and add your accounts as **test users** while the app is unpublished | the consent screen refuses the account |
| Put the **Web** OAuth client id in `GOOGLE_WEB_CLIENT_ID` (`@react-native-google-signin` needs the Web id as `webClientId`, not the Android one) | sign-in never resolves |
| Register **both** the debug and the release SHA-1 fingerprints in Firebase | sign-in fails with no useful error — the single most common setup mistake |
| Enable the Google Calendar API in the GCP project | 403 on every sync |
| Use an emulator or device **with Google Play services** | Google Sign-In and FCM unavailable |
| Sign in with a real Google account that has actual calendar events | an empty but "successful" sync |
| For pairing: a **second** Google account **and** a second device or emulator — two live sessions are needed at once | pairing and every two-sided path untestable |

## Verify

```bash
npm run lint && npx tsc --noEmit && npm test
cd backend && pnpm build && pnpm test
```

CI (`.github/workflows/ci.yml`) runs both of those on every PR, plus an Android prebuild to catch
config-plugin breakage. Deployment is a git push: Coolify builds `backend/Dockerfile`
(`docs/deployment/coolify.md`).
