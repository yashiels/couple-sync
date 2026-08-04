# CLAUDE.md

Couple Sync — an **Android** app for long-distance couples to find mutual free time. A user signs in
with Google (the same consent grants read-only calendar access), the backend pulls busy/free
intervals, computes overlap windows, and pushes them to both partners over WebSocket + FCM.

**`docs/REBUILD-SPEC.md` is the single source of truth.** `AGENTS.md` holds the full conventions and
non-negotiables. `PRD.md`, `ARCHITECTURE.md` and `docs/MANUAL_STEPS.md` are stale product history —
they describe Flutter, Firestore and device-side compute. Do not use them.

## Layout — two deployables, one repo

| | | package manager |
|---|---|---|
| Expo React Native app | repo root (`app/`, `src/`) | **npm** |
| Fastify + Postgres backend | `backend/` | **pnpm** |

Never mix the two. A `package-lock.json` is checked in at the root, a `pnpm-lock.yaml` in `backend/`.

**Stack:** Expo SDK 57 / React Native 0.86 / React 19.2 / expo-router / zustand / luxon ·
Node 22 / TypeScript strict / Fastify 5 / `pg` / `ws` / `firebase-admin` / vitest / pnpm ·
Postgres 16 · Firebase Auth + FCM only (Spark plan — no Firestore, no Cloud Functions).

## Commands

```bash
# App (repo root)
npm install
npx tsc --noEmit
npm run lint                 # eslint.config.mjs; backend/ is ignored
npm test                     # app tests only — vitest.config.ts restricts include to src/**
npx expo run:android         # a dev build is required; Expo Go cannot load the native modules

# Backend
cd backend && pnpm install
pnpm build && pnpm test      # always both, in that order — see below
pnpm typecheck

# Local stack: api + a throwaway postgres:16. FIREBASE_PROJECT_ID and
# FIREBASE_SERVICE_ACCOUNT_JSON must be exported first — boot mints a real Google token.
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --build
curl localhost:3000/health
```

`pnpm build` before `pnpm test`, always: `src/__tests__/boot-esm.test.ts` imports the **built** output
to catch CJS/ESM interop breakage, and silently skips when `dist/` is absent. Set
`TEST_DATABASE_URL` to run the 7 migration tests against a real Postgres; without it they skip.

CI (`.github/workflows/ci.yml`) runs exactly the above on every PR — both jobs, tests included.
There is no lint script in `backend/`. Deployment is a git push; Coolify builds `backend/Dockerfile`.

## Architecture rules that are easy to get backwards

- **The backend computes overlap. The device does not.** The engine is a pure function at
  `backend/src/overlap/` (135 tests); `overlapService.ts` is its only caller. Any client-side
  interval algebra beyond positioning an already-expanded interval on the week grid is a defect.
- **The backend also expands recurrence.** The app has no `rrule`, so `GET /blocks` takes a `from`/`to`
  range and returns per-block `occurrences`. A view must never read `recurrence_rule` directly.
- **The wire shape is the row shape.** Postgres rows go out `snake_case` with no DTO mapping layer.
  The one exception is `OverlapWindow`, the engine's computed type, which stays `camelCase`.
- **The app imports wire types from the backend, type-only:**
  `import type { UserRow } from '../backend/src/wire'`. One definition, nothing to drift.
- **UTC epoch milliseconds** everywhere — `BIGINT`, `number`, integers on the wire. The sole exception
  is `freeBusy.query`, which needs RFC3339. **IANA timezone IDs**, never offsets or abbreviations.

## Standing decisions (REBUILD-SPEC §0 — do not relitigate)

- Android only, Google sign-in only. No iOS build, no Apple Sign-In, no email/password, no anonymous.
- Signing in with Google *is* connecting the calendar — no connect screen, no Settings toggle. But
  never assume the scope was granted: `sync()` returns `'scope-missing'`, surfaced as one inline row.
- Google Calendar is **freebusy-only**. `freeBusy.query`, never `events.list`. Titles are never
  requested, stored, logged, or displayed.
- `visibility: 'onlyMe'` is enforced server-side: the block shapes the overlap, its `title` and
  `category` never reach the partner.
- Min window is 30 minutes, hard-coded. The duration filter is display-only.
- Recurrence is anchored to `block.timezone`, not expanded as UTC. `ALGO_VERSION = 1`.
- Fail fast at boot on a missing/invalid Firebase credential, an unreachable database, or an unset
  `CORS_ORIGINS` (`*` is refused). A container must never look healthy while returning 401.
- Verify the Firebase ID token on every REST and WS path; every couple-scoped path also calls
  `assertMember`. A non-member and a non-existent couple both get **403**, never 404.

## Style and commits

Ponytail mode: the minimum code that works. No abstraction with a single call site, no config for a
value that never changes. Where a shortcut has a known ceiling, one comment names it and the upgrade
path.

`<type>(<scope>): <message>` — e.g. `feat(backend): add invite redeem transaction`. Never
`git commit -am`; it silently skips new files. Name the paths.
