# Couple Sync — Agent Guide

Conventions for any agent working in this repo. **Read `docs/REBUILD-SPEC.md` before writing code** —
it is the single source of truth for behaviour. `PRD.md`, `ARCHITECTURE.md`, `RESEARCH.md`,
`BACKLOG.md` and `docs/MANUAL_STEPS.md` are retained for product history only and are **stale** on
stack, data model, and architecture (they describe Flutter, Firestore, and device-side compute). Do
not follow them.

## Overview

Couple Sync — an **Android** app for long-distance couples to find mutual free time. A user signs in
with Google (the same consent grants read-only calendar access); the backend pulls busy/free
intervals, computes overlap windows, and pushes them to both partners over WebSocket + FCM.

**Stack:** Expo SDK 57 / React Native 0.86 / React 19.2 / expo-router / zustand / luxon ·
Node 22 / TypeScript strict / Fastify 5 / `pg` / `ws` / `firebase-admin` / vitest ·
Postgres 16 · Firebase Auth + FCM only (Spark plan — no Firestore, no Cloud Functions).

Three deployables in one repo — **never mix their package managers:**

| Deployable | Location | Package manager | Lockfile |
|---|---|---|---|
| Expo React Native app | repo root (`app/`, `src/`) | **npm** | `package-lock.json` |
| Fastify + Postgres backend | `backend/` | **pnpm** (`pnpm@10.26.0`) | `backend/pnpm-lock.yaml` |
| Cloudflare Pages 1-pager | `site/` | **pnpm** (`pnpm@10.26.0`) | `site/pnpm-lock.yaml` |

## Build & Test

```bash
# App (repo root — npm)
npm install
npx tsc --noEmit
npm run lint                 # eslint.config.mjs; backend/** is ignored (no backend lint script — do not add one)
npm test                     # app tests only — vitest.config.ts restricts include to src/**
npx expo run:android         # a dev build is required; Expo Go cannot load the native modules

# Backend (backend/ — pnpm, never npm/yarn)
cd backend && pnpm install
pnpm build && pnpm test      # ALWAYS both, in this order — see Gotchas
pnpm typecheck

# Local stack: api + a throwaway postgres:16. Populate backend/.env first (see Security).
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --build
curl localhost:3000/health
```

`.github/workflows/ci.yml` gates every PR in two jobs (backend build+test, app typecheck+lint+test+
prebuild) and runs exactly the commands above. A locally-skipped test is a red pipeline.

## Architecture rules that are easy to get backwards

- **The backend computes overlap. The device does not.** The engine is a pure function at
  `backend/src/overlap/` (135 tests); `overlapService.ts` is its only caller. Any client-side interval
  algebra beyond positioning an already-expanded interval on the week grid is a defect.
- **The backend also expands recurrence.** The app has no `rrule`, so `GET /blocks` takes a `from`/`to`
  range and returns per-block `occurrences`. A view must never read `recurrence_rule` directly.
- **The wire shape is the row shape.** Postgres rows go out `snake_case` with no DTO mapping layer. The
  one exception is `OverlapWindow`, the engine's computed type, which stays `camelCase`.
- **The app imports wire types from the backend, type-only:**
  `import type { UserRow } from '../backend/src/wire'`. Engine types come from `overlap/types.js`
  (zero imports), never `overlap/index.js` (which reaches `rrule`).
- **Two different Google tokens.** The Firebase ID token authorizes *our* backend. The Calendar API
  needs `GoogleSignin.getTokens().accessToken`. They are not interchangeable.
- **UTC epoch milliseconds** everywhere — `BIGINT` in Postgres, `number` in TS, integers on the wire.
  The sole exception is `freeBusy.query`, which needs RFC3339 `timeMin`/`timeMax`.
- **IANA timezone IDs**, never abbreviations or offsets. `users.timezone` is nullable until onboarding
  confirms it — the router guard depends on that. Recurrence anchors to `block.timezone`. `ALGO_VERSION = 1`.

## Non-negotiables (REBUILD-SPEC §0 — do not relitigate)

- Android + Google sign-in only. No iOS build, no Apple Sign-In, no email/password, no anonymous auth.
- Signing in with Google *is* connecting the calendar — no connect screen. But never assume the scope
  was granted: `sync()` returns `'scope-missing'`, surfaced as one inline row.
- **Google Calendar freebusy only.** `freeBusy.query`, never `events.list`. An event title is never
  requested, stored, logged, or displayed.
- **`visibility: 'onlyMe'`** blocks shape the overlap result, but their `title`/`category` never reach
  the partner. This was once shipped as a no-op — it must stay enforced server-side.
- **Verify the Firebase ID token on every REST and WS path.** Every couple-scoped path also calls
  `assertMember`. A non-member and a non-existent couple both get **403**, never 404.
- Min window is 30 minutes, hard-coded. The duration filter is display-only.
- **Fail fast at boot** on a missing/invalid Firebase credential, an unreachable database, or an unset
  `CORS_ORIGINS` (`*` is refused). A container must never report healthy while returning 401.

## Layout

| Path | What |
|---|---|
| `src/` | app code — `api.ts`, `auth.ts`, `calendar.ts`, `ws.ts`, `store.ts` (zustand), `components/` |
| `app/` | expo-router screens |
| `app.config.ts` | Expo config; points at the real (gitignored) `google-services.json` on purpose |
| `backend/src/overlap/` | pure overlap engine (`types.ts` has zero imports; `index.ts` reaches `rrule`) |
| `backend/src/routes/` | Fastify routes; `wire.ts` = shared wire types; `firebase.ts` = Admin SDK boot |
| `backend/src/migrations/` | idempotent DDL, re-run on every boot (no version table) |
| `site/` | Cloudflare Pages 1-pager + the Pages Function that splits page-vs-API on the shared hostname |
| `docs/deployment/deploy.md` | the live deployment doc (backend + site) |
| `e2e/` | maestro flows + `seed-partner.mjs` |

