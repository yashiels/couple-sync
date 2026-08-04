# AGENTS.md

Conventions for agents working in this repo. **Read `docs/REBUILD-SPEC.md` before writing code** — it
is the single source of truth. `PRD.md` and `ARCHITECTURE.md` are retained for product history only
and are stale on stack, data model, and architecture.

## What this is

Couple Sync — an Android app for long-distance couples to find mutual free time. A user signs in with
Google, which also grants read-only calendar access; the backend pulls busy/free intervals, computes
overlap windows, and pushes them to both partners.

Two deployables in one repo:

| | |
|---|---|
| Expo React Native app | repo root (`app/`, `src/`) — **npm** |
| Fastify + Postgres backend | `backend/` — **pnpm** |

## Architecture rules that are easy to get backwards

- **The backend computes overlap. The device does not.** Earlier versions of this project did the
  opposite and older docs still say so — they are wrong. The overlap engine is a pure function at
  `backend/src/overlap/` with 135 tests; `overlapService.ts` is its only caller.
- **The backend also expands recurrence.** The app has no `rrule` dependency, so `GET /blocks` returns
  per-block `occurrences` for a requested `from`/`to` range. A calendar view must never read
  `recurrence_rule` directly.
- **The wire shape is the row shape.** Postgres rows go out in `snake_case` with no DTO mapping layer.
  The one exception is `OverlapWindow`, which is the engine's computed type and stays `camelCase`.
- **The app imports its wire types from the backend, type-only:**
  `import type { UserRow } from '../backend/src/wire'`. Engine types come from `overlap/types.js`,
  never `overlap/index.js` — `types.ts` has zero imports, while `index.ts` reaches `rrule`.

## Commands

```bash
# Backend (pnpm — never npm/yarn)
cd backend && pnpm install
pnpm build          # tsc
pnpm test           # vitest
pnpm typecheck      # tsc --noEmit

# Local stack (api + bundled postgres)
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --build
curl localhost:3000/health

# App (npm — a package-lock.json is checked in)
npm install
npx tsc --noEmit
npm run lint
npm test            # app tests only; the root vitest config excludes backend/
npx expo run:android
```

There is no ESLint config in `backend/` — do not run a lint script there. Deployment is a git push;
Coolify builds `backend/Dockerfile`.

## Non-negotiables

- **Google Calendar freebusy only.** `freeBusy.query`, never `events.list`. An event title is never
  requested, stored, logged, or displayed.
- **Verify the Firebase ID token on every REST and WS path.** Every couple-scoped path also calls
  `assertMember`. A non-member and a non-existent couple both get **403**, never 404.
- **`visibility: 'onlyMe'`** blocks shape the overlap result, but their `title` and `category` never
  reach the partner. A previous version shipped this control as a no-op.
- **Two different Google tokens.** The Firebase ID token authorizes *our* backend. The Calendar API
  needs `GoogleSignin.getTokens().accessToken`. They are not interchangeable.
- **UTC epoch milliseconds** everywhere — `BIGINT` in Postgres, `number` in TS, integers on the wire.
  The single exception is `freeBusy.query`, which requires RFC3339 `timeMin`/`timeMax`.
- **IANA timezone IDs**, never abbreviations or offsets. `users.timezone` is nullable until onboarding
  confirms it — the router guard depends on that.
- **Fail fast at boot** on a missing/invalid Firebase credential, an unreachable database, or an unset
  `CORS_ORIGINS`. A container must never report healthy while returning 401 for everything.
- **Firebase Spark plan**: Auth + FCM only. No Firestore, no Cloud Functions, no Blaze feature.

## Do not

- Move overlap computation to the device.
- Add client-side interval algebra or recurrence expansion.
- Add Apple Sign-In, iOS builds, email/password, or anonymous auth. Android + Google only for now.
- Add a DTO mapping layer, an ORM, or a shared types package.
- Use `git commit -am` — it silently skips new files. Name the paths.
- Report a step as passing without running it. Device steps need real credentials; if they are
  missing, say so.

## Style

Ponytail mode: the minimum code that works. No abstraction with a single call site, no config for a
value that never changes, no speculative interfaces. Where a shortcut has a known ceiling, leave one
comment naming the ceiling and the upgrade path. Boring beats clever.

Tests: real ones that fail when the logic breaks. The overlap engine and the auth/membership guards
get thorough coverage. UI does not get a test per component.

## Commits

`<type>(<scope>): <message>` — e.g. `feat(backend): add invite redeem transaction`.