## Gotchas

- **Adding a backend route? Update the site split too.** `site/functions/_middleware.ts` decides
  page-vs-API by path on the shared hostname; a new Fastify route that isn't added to `API_EXACT` /
  `API_PREFIX` serves the static 404 page to the app instead of proxying. The routing test
  (`site/functions/_middleware.test.ts`, run by root `npm test`) enumerates every live route —
  add it there.
- **`pnpm build` before `pnpm test`, always:** `backend/src/__tests__/boot-esm.test.ts` imports the
  **built** output to catch CJS/ESM interop breakage and silently skips when `dist/` is absent.
- **`TEST_DATABASE_URL` gates the 7 migration tests** — unset, they skip (a typo'd column name goes
  invisible). CI sets it; set it locally to actually exercise them.
- **CI installs no backend deps for the app job** — `tsconfig.json` pulls in `backend/src/wire.ts`, but
  its type-only graph reaches nothing that needs installing.
- **`docker-compose.override.yml` is local-dev only** — it publishes port 3000 and starts a throwaway
  trust-auth Postgres with no volume. Never deploy it.

## Security

- **Secrets live in 1Password**, vault `Nexion`, item `couple-sync-env` (fields = env-var names).
  Resolve env files with `op inject -i backend/.env.tpl -o backend/.env` (and root `.env.tpl` → `.env`).
  Templates hold `op://` references, never values.
- **Required backend env** (all fail-fast at boot): `DATABASE_URL`, `FIREBASE_PROJECT_ID`,
  `FIREBASE_SERVICE_ACCOUNT_JSON` (the whole key as one JSON string), `CORS_ORIGINS` (no default, `*`
  rejected). Optional: `ADMIN_TOKEN`, `PORT` (default 3000). App env: `API_BASE_URL`, `GOOGLE_WEB_CLIENT_ID`.
- **GCP project `couple-sync-personal`** (#1017647089243, personal account). Billing NOT linked → $0.
  Both Firebase API keys are restricted to package `dev.yashiel.couplesync` + release/debug SHA-1.
- **Never commit** the real `google-services.json` (gitignored; CI copies the placeholder), the release
  keystore, a service-account key, or any `.env`. The service-account JSON is the only true secret.
- **Hosting (live).** `https://couple-sync.yashiel.dev` is the one public host (WS: `wss://…/sync`) and
  the app's unchanged `API_BASE_URL`. It resolves to the **Cloudflare Pages** project `couple-sync`
  (`couple-sync-7hy.pages.dev`); the Pages Function serves static pages and proxies API/WS paths to the
  backend tunnel at **`couple-sync-tunnel.yashiel.dev`** — set as the Pages prod env `API_BASE_URL`. Both
  hostnames live in the `yashiel.dev` Cloudflare zone. Do not point the app at the tunnel host directly.
- **Two Cloudflare tokens.** CI's `CF_PAGES_API_TOKEN` (1Password `api.cloudflare-pages-ci`) is
  Pages:Edit-only and CANNOT touch DNS. DNS/tunnel/Pages-admin changes need the broad account token,
  1Password Agents vault item `api.cloudflare.apex`. A Pages custom-domain cutover has a ~1-minute
  HTTP-522 window while the edge cert provisions — not zero-downtime.

## Do not

- Move overlap computation to the device, or add client-side interval algebra / recurrence expansion.
- Add a DTO mapping layer, an ORM, or a shared types package.
- Add iOS builds, Apple Sign-In, email/password, or anonymous auth.
- Add a `backend/` lint script, or a `pre-commit`/`pre-push` hook (CI gates the same things and cannot
  be `--no-verify`'d).
- Use `git commit -am` — it silently skips new files. Name the paths.
- Report a step as passing without running it. Device steps need real credentials; if they are
  missing, say so. **End a task by stating what you did NOT do.**

## Style

Ponytail mode: the minimum code that works. No abstraction with a single call site, no config for a
value that never changes, no speculative interfaces. Where a shortcut has a known ceiling, leave one
comment naming the ceiling and the upgrade path. Boring beats clever. Tests are real ones that fail
when the logic breaks — the overlap engine and the auth/membership guards get thorough coverage; UI
does not get a test per component.

## Commits

`<type>(<scope>): <message> #<issue>` — e.g. `feat(backend): add invite redeem transaction #42`. The
commit-msg hook (Yash's Conventional Commit policy) **requires** the `#<issue>` reference (same-repo
`#123` or cross-repo `owner/repo#123`); a subject without it is rejected. Allowed types: `feat`, `fix`,
`docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.

## Related Repositories

Self-contained monorepo — the app and its backend both live here; there are no sibling **code** repos
to read. Deploy target is a self-hosted Docker host via a CI-published GHCR image + Cloudflare Tunnel
(see `docs/deployment/deploy.md`); shared
agent tooling lives in `yashiels/agent-scripts` (skills/scripts, not a runtime dependency).

<!-- Human-only notes (stripped before the model sees this file):
     - Being prepared to go public: tracking issue #68, branch chore/prep-public.
     - Human-readable secret map: 1Password Nexion → "Couple Sync — GCP/Firebase reference". -->
