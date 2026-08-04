# Couple Sync React Native Rebuild — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the deleted Flutter app with an Expo React Native app talking to a Fastify + Postgres backend that runs in Docker, computes overlap windows server-side, and fans them out over WebSocket + FCM.

**Architecture:** One repo, two deployables. The Expo app at the repo root is a thin client — it renders windows the server computed and holds no interval math. `backend/` is a single Fastify process serving REST + a WebSocket, with Postgres for storage; overlap is a pure function (`backend/src/overlap/`, already built and tested) called inline on any write that could change the result. Firebase provides Auth (ID token verification) and FCM only — no Firestore, no Cloud Functions.

**Tech Stack:** Expo SDK 57 / React Native 0.86 / React 19.2 / expo-router / zustand / luxon · Node 22 / TypeScript strict / Fastify 5 / `pg` / `ws` / `firebase-admin` / vitest / pnpm · Postgres 16 · Docker + Docker Compose · Firebase Auth + FCM (Spark plan)

**Specification:** `docs/REBUILD-SPEC.md` (moved there by Task 1). Sections are cited per task as **§n**. The spec is authoritative; `PRD.md` and `ARCHITECTURE.md` are stale and must not be used as a source of truth.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Timestamps** are UTC epoch milliseconds everywhere: `BIGINT` in Postgres, `number` in TypeScript, plain integers on the wire. Never an ISO string, never a `Date` in a payload.
- **The wire shape is the row shape.** Database rows go out over REST and WS in `snake_case`, exactly as Postgres returns them. There is no DTO mapping layer, because renaming `couple_id` to `coupleId` buys nothing and costs a mapper per entity plus a drift-detection test. The two transforms that carry real logic — scrubbing an `onlyMe` block and stripping `fcm_tokens` — live in `backend/src/wire.ts` and are the only functions between a row and a response. The one exception is `OverlapWindow`, which is the engine's own computed type and stays `camelCase` (`startUtc`, `durationMinutes`) because it is not a row.
- **The app imports its wire types directly from the backend, type-only:** `import type { UserRow } from '../backend/src/wire'`. One repo, one definition, no hand-copy and no contract test to police the copy. `import type` is erased before Metro sees it, so no backend code is ever bundled — and an accidental *value* import fails loudly at bundle time when Metro tries to resolve `pg`.
- **Timezones** are IANA IDs (`America/New_York`, `Africa/Johannesburg`). Never an abbreviation, never a UTC offset.
- **Package manager** is `pnpm` in `backend/` (declared via `packageManager`) and `npm` at the repo root (an `npm`-generated `package-lock.json` already exists there). Never mix.
- **TypeScript** is `strict` in both projects. `backend/tsconfig.json` additionally sets `noUncheckedIndexedAccess` — the existing engine code depends on it, do not relax it.
- **Backend module system** is ESM. Relative imports carry a `.js` extension (`import { query } from './db.js'`).
- **Overlap is computed server-side only.** The client never computes, hashes, or publishes windows. Any client-side interval algebra beyond positioning a block on the week grid is a defect.
- **Google Calendar is freebusy-only.** Scope is exactly `https://www.googleapis.com/auth/calendar.readonly`; the only API call is `freeBusy.query`. Event titles are never requested, stored, logged, or displayed.
- **Every REST and WebSocket path verifies the Firebase ID token.** Every couple-scoped path additionally calls `assertMember`. A non-member and a non-existent couple both return **403** — never 404, so existence is never leaked.
- **`CORS_ORIGINS` must not default to `*`.** Boot fails when it is unset.
- **Boot fails loudly** on missing/invalid Firebase credentials and on an unreachable database. The previous build only `console.warn`ed, so a misconfigured container reported healthy while returning 401 for every request. Do not reproduce that.
- **The admin token** is compared with `crypto.timingSafeEqual`; admin routes return 503 when it is unset.
- **`visibility: 'onlyMe'`** blocks shape the overlap result but their `title` and `category` never reach the partner. The previous build shipped this control as a no-op.
- **Firebase Spark plan.** Auth + FCM only. No Blaze feature, no Firestore, no Cloud Functions, no Cloud Storage.
- **Migrations are idempotent DDL** (`CREATE TABLE IF NOT EXISTS`, `ALTER TABLE ... IF NOT EXISTS`). There is no `schema_migrations` version table yet and `migrate.ts` re-runs every file on every boot.
- **App identity:** display name `Couple Sync`, slug `couple-sync`, bundle/package id `money.stitch.couplesync`, URL scheme `couplesync`.
- **Commit format:** `<type>(<scope>): <message>`, e.g. `feat(backend): add invite redeem transaction`. No `Co-Authored-By: Claude` trailer.
- **Style:** ponytail mode. Minimum code that works; no abstraction with a single call site; no config for a value that never changes. Where a deliberate shortcut has a known ceiling, leave a one-line comment naming the ceiling and the upgrade path.
- **Accessibility basics are not optional** and are not what the spec deferred (it deferred the full WCAG *sweep*). Every task that ships UI owes three things, checked at that task's verify step: an `accessibilityLabel` on every icon-only control; a minimum 44×44pt touch target on every tappable element; and no state conveyed by colour alone — a late-night window, a `tentative` block, and a read-only google-sourced row each need a text or icon marker, not just a hue. These cost one prop each; retrofitting them later costs a sweep.

---

## Starting State

Verify this before Task 1. `git status` shows 313 staged deletions (the entire Flutter app and the previous backend) plus these untracked survivors:

**Keep as-is:**
- `backend/src/overlap/**` — the overlap engine, 7 source files + 6 test files, **135 passing tests**. Built to §3 including both DST axes. Do not modify it in any task except where a task explicitly says so.
- `package.json`, `package-lock.json`, `tsconfig.json`, `assets/*.png` (root) — Expo SDK 57 dependency set and app icons.
- `backend/package.json`, `backend/pnpm-lock.yaml`, `backend/tsconfig.json`, `backend/vitest.config.ts` — need the fixes in Task 1.

**Unreviewed draft — treat as a starting point, not as correct.** Written by an interrupted agent against an earlier spec revision, never compiled, never tested, never reviewed. Each task below that touches one of these files owns verifying it against the spec and rewriting whatever does not match:
- `backend/src/config.ts`, `db.ts`, `firebase.ts`, `auth.ts`, `couples.ts`, `http.ts`, `sockets.ts`, `push.ts`, `dto.ts` (replaced by `wire.ts` in Task 4), `routes/auth.ts`

**Delete — built to the abandoned device-computes design:**
- `backend/src/overlap.ts` (`validateWindows`, the `computedBy` forgery gate — the client no longer publishes windows, so this whole module is obsolete and its filename collides confusingly with `src/overlap/`)
- `backend/src/sync.ts` (client→server overlap ingestion)

**Does not exist yet:** the entire Expo app (`app/`, `src/`, `app.config.ts`), all backend routes except `routes/auth.ts`, `migrate.ts`, `migrations/`, `Dockerfile`, `docker-compose*.yml`, CI workflows, `README.md`, `CLAUDE.md`.

---

## File Structure

### Backend (`backend/`)

| File | Responsibility |
|---|---|
| `src/index.ts` | Fastify bootstrap, plugin registration, `/health`, WS upgrade wiring, `listen` |
| `src/config.ts` | Read + validate env once at import; export a frozen typed object; throw on anything missing |
| `src/db.ts` | `pg.Pool` singleton, `query`, `withTx`, `assertReachable` |
| `src/migrate.ts` | Apply every file in `migrations/` in filename order; standalone entrypoint |
| `src/migrations/001_init.sql` | Whole schema per §2, idempotent |
| `src/firebase.ts` | `firebase-admin` init from the service-account env var; export `verifyIdToken`, `sendEach` |
| `src/auth.ts` | Extract + verify the bearer/query token; Fastify `preHandler` that sets `req.uid` |
| `src/http.ts` | `HttpError` + the Fastify error handler that maps it to a response |
| `src/couples.ts` | `assertMember`, `partnerUid` |
| `src/wire.ts` | Row interfaces (the wire shape), the `onlyMe` scrub, `fcm_tokens` stripping, the `WsMessage` union. Imported type-only by the app. |
| `src/sockets.ts` | `uid → WebSocket` registry, `sendTo`, `isOnline` |
| `src/overlap/**` | **Existing.** Pure engine. §3. |
| `src/overlapService.ts` | The only caller of `computeOverlap`: load rows → compute → dedup on `input_hash` → upsert → fan out → push |
| `src/push.ts` | FCM send + invalid-token pruning |
| `src/cron.ts` | Daily invite expiry timer + `POST /admin/cleanup` |
| `src/routes/auth.ts` | `POST /auth/verify`, `POST /auth/fcm-token` |
| `src/routes/users.ts` | `GET /users/me`, `GET /users/:uid`, `PATCH /users/:uid` |
| `src/routes/blocks.ts` | Block CRUD + `PUT /blocks/google` |
| `src/routes/overlaps.ts` | `GET /overlaps/latest` |
| `src/routes/couples.ts` | `GET /couples/:id`, `POST /couples/:id/unpair` |
| `src/routes/invites.ts` | `POST /invites`, `POST /invites/:code/redeem` |
| `src/sync.ts` | WS `/sync` handler (server→client only) |
| `src/__tests__/*.test.ts` | Route-level integration tests, `db.ts` + `firebase.ts` mocked |
| `Dockerfile` | Multi-stage Node 22, non-root, healthcheck, migrate-then-serve |
| `README.md` | Env vars, local run, deploy |

### App (repo root)

| File | Responsibility |
|---|---|
| `app.config.ts` | Expo config: identity, scheme, bundle ids, plugins |
| `app/_layout.tsx` | Root: hydrate auth + user, run the guard chain, render a splash until hydrated |
| `app/auth.tsx` | Sign-in screen |
| `app/timezone-setup.tsx` | Timezone confirm/search |
| `app/pairing.tsx` | Share / Enter tabs |
| `app/(tabs)/_layout.tsx` | Bottom tab bar |
| `app/(tabs)/index.tsx` | Home |
| `app/(tabs)/calendar.tsx` | Week view |
| `app/(tabs)/overlap.tsx` | Window list + filter |
| `app/(tabs)/blocks.tsx` | Own-block list |
| `app/(tabs)/settings.tsx` | Settings |
| `app/block-form.tsx` | Create/edit block (modal) |
| `src/api.ts` | Typed REST client; injects the bearer token; maps errors |
| `src/ws.ts` | WS client with reconnect backoff; dispatches into the store |
| `src/auth.ts` | Firebase Auth: Google + Apple sign-in, sign-out, token access |
| `src/store.ts` | zustand store: `user`, `couple`, `blocks`, `windows`, `hydrated`, actions |
| `src/theme.ts` | Colors, spacing, type scale; light + dark |
| `src/time.ts` | luxon display helpers: format a window, a clock, a block's grid position |
| `src/calendar.ts` | Google freebusy fetch → block payloads |
| `src/notifications.ts` | FCM permission, token registration, tap routing |

---

## Task Sequencing

Tasks 1–4 must land in order. Task 4 produces `backend/src/wire.ts`, which is the only thing Track 2
needs from Track 1 — so once Task 4 lands, the two tracks are independent and run in parallel. They
meet at Task 17.

```
Track 1 (backend):  1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9
Track 2 (app):               └────→ 10 → 11 → 12 → 13 → 14 → 15 → 16
                                                                    ↓
                                                          17 (CI + docs)
```

Track 2 codes against the type declarations in `wire.ts`, not against a running server, so it does
not wait for Tasks 5–9. The first task that genuinely needs a live backend is Task 12 Step 5
(walking the sign-in flow on a simulator); if Track 1 is behind at that point, run Track 2's
verification steps against the local compose stack once Task 9 lands.

---

## Task 1: Repo hygiene, project config, engine tests runnable

**Files:**
- Delete: `backend/src/overlap.ts`, `backend/src/sync.ts`
- Move: the spec from the scratchpad to `docs/REBUILD-SPEC.md`
- Modify: `backend/vitest.config.ts`, `backend/tsconfig.json`, `backend/package.json`, `package.json` (root)

**Interfaces:**
- Consumes: nothing.
- Produces: `pnpm test` and `pnpm build` both work in `backend/`; `docs/REBUILD-SPEC.md` is the in-repo spec path every later task reads.

- [ ] **Step 1: Move the spec into the repo**

```bash
cd /Users/yashielsookdeo/Developer/yashiels/couple-sync/.worktrees/chore-couple-sync-react-native
cp "/private/tmp/claude-501/-Users-yashielsookdeo-Developer-yashiels-couple-sync--worktrees-chore-couple-sync-react-native/888716e0-e56e-4c0c-8bdb-0ae0e2ba0874/scratchpad/REBUILD-SPEC.md" docs/REBUILD-SPEC.md
```

Then apply the two spec corrections listed in the Self-Review section at the bottom of this plan (the DST wording in §3 step 8, and the `durationMinutes` note).

- [ ] **Step 2: Delete the two obsolete modules**

```bash
rm backend/src/overlap.ts backend/src/sync.ts
```

`overlap.ts` implemented `validateWindows` and a `computedBy === socketUid` forgery gate for client-published windows. The client no longer publishes windows (§0.1, §6), so both are dead. Its name also collides with the `src/overlap/` engine directory.

- [ ] **Step 3: Fix `backend/vitest.config.ts` so the engine's colocated tests are collected**

The current `include` is `['tests/**/*.test.ts']` and it references a `setupFiles: ['tests/setup.ts']` that does not exist, so the suite currently collects **zero** files.

```ts
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts', 'src/__tests__/**/*.test.ts'],
    environment: 'node',
  },
})
```

- [ ] **Step 4: Exclude tests from the build in `backend/tsconfig.json`**

Without this, `pnpm build` emits `dist/overlap/*.test.js` into the production image.

```jsonc
{
  // keep every existing compilerOptions value, including noUncheckedIndexedAccess
  "exclude": ["node_modules", "dist", "src/**/*.test.ts"]
}
```

- [ ] **Step 5: Add the engine's real dependencies to `backend/package.json`**

The engine already imports these; a previous agent hand-copied them into `node_modules`, so the next `pnpm install` would wipe them and break 135 tests.

```jsonc
"dependencies": {
  "luxon": "^3.7.2",
  "rrule": "^2.8.1"
},
"devDependencies": {
  "@types/luxon": "^3.7.1"
}
```

Also confirm `"packageManager": "pnpm@<version>"`, `"type": "module"`, and scripts `build` (`tsc`), `dev`, `start`, `migrate`, `test` (`vitest run`) are all present; add whichever are missing.

- [ ] **Step 6: Remove `rrule` from the root `package.json`**

The client does no recurrence expansion (§0.1). `luxon` stays — the client needs it for display formatting and grid positioning.

- [ ] **Step 7: Install and prove the engine suite runs green**

```bash
cd backend && pnpm install && pnpm build && pnpm test
```

Expected: `tsc` exits 0; vitest reports **135 passed** across 6 files. If the count is lower, `include` is still wrong. If any test fails after a clean `pnpm install`, a dependency version is wrong — fix the version, never the test.

- [ ] **Step 8: Ignore the worktree directory in the parent repo**

```bash
echo '.worktrees/' >> "$(git rev-parse --git-common-dir)/info/exclude"
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore(repo): scrap Flutter app, keep overlap engine, fix backend project config"
```

---

## Task 2: Schema, migrations, and the database layer

**Files:**
- Create: `backend/src/migrations/001_init.sql`, `backend/src/migrate.ts`
- Rewrite: `backend/src/db.ts`
- Test: `backend/src/__tests__/migrate.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```ts
  // src/db.ts
  export function getPool(): pg.Pool
  export function query<T extends pg.QueryResultRow = pg.QueryResultRow>(
    sql: string, params?: unknown[]
  ): Promise<pg.QueryResult<T>>
  /** Runs fn inside BEGIN/COMMIT; ROLLBACK + rethrow on any throw. Always releases the client. */
  export function withTx<T>(fn: (c: pg.PoolClient) => Promise<T>): Promise<T>
  /** SELECT 1. Throws on failure — called at boot so a bad DB crashes instead of reporting healthy. */
  export function assertReachable(): Promise<void>
  ```
  No `closePool` — nothing in this plan calls it. Add it alongside a graceful-shutdown handler if and
  when one is needed, not before.

  **`db.ts` must register an int8 parser at module load:**
  ```ts
  // pg returns BIGINT as a string by default, which would make every *_utc field a string
  // and quietly falsify every timestamp type in wire.ts. Epoch ms fits in a double until
  // year 287396, so Number is lossless here.
  pg.types.setTypeParser(20, Number)
  ```

- [ ] **Step 1: Write the schema, exactly per §2**

`backend/src/migrations/001_init.sql`. Every statement idempotent — `migrate.ts` re-runs every file on every boot and there is no version table.

```sql
CREATE TABLE IF NOT EXISTS couples (
  id            TEXT PRIMARY KEY,
  user_a_uid    TEXT NOT NULL,
  user_b_uid    TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  paired_at     BIGINT NOT NULL,
  created_at    BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS users (
  uid                      TEXT PRIMARY KEY,
  email                    TEXT NOT NULL,
  display_name             TEXT,
  photo_url                TEXT,
  timezone                 TEXT NOT NULL DEFAULT 'UTC',
  couple_id                TEXT REFERENCES couples(id) ON DELETE SET NULL,
  fcm_tokens               TEXT[] NOT NULL DEFAULT '{}',
  show_late_night_windows  BOOLEAN NOT NULL DEFAULT FALSE,
  notifications_enabled    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at               BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS invites (
  code            TEXT PRIMARY KEY,
  created_by_uid  TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  couple_id       TEXT REFERENCES couples(id) ON DELETE SET NULL,
  expires_at      BIGINT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','accepted','expired')),
  created_at      BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS timeblocks (
  id               TEXT PRIMARY KEY,
  couple_id        TEXT NOT NULL REFERENCES couples(id) ON DELETE CASCADE,
  user_id          TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  title            TEXT NOT NULL,
  type             TEXT NOT NULL CHECK (type IN ('busy','free','tentative')),
  category         TEXT,
  start_utc        BIGINT NOT NULL,
  end_utc          BIGINT NOT NULL,
  timezone         TEXT NOT NULL,
  recurrence_rule  TEXT,
  source           TEXT NOT NULL CHECK (source IN ('google','manual')),
  visibility       TEXT NOT NULL DEFAULT 'bothPartners'
                   CHECK (visibility IN ('bothPartners','onlyMe')),
  created_at       BIGINT NOT NULL,
  CONSTRAINT timeblocks_end_after_start CHECK (end_utc > start_utc)
);

CREATE TABLE IF NOT EXISTS overlaps_latest (
  couple_id    TEXT PRIMARY KEY REFERENCES couples(id) ON DELETE CASCADE,
  windows      JSONB NOT NULL,
  computed_at  BIGINT NOT NULL,
  input_hash   TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS timeblocks_couple_user_idx   ON timeblocks (couple_id, user_id);
CREATE INDEX IF NOT EXISTS timeblocks_couple_source_idx ON timeblocks (couple_id, source);
CREATE INDEX IF NOT EXISTS invites_status_expires_idx   ON invites (status, expires_at);
CREATE INDEX IF NOT EXISTS users_couple_idx             ON users (couple_id);
```

Note in a comment at the top of the file: no `schema_migrations` table yet, so every migration must stay idempotent; a version table is the upgrade path when the first non-idempotent change arrives.

- [ ] **Step 2: Write `migrate.ts`**

Read every `*.sql` in `src/migrations/` sorted by filename, run each in its own transaction, log each filename, exit non-zero on failure. It must work both as a library (`runMigrations()`) and as a standalone entrypoint (`node dist/migrate.js`), because the Dockerfile calls it before the server starts.

- [ ] **Step 3: Write `db.ts` to the interface above**

`getPool` lazily constructs one `pg.Pool` from the configured connection string. `withTx` must `ROLLBACK` on throw and `release()` in a `finally`. Verify what the draft `db.ts` does today and rewrite whatever differs — in particular confirm the client is released on the error path.

- [ ] **Step 4: Write the migration test**

`backend/src/__tests__/migrate.test.ts`. This is the one suite that talks to a **real** Postgres, because mocked-`db` tests cannot catch a typo'd column name — the previous build's entire backend suite mocked `db.js` and would have passed with a broken schema.

```ts
// Skips (does not fail) when TEST_DATABASE_URL is unset, so the suite stays runnable offline.
// CI sets it against a postgres:16 service container.
const url = process.env.TEST_DATABASE_URL
describe.skipIf(!url)('migrations', () => {
  it('applies cleanly to an empty database', async () => { /* runMigrations(); assert every table exists */ })
  it('is idempotent — applying twice is a no-op', async () => { /* runMigrations() twice, no throw */ })
  it('rejects a timeblock whose end is not after its start', async () => { /* expect insert to reject */ })
  it('rejects an invalid block type / source / visibility / couple status', async () => { /* 4 CHECK assertions */ })
  it('cascades timeblocks and overlaps_latest when a couple row is deleted', async () => { /* … */ })
  it('nulls users.couple_id when the couple is deleted', async () => { /* ON DELETE SET NULL */ })
  it('returns BIGINT columns as numbers, not strings', async () => {
    // insert created_at: 1712345678000, read it back, expect typeof === 'number'
    // Without the int8 parser in db.ts this fails, and every timestamp in wire.ts is a lie.
  })
})
```

- [ ] **Step 5: Run it against a real database**

Use `trust` auth on the throwaway container so no credential appears anywhere.

```bash
docker run --rm -d --name cs-pg -e POSTGRES_HOST_AUTH_METHOD=trust -p 55432:5432 postgres:16
export TEST_DATABASE_URL='postgres://postgres@localhost:55432/postgres'
cd backend && pnpm test src/__tests__/migrate.test.ts
docker rm -f cs-pg
```

Expected: all migration tests pass, and the 135 engine tests still pass.

- [ ] **Step 6: Commit**

```bash
git add backend/src/migrations backend/src/migrate.ts backend/src/db.ts backend/src/__tests__/migrate.test.ts
git commit -m "feat(backend): add schema, migration runner, and db layer"
```

---

## Task 3: Config, Firebase, auth, and error handling — all fail-fast

**Files:**
- Rewrite: `backend/src/config.ts`, `backend/src/firebase.ts`, `backend/src/auth.ts`, `backend/src/http.ts`
- Create: `backend/src/index.ts`
- Test: `backend/src/__tests__/config.test.ts`, `backend/src/__tests__/auth.test.ts`

**Interfaces:**
- Consumes: `db.ts` from Task 2.
- Produces:
  ```ts
  // src/config.ts — validated at import time
  export const config: Readonly<{
    port: number                   // PORT, default 3000
    databaseUrl: string            // DATABASE_URL                    required
    firebaseProjectId: string      // FIREBASE_PROJECT_ID             required
    firebaseServiceAccount: object // FIREBASE_SERVICE_ACCOUNT_JSON, parsed; required
    corsOrigins: string[]          // CORS_ORIGINS, comma-separated; required, '*' rejected
    adminToken: string | null      // ADMIN_TOKEN, optional
  }>

  // src/firebase.ts
  export function verifyIdToken(token: string):
    Promise<{ uid: string; email?: string; name?: string; picture?: string }>
  export function sendEach(tokens: string[], payload: unknown):
    Promise<{ token: string; errorCode: string | null }[]>

  // src/auth.ts
  /** Fastify preHandler. 401 on a missing/invalid token. Sets req.uid. */
  export const requireAuth: preHandlerHookHandler
  /** For the WS upgrade: Authorization header first, then ?token=. Throws HttpError(401). */
  export function uidFromRequest(req: IncomingMessage): Promise<string>

  // src/http.ts
  export class HttpError extends Error { constructor(status: number, code: string, detail?: string) }
  export function registerErrorHandler(app: FastifyInstance): void
  ```
  `req.uid` is declared on `FastifyRequest` via module augmentation so every route reads it type-safely.

- [ ] **Step 1: Write the config tests first**

```ts
// src/__tests__/config.test.ts — load config via vi.resetModules with a stubbed env
it('throws when DATABASE_URL is unset')
it('throws when the firebase service account env var is unset')
it('throws when the firebase service account env var is not valid JSON')
it('throws when CORS_ORIGINS is unset')            // must NOT silently default to '*'
it('throws when CORS_ORIGINS is literally "*"')
it('parses CORS_ORIGINS into a trimmed array')
it('defaults port to 3000 and throws on a non-numeric PORT')
it('leaves adminToken null when the admin token env var is unset')
```

- [ ] **Step 2: Run them and watch them fail, then implement `config.ts`**

Validate once at import, `Object.freeze` the result, and throw an `Error` naming the offending variable. Check the draft `config.ts` and fix every deviation — the `CORS_ORIGINS` rule is the one most likely to be wrong.

- [ ] **Step 3: Implement `firebase.ts` with a hard failure on bad credentials**

`initializeApp({ credential: cert(config.firebaseServiceAccount) })` at module load. If `cert()` or the first `verifyIdToken` rejects because of the credential itself, **throw** — do not `console.warn` and continue. This is the exact footgun the previous build shipped: the container passed its healthcheck and 401'd every authenticated request.

- [ ] **Step 4: Write the auth tests, then implement `auth.ts`**

```ts
// src/__tests__/auth.test.ts — vi.mock('../firebase.js')
it('401s with no Authorization header')
it('401s on a malformed Authorization header')      // no "Bearer " prefix
it('401s when verifyIdToken rejects')
it('sets req.uid from a valid token')
it('reads the token from the Authorization header on a WS upgrade')
it('falls back to ?token= on a WS upgrade when no header is present')
it('prefers the header over ?token= when both are present')
```

- [ ] **Step 5: Implement `http.ts` and `index.ts`**

`registerErrorHandler` maps `HttpError` → `{ error: code, detail? }` at its status, and anything else → 500 with the stack logged but not returned. `index.ts`:

```ts
// order matters: a bad DB or bad credentials must crash the process, not degrade the service
await assertReachable()
const app = Fastify({ logger: true })
registerErrorHandler(app)
await app.register(cors, { origin: config.corsOrigins })
app.get('/health', async () => ({ status: 'ok', time: Date.now() }))   // no auth
// route registrations land here in Tasks 6-8
await app.listen({ port: config.port, host: '0.0.0.0' })
```

- [ ] **Step 6: Verify**

```bash
cd backend && pnpm build && pnpm test
```

Expected: tsc clean; config, auth, migration and the 135 engine tests all pass.

- [ ] **Step 7: Commit**

```bash
git commit -am "feat(backend): add fail-fast config, firebase init, auth, and error handling"
```

---

## Task 4: Membership guard, the wire module, and the socket registry

**Files:**
- Rewrite: `backend/src/couples.ts`, `backend/src/sockets.ts`
- Create: `backend/src/wire.ts` (replaces the draft `backend/src/dto.ts` — delete that file)
- Test: `backend/src/__tests__/couples.test.ts`, `backend/src/__tests__/wire.test.ts`

**Interfaces:**
- Consumes: `db.ts`, `http.ts`.
- Produces:
  ```ts
  // src/wire.ts — row shapes ARE the wire shapes. snake_case, no mapping layer.
  // The app imports these type-only: import type { UserRow } from '../backend/src/wire'
  export interface UserRow {
    uid: string; email: string
    display_name: string | null; photo_url: string | null
    timezone: string; couple_id: string | null
    show_late_night_windows: boolean; notifications_enabled: boolean
    fcm_tokens: string[]        // stripped before a partner ever sees the row
    created_at: number
  }
  export interface CoupleRow {
    id: string; user_a_uid: string; user_b_uid: string
    status: 'active' | 'inactive'; paired_at: number; created_at: number
  }
  export interface BlockRow {
    id: string; couple_id: string; user_id: string
    title: string | null; type: 'busy'|'free'|'tentative'; category: string | null
    start_utc: number; end_utc: number; timezone: string
    recurrence_rule: string | null; source: 'google'|'manual'
    visibility: 'bothPartners'|'onlyMe'; created_at: number
  }

  /** Identity when viewerUid owns the block. Otherwise, for visibility==='onlyMe',
   *  returns a copy with title and category nulled. Never drops the interval —
   *  the overlap engine needs it, the partner just must not see what it is. */
  export function scrubBlockForViewer(block: BlockRow, viewerUid: string): BlockRow
  /** Drops fcm_tokens. Every path except GET /users/me sends the result of this. */
  export function stripTokens(user: UserRow): Omit<UserRow, 'fcm_tokens'>

  // OverlapWindow stays camelCase — it is the engine's computed type, not a row.
  export type { OverlapWindow } from './overlap/index.js'

  export type WsMessage =
    | { t: 'hello';       uid: string; couple_id: string | null }
    | { t: 'block:set';   block: BlockRow }
    | { t: 'block:del';   id: string }
    | { t: 'overlap';     couple_id: string; windows: OverlapWindow[]; computed_at: number }
    | { t: 'unpair';      couple_id: string }
    | { t: 'pairing';     couple_id: string; partner_uid: string }
    | { t: 'user:update'; user: Omit<UserRow, 'fcm_tokens'> }

  // src/couples.ts
  /** Throws HttpError(403,'forbidden') when the couple is missing, inactive, or uid is not a member. */
  export function assertMember(coupleId: string, uid: string): Promise<CoupleRow>
  export function partnerUid(couple: CoupleRow, uid: string): string

  // src/sockets.ts
  export function register(uid: string, ws: WebSocket): void
  export function unregister(uid: string, ws: WebSocket): void
  export function isOnline(uid: string): boolean
  /** false when uid has no live socket. */
  export function sendTo(uid: string, msg: WsMessage): boolean
  ```

There is deliberately no `toUserRow`/`toBlockRow` mapper and no contract test. `pg` already returns
rows in this shape, and the app imports the same declarations, so there is nothing to convert and
nothing to drift. `BIGINT` is the one thing to watch: `pg` returns it as a **string** by default, so
register an int8 parser once in `db.ts` (`pg.types.setTypeParser(20, Number)`) and assert it in the
migration test — otherwise every timestamp arrives as `"1712345678000"` and the types lie.

- [ ] **Step 1: Write the membership tests first**

```ts
// src/__tests__/couples.test.ts — vi.mock('../db.js')
it('returns the couple row for user_a_uid')
it('returns the couple row for user_b_uid')
it('throws 403 for a uid that is not a member')
it('throws 403 — not 404 — for a coupleId that does not exist')   // never leak existence
it('throws 403 when the couple status is inactive')
it('partnerUid returns b for a, and a for b')
```

- [ ] **Step 2: Write the wire tests, focusing on the `onlyMe` scrub**

```ts
// src/__tests__/wire.test.ts
it('scrubBlockForViewer is identity for the block owner')
it('nulls title and category on an onlyMe block for the partner')
it('preserves start_utc, end_utc, timezone, recurrence_rule and type on a scrubbed block')
it('leaves a bothPartners block untouched for the partner')
it('does not mutate the input block')
it('stripTokens removes fcm_tokens and leaves every other field intact')
it('stripTokens does not mutate the input user')
```

The interval-preserving assertion is the important one: scrubbing must not remove the data the engine needs, or `onlyMe` blocks would stop shaping the overlap.

- [ ] **Step 3: Implement all three modules; run the tests**

Delete the draft `backend/src/dto.ts` — `wire.ts` replaces it. Fix the `import type { UserRow } from './dto.js'` in the draft `push.ts` to point at `./wire.js`.

`sockets.ts` holds a `Map<string, Set<WebSocket>>` so a user with two devices works. Comment the ceiling: in-memory, single-replica only; Redis pub/sub is the upgrade path.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(backend): add membership guard, DTO scrubbing, and socket registry"
```

---

## Task 5: The overlap service — the only caller of the engine

**Files:**
- Create: `backend/src/overlapService.ts`
- Test: `backend/src/__tests__/overlapService.test.ts`

**Interfaces:**
- Consumes: `computeOverlap`, `computeInputHash`, `ALGO_VERSION`, `Block`, `OverlapWindow` from `./overlap/index.js`; `query`, `withTx`; `assertMember`, `partnerUid`; `sendTo`, `isOnline`; `pushOverlapChanged`.
- Produces:
  ```ts
  // src/overlapService.ts
  export interface RefreshResult {
    windows: OverlapWindow[]
    computedAt: number
    changed: boolean            // false when input_hash matched the stored row
  }
  /**
   * Load both partners' blocks and prefs, compute, and upsert only when the hash changed.
   * @param triggeredBy uid whose action caused this; that user is never pushed.
   *                    null for a read-path refresh.
   * Callers: every block write, a tz/late-night PATCH, invite redeem, and GET /overlaps/latest.
   */
  export function refreshOverlap(coupleId: string, triggeredBy: string | null): Promise<RefreshResult>
  ```
  `refreshOverlap` is the whole public surface. There is no separate `readStored` — every read path
  goes through `refreshOverlap`, which already returns the stored windows unchanged when the hash
  matches. A second read-only accessor would have zero call sites.

- [ ] **Step 1: Write the service tests first**

```ts
// src/__tests__/overlapService.test.ts — vi.mock db, sockets, push; use the REAL engine
it('partitions blocks by couple.user_a_uid into blocksA and user_b_uid into blocksB')
it('passes timezoneA from user_a and timezoneB from user_b, not swapped')  // scoring anchors on A
it('includes onlyMe blocks in the engine input')       // they shape overlap even when hidden
it('skips the upsert entirely when the computed input_hash equals the stored one')
it('reports changed:false and sends no WS message and no push on an unchanged hash')
it('upserts windows, computed_at and input_hash when the hash differs')
it('sends a WS overlap message to both partners when the result changed')
it('does not push to triggeredBy even when that user is offline')
it('pushes to the partner only when the partner is offline')
it('does not push when the partner has notifications_enabled false')
it('returns an empty window list for a couple with no blocks on either side')
it('computes for a couple where only one partner has any blocks')
```

- [ ] **Step 2: Implement `refreshOverlap`**

Load in one round trip: the couple row, both user rows (`timezone`, `show_late_night_windows`, `notifications_enabled`, `fcm_tokens`), and every `timeblocks` row for the couple. Partition by `couple.user_a_uid`. Call `computeInputHash` with `now = Date.now()`, compare to the stored `input_hash`, and return early with `changed: false` on a match. Otherwise `computeOverlap`, upsert, then fan out.

Comment the ceiling above the `computeOverlap` call: it runs inline on the request thread; measured at ~90 ms for 500 recurring blocks per partner against a 500 ms budget, so a job queue is the upgrade path only if p99 write latency starts to matter.

- [ ] **Step 3: Verify**

```bash
cd backend && pnpm test
```

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(backend): add overlap service with input-hash dedup and fan-out"
```

---

## Task 6: Users, couples, and invites routes

**Files:**
- Rewrite: `backend/src/routes/auth.ts`
- Create: `backend/src/routes/users.ts`, `backend/src/routes/couples.ts`, `backend/src/routes/invites.ts`
- Modify: `backend/src/index.ts` (register the four route plugins)
- Test: `backend/src/__tests__/users.test.ts`, `backend/src/__tests__/invites.test.ts`, `backend/src/__tests__/couples.route.test.ts`

**Interfaces:**
- Consumes: everything from Tasks 3–5.
- Produces: the routes in §7 for `/auth/*`, `/users/*`, `/couples/*`, `/invites/*`. Every couple-scoped handler calls `assertMember` first.

- [ ] **Step 1: Write the invite tests first — this is the highest-risk logic in the backend**

```ts
// src/__tests__/invites.test.ts
it('POST /invites returns 201 with a 6-character code and expiresAt 48h out')
it('generates codes from an unambiguous alphabet — no O, 0, I or 1')
it('POST /invites 409s when the caller already has a couple_id')
it('redeem pairs two unpaired users and returns coupleId')
it('redeem sets couple_id on BOTH user rows and stamps the invite accepted')
it('redeem 404s on an unknown code')
it('redeem rejects an expired code and does not pair')
it('redeem rejects an already-accepted code')
it('redeem rejects self-pairing by the invite creator')
it('redeem 409s when the redeemer already has a couple')
it('redeem 409s when the inviter has since paired with someone else')
it('redeem uses SELECT ... FOR UPDATE and performs every write in one transaction')
it('redeem rolls back completely on a mid-transaction failure — no orphan couple row')
it('redeem triggers refreshOverlap and a pairing WS message to the inviter')
```

- [ ] **Step 2: Implement `invites.ts`**

The redeem handler is a single `withTx`: `SELECT ... FOR UPDATE` the invite, then both user rows, run every check from §4, insert the couple, stamp the invite, update both users, `COMMIT`. Only after the commit: `refreshOverlap(coupleId, uid)` and a best-effort `sendTo(inviterUid, { t: 'pairing', ... })`.

- [ ] **Step 3: Write the users tests, then implement `users.ts`**

```ts
// src/__tests__/users.test.ts
it('GET /users/me includes fcm_tokens')
it('GET /users/:uid returns the partner without fcm_tokens')
it('GET /users/:uid 403s for a uid that is neither self nor partner')
it('PATCH /users/:uid 403s when the target is not the caller')
it('PATCH accepts timezone, show_late_night_windows, notifications_enabled and display_name')
it('PATCH rejects any other field, including couple_id, email and fcm_tokens')
it('PATCH rejects an invalid IANA timezone')
it('PATCH triggers refreshOverlap when timezone changed')
it('PATCH triggers refreshOverlap when show_late_night_windows changed')
it('PATCH does NOT trigger refreshOverlap when only display_name changed')
it('PATCH broadcasts user:update to the partner with fcm_tokens stripped')
```

- [ ] **Step 4: Write the couples tests, then implement `couples.ts`**

```ts
// src/__tests__/couples.route.test.ts
it('GET /couples/:id returns the couple for a member')
it('GET /couples/:id 403s for a non-member and for a non-existent id alike')
it('unpair sets status inactive and nulls couple_id on both users')
it('unpair deletes every timeblock for the couple')
it('unpair deletes the overlaps_latest row')
it('unpair broadcasts unpair to both partners')
it('unpair 403s for a non-member')
it('unpair does all of it in one transaction')
```

- [ ] **Step 5: Rewrite `routes/auth.ts`**

`POST /auth/verify` upserts from the decoded token (`uid`, `email`, `name`, `picture`) — on conflict, refresh `email`/`display_name`/`photo_url` but never overwrite `timezone`, `couple_id` or the preference columns — and returns the full row (this is the caller's own row, so `fcm_tokens` stays). `POST /auth/fcm-token` appends with dedup so a repeat is a no-op. Add tests: a first-time sign-in creates the row; a repeat sign-in does not reset the timezone; a repeated FCM token does not duplicate.

- [ ] **Step 6: Verify and commit**

```bash
cd backend && pnpm build && pnpm test
git commit -am "feat(backend): add auth, users, couples and invites routes"
```

---

## Task 7: Blocks routes, `onlyMe` enforcement, and Google batch replace

**Files:**
- Create: `backend/src/routes/blocks.ts`, `backend/src/routes/overlaps.ts`
- Modify: `backend/src/index.ts`
- Test: `backend/src/__tests__/blocks.test.ts`, `backend/src/__tests__/overlaps.test.ts`

**Interfaces:**
- Consumes: Tasks 3–5.
- Produces: the `/blocks*` and `/overlaps/latest` routes in §7. Every write ends with `refreshOverlap(coupleId, req.uid)` and a `block:set`/`block:del` fan-out.

- [ ] **Step 1: Write the block tests first**

```ts
// src/__tests__/blocks.test.ts
it('GET /blocks returns both partners blocks for a member')
it('GET /blocks 403s for a non-member')
it('GET /blocks nulls title and category on the partners onlyMe blocks')
it('GET /blocks keeps title and category on the callers own onlyMe blocks')
it('POST /blocks 400s on an empty title')
it('POST /blocks 400s when end_utc <= start_utc')
it('POST /blocks 400s on an invalid IANA timezone')
it('POST /blocks 400s on an unparseable recurrence rule')
it('POST /blocks 400s on an unsupported RRULE FREQ')      // only DAILY/WEEKLY/MONTHLY/YEARLY
it('POST /blocks forces user_id to the caller, ignoring any user_id in the body')
it('POST /blocks forces source to manual, ignoring any source in the body')
it('POST /blocks triggers refreshOverlap and broadcasts block:set')
it('PATCH /blocks/:id 403s when the caller does not own the block')
it('PATCH /blocks/:id 403s on a google-sourced block')     // read-only
it('PATCH /blocks/:id triggers refreshOverlap and broadcasts block:set')
it('DELETE /blocks/:id 403s when the caller does not own the block')
it('DELETE /blocks/:id triggers refreshOverlap and broadcasts block:del')
it('PUT /blocks/google replaces only the callers google blocks, leaving manual blocks alone')
it('PUT /blocks/google leaves the partners google blocks alone')
it('PUT /blocks/google is atomic — a mid-insert failure leaves the old set intact')
it('PUT /blocks/google forces type=busy, source=google and a placeholder title on every entry')
it('PUT /blocks/google rejects a payload carrying a title')  // no event titles, ever
it('PUT /blocks/google triggers exactly one refreshOverlap for the whole batch')
```

That second-to-last test is a hard privacy boundary from §5: even if a client tried to send an event title, the server must refuse it.

- [ ] **Step 2: Implement `blocks.ts`**

Validate the body explicitly (Fastify JSON schema or hand-rolled — no new dependency). Validate `recurrenceRule` by attempting to parse it with `rrulestr` and rejecting anything whose `FREQ` is outside the supported set, so an unparseable rule fails at write time rather than silently producing zero occurrences later.

- [ ] **Step 3: Write the overlaps tests, then implement `overlaps.ts`**

```ts
// src/__tests__/overlaps.test.ts
it('GET /overlaps/latest 403s for a non-member')
it('returns the stored windows when the recomputed hash matches')
it('does not write to the database when the hash matches')
it('recomputes and returns fresh windows when the stored hash is stale')
it('recomputes when the hour bucket rolled over even though no block changed')  // the staleness fix
it('returns an empty array — not 404 — for a couple that has never computed')
it('accepts a window whose durationMinutes is 1560')   // camelCase: engine type, not a row
```

The hour-bucket test is the one that proves §3's staleness fix: the old build let past windows linger until some unrelated change event fired.

- [ ] **Step 4: Verify and commit**

```bash
cd backend && pnpm build && pnpm test
git commit -am "feat(backend): add block routes with onlyMe enforcement and overlap read path"
```

---

## Task 8: WebSocket `/sync`, FCM push, and the invite-expiry cron

**Files:**
- Create: `backend/src/sync.ts`, `backend/src/cron.ts`
- Rewrite: `backend/src/push.ts`
- Modify: `backend/src/index.ts`
- Test: `backend/src/__tests__/sync.test.ts`, `backend/src/__tests__/push.test.ts`, `backend/src/__tests__/cron.test.ts`

**Interfaces:**
- Consumes: `uidFromRequest`, `sockets.*`, `firebase.sendEach`, `query`.
- Produces:
  ```ts
  // src/sync.ts
  export function attachSyncServer(app: FastifyInstance): void   // handles the /sync upgrade

  // src/push.ts
  /** Sends to every token for uid; prunes only hard-invalid tokens. No-op when tokens is empty. */
  export function pushOverlapChanged(uid: string, windows: OverlapWindow[], timezone: string): Promise<void>

  // src/cron.ts
  export function registerAdminRoutes(app: FastifyInstance): void   // POST /admin/cleanup
  export function startInviteExpiryTimer(): NodeJS.Timeout          // 03:00 UTC daily
  export function expireStaleInvites(): Promise<number>             // returns rows affected
  ```

- [ ] **Step 1: Write the WS tests first**

```ts
// src/__tests__/sync.test.ts — drive a real ws client against a real server on an ephemeral port
it('closes with 4001 when no token is supplied')
it('closes with 4001 when verifyIdToken rejects')
it('accepts a token from the Authorization header on the upgrade')
it('accepts a token from ?token= when no header is present')
it('sends hello with uid and coupleId immediately on connect')
it('registers the socket so sendTo reaches it')
it('unregisters on close, after which isOnline is false')
it('supports two concurrent sockets for the same uid')       // two devices
it('silently ignores an inbound message with an unrecognised t')  // forward-compat
it('ignores an inbound overlap message — clients no longer publish windows')
it('responds to a ping with a pong')
```

The second-to-last test is load-bearing for §0.1: the client-publish path is gone and the server must not honour it even if an old build sends one.

- [ ] **Step 2: Implement `sync.ts`**

Server→client only. On upgrade: resolve the uid via `uidFromRequest`, close `4001` on failure, look up `couple_id`, `register(uid, ws)`, send `hello`, and `unregister` on close/error.

- [ ] **Step 3: Write the push tests, then implement `push.ts`**

```ts
// src/__tests__/push.test.ts — vi.mock('../firebase.js')
it('sends nothing when the user has no tokens')
it('sends to every token the user has')
it('prunes a token on messaging/invalid-registration-token')
it('prunes a token on messaging/registration-token-not-registered')
it('KEEPS a token on messaging/internal-error and other transient codes')
it('keeps every other token when one is pruned')
it('formats the body with a local time in the recipient timezone')
it('never includes a block title in the payload')
```

- [ ] **Step 4: Write the cron tests, then implement `cron.ts`**

```ts
// src/__tests__/cron.test.ts
it('expireStaleInvites flips only pending invites whose expires_at has passed')
it('expireStaleInvites leaves accepted invites untouched')
it('POST /admin/cleanup 503s when the admin token is unset')
it('POST /admin/cleanup 401s on a wrong token')
it('POST /admin/cleanup 200s and reports the count on the correct token')
it('compares the admin token in constant time')   // assert timingSafeEqual is used
```

Use a plain `setInterval` that checks the clock — no `node-cron` dependency for one daily job. Comment the ceiling: it drifts on a long-running process and only fires on the replica that owns it.

- [ ] **Step 5: Verify and commit**

```bash
cd backend && pnpm build && pnpm test
git commit -am "feat(backend): add websocket fan-out, FCM push, and invite expiry"
```

---

## Task 9: Docker, Compose, and the backend README

**Files:**
- Create: `backend/Dockerfile`, `backend/README.md`, `docker-compose.yml`, `docker-compose.override.yml`, `.dockerignore`

**Interfaces:**
- Consumes: a fully built backend.
- Produces: a container that migrates then serves on port 3000, and a one-command local stack.

- [ ] **Step 1: Write `backend/Dockerfile`**

Multi-stage on `node:22-alpine`: a build stage that installs with `pnpm --frozen-lockfile` and runs `tsc`, then a runtime stage with production deps only, a non-root user, `EXPOSE 3000`, and:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["sh", "-c", "node dist/migrate.js && node dist/index.js"]
```

- [ ] **Step 2: Write `docker-compose.yml` — production shape**

`build: ./backend`, `expose: ["3000"]` with **no** host port publish, `restart: unless-stopped`, Traefik labels for TLS termination, and every environment value read from the deploy environment. No literal secrets in the file — reference variables only.

- [ ] **Step 3: Write `docker-compose.override.yml` — local dev**

Adds a `postgres:16` service using `POSTGRES_HOST_AUTH_METHOD=trust` (throwaway local data only), an api `depends_on: { db: { condition: service_healthy } }` with a `pg_isready` healthcheck on the db, and `ports: ["3000:3000"]`.

- [ ] **Step 4: Verify the container actually serves**

```bash
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --build
sleep 15 && curl -fsS localhost:3000/health && echo OK
docker compose -f docker-compose.yml -f docker-compose.override.yml logs api | grep -i migrat
docker compose -f docker-compose.yml -f docker-compose.override.yml down -v
```

Expected: `/health` returns 200, and the logs show migrations running before the listen line.

- [ ] **Step 5: Prove the fail-fast paths**

Start the api with `CORS_ORIGINS` unset, and again with a garbage service-account value. Both must exit non-zero. A container that boots healthy in either case is a Task 3 regression — fix it there.

- [ ] **Step 6: Write `backend/README.md`**

Required environment variables in a table, the local-run command, how to run migrations standalone, and how deploy works (git push → Coolify builds `backend/Dockerfile`). Keep it short.

- [ ] **Step 7: Commit**

```bash
git add backend/Dockerfile backend/README.md docker-compose.yml docker-compose.override.yml .dockerignore
git commit -m "feat(backend): containerize with healthcheck and local compose stack"
```

---

## Task 10: Expo scaffold, routing, guard chain, and store

**Files:**
- Create: `app.config.ts`, `app/_layout.tsx`, `app/auth.tsx`, `app/timezone-setup.tsx`, `app/pairing.tsx`, `app/(tabs)/_layout.tsx` + the five tab screens, `app/block-form.tsx`, `src/store.ts`, `src/theme.ts`, `.env.example`
- Modify: `tsconfig.json`, `package.json` (root)

**Interfaces:**
- Consumes: `backend/src/wire.ts` from Task 4, imported type-only.
- Produces:
  ```ts
  // src/store.ts
  import type { UserRow, CoupleRow, BlockRow, OverlapWindow } from '../backend/src/wire'

  interface State {
    hydrated: boolean
    user: UserRow | null                   // own row, so fcm_tokens is present
    couple: CoupleRow | null
    blocks: BlockRow[]
    windows: OverlapWindow[]
    pendingInviteCode: string | null       // parked across the sign-in round trip
    lastCalendarSyncMs: number | null
  }
  interface Actions {
    setUser(u: UserRow | null): void
    setCouple(c: CoupleRow | null): void
    setBlocks(b: BlockRow[]): void
    upsertBlock(b: BlockRow): void
    removeBlock(id: string): void
    setWindows(w: OverlapWindow[], computedAt: number): void
    setPendingInvite(code: string | null): void
    reset(): void                          // on sign-out and on unpair
  }
  export const useStore: UseBoundStore<StoreApi<State & Actions>>
  ```

The root `tsconfig.json` must add `backend/src/wire.ts` to its `include` so the type-only import
resolves. Confirm with `npx tsc --noEmit` that it resolves, and confirm `npx expo export` (or a
Metro bundle) does **not** pull in `pg` — if it does, someone wrote a value import instead of
`import type`.

- [ ] **Step 1: Write `app.config.ts`**

Name `Couple Sync`, slug `couple-sync`, scheme `couplesync`, iOS bundle + Android package `money.stitch.couplesync`, the existing `assets/*.png` wired as icon/splash/adaptive icon, and the `@react-native-firebase/app`, `@react-native-google-signin/google-signin`, `expo-apple-authentication`, `expo-notifications`, `expo-build-properties` plugins. Read `API_BASE_URL` from `process.env` into `extra`.

- [ ] **Step 2: Build the route tree and the guard chain in `app/_layout.tsx`**

Order per §1, evaluated only once `hydrated` is true:

```
!user                → /auth
!user.timezone       → /timezone-setup
!user.coupleId       → /pairing
otherwise            → /(tabs)
```

While `hydrated` is false, render a splash — never a screen. A wrong-route flash on cold start was a real defect class in the old build's redirect chain.

- [ ] **Step 3: Implement deep-link parking**

`couplesync://invite/:code` must call `setPendingInvite(code)` and survive sign-in. Once authenticated and unpaired, `/pairing` opens on the Enter tab with the code pre-filled, and `setPendingInvite(null)` runs after it is consumed. Handle both cold start (`Linking.getInitialURL`) and warm (`Linking.addEventListener`).

- [ ] **Step 4: Write `src/theme.ts` and `src/store.ts`**

Theme: colors (light + dark), spacing scale, type scale. Plain objects, no styling library. Store: exactly the interface above, no persistence yet.

- [ ] **Step 5: Create every screen as a one-line stub**

Literally `export default () => <Text>auth</Text>` per screen — nine files, one line each. Do **not**
lay out the screens here: Tasks 12–16 rewrite every one of them, and laying them out twice is a
wasted pass. The only files with real content in this task are `_layout.tsx` (the guard chain) and
`(tabs)/_layout.tsx` (the tab bar), because those are what you are actually verifying.

- [ ] **Step 6: Verify**

```bash
npx tsc --noEmit && npx expo-doctor
```

Expected: tsc clean. Report every `expo-doctor` warning honestly rather than suppressing it. Do not attempt a native build — no Firebase credential files exist yet.

- [ ] **Step 7: Commit**

```bash
git add app app.config.ts src tsconfig.json package.json .env.example
git commit -m "feat(app): scaffold expo-router tree, guard chain, store and theme"
```

---

## Task 11: API client, WebSocket client, and Firebase auth

**Files:**
- Create: `src/api.ts`, `src/ws.ts`, `src/auth.ts`, `src/time.ts`
- Modify: `app/_layout.tsx`, `app/auth.tsx`
- Test: `src/__tests__/api.test.ts`, `src/__tests__/ws.test.ts`

**Interfaces:**
- Consumes: `backend/src/wire.ts` (type-only), `src/store.ts`.
- Produces:
  ```ts
  // src/api.ts — every method injects the current ID token
  import type { UserRow, CoupleRow, BlockRow, OverlapWindow } from '../backend/src/wire'

  /** Request body for a manual block. The server sets id, couple_id, user_id, source, created_at. */
  type NewBlock = Pick<BlockRow,
    'title'|'type'|'category'|'start_utc'|'end_utc'|'timezone'|'recurrence_rule'|'visibility'>

  export const api: {
    verify(): Promise<UserRow>
    me(): Promise<UserRow>
    getUser(uid: string): Promise<Omit<UserRow, 'fcm_tokens'>>
    patchUser(uid: string, patch: Partial<Pick<UserRow,
      'timezone'|'show_late_night_windows'|'notifications_enabled'|'display_name'>>): Promise<UserRow>
    getCouple(id: string): Promise<CoupleRow>
    unpair(id: string): Promise<void>
    createInvite(): Promise<{ code: string; expires_at: number }>
    redeemInvite(code: string): Promise<{ couple_id: string }>
    listBlocks(coupleId: string): Promise<BlockRow[]>
    createBlock(b: NewBlock): Promise<BlockRow>
    updateBlock(id: string, patch: Partial<NewBlock>): Promise<BlockRow>
    deleteBlock(id: string): Promise<void>
    putGoogleBlocks(coupleId: string, intervals: { start_utc: number; end_utc: number }[]): Promise<BlockRow[]>
    latestOverlap(coupleId: string): Promise<{ windows: OverlapWindow[]; computed_at: number }>
    registerFcmToken(token: string): Promise<void>
  }
  export class ApiError extends Error { status: number; code: string }

  // src/ws.ts
  export function connect(): void       // idempotent; reconnects with backoff
  export function disconnect(): void

  // src/auth.ts
  export function signInWithGoogle(): Promise<void>
  export function signInWithApple(): Promise<void>
  export function signOut(): Promise<void>
  export function getIdToken(): Promise<string | null>
  export function onAuthChange(cb: (uid: string | null) => void): () => void
  ```

- [ ] **Step 1: Write the API client tests first**

```ts
// src/__tests__/api.test.ts — mock fetch and getIdToken
it('sends Authorization: Bearer with the current id token on every call')
it('throws ApiError carrying the status and the server error code on a 4xx')
it('throws ApiError on a 5xx')
it('does not retry a 4xx')
it('surfaces a network failure as an ApiError rather than a raw TypeError')
it('sends timestamps as integers, never as ISO strings')
```

- [ ] **Step 2: Implement `src/api.ts`**

One `request()` helper plus thin typed methods. No retry logic beyond what `ws.ts` needs — the client is online-only in v1 (§0.8).

- [ ] **Step 3: Write the WS tests, then implement `src/ws.ts`**

```ts
// src/__tests__/ws.test.ts — fake WebSocket
it('connects with the id token in the Authorization header')
it('reconnects with exponential backoff, capped, after an unexpected close')
it('does not reconnect after an explicit disconnect')
it('does not open a second socket when connect is called twice')
it('applies block:set to the store via upsertBlock')
it('applies block:del to the store via removeBlock')
it('applies overlap to the store via setWindows')
it('applies user:update to the store')
it('resets the store and routes to /pairing on unpair')
it('refetches user and couple on pairing')
it('ignores a message with an unknown t')
it('refetches the latest overlap after a reconnect')   // catches anything missed while offline
```

- [ ] **Step 4: Implement `src/auth.ts` and wire the sign-in screen**

Google via `@react-native-google-signin/google-signin` → Firebase credential; Apple via `expo-apple-authentication` → Firebase credential (guard it to iOS). `onAuthChange` drives hydration in `_layout.tsx`: on a uid, `api.verify()` → `setUser`, then couple + blocks + windows in parallel, then `connect()`, then `hydrated = true`. On sign-out: `disconnect()`, `reset()`.

- [ ] **Step 5: Write `src/time.ts`**

luxon helpers only — format a window range in a given zone, a live clock string, a relative countdown, and a block's `{ dayIndex, topMinutes, heightMinutes }` for the week grid. **No interval algebra** (§0.1): no merging, no intersecting, no recurrence expansion.

- [ ] **Step 6: Verify and commit**

```bash
npx tsc --noEmit && npm test
git commit -am "feat(app): add api client, websocket client, firebase auth and time helpers"
```

---

## Task 12: Onboarding screens — auth, timezone, pairing

**Files:** `app/auth.tsx`, `app/timezone-setup.tsx`, `app/pairing.tsx`, `src/timezones.ts`

**Interfaces:** Consumes `api`, `src/auth.ts`, `store`. Produces nothing later tasks depend on.

- [ ] **Step 1: Finish `app/auth.tsx`** — Google and Apple buttons (Apple iOS-only), a loading state, and an inline error message on failure. No email/password, no anonymous (§0.8).
- [ ] **Step 2: Write `src/timezones.ts`** — the IANA zone list grouped by region with a search filter. Use `Intl.supportedValuesOf('timeZone')` rather than shipping a hand-maintained list.
- [ ] **Step 3: Finish `app/timezone-setup.tsx`** — pre-select `expo-localization`'s detected zone, offer a searchable override, `api.patchUser` on confirm. Show each candidate's current local time so a wrong pick is obvious.
- [ ] **Step 4: Finish `app/pairing.tsx`** — Share tab (`api.createInvite`, show the code + expiry, copy button, `Share.share` with the `couplesync://invite/<code>` link) and Enter tab (6-char input, `api.redeemInvite`, distinct messages for expired / already-used / self-pair / already-paired). Consume `pendingInviteCode` when present. Navigation happens off the WS `pairing` message and the `coupleId` change — **no polling loop**; the old build polled every 3 s.
- [ ] **Step 5: Verify** — `npx tsc --noEmit`, then run on a simulator and walk sign-in → timezone → pairing.
- [ ] **Step 6: Commit** — `git commit -am "feat(app): implement auth, timezone setup and pairing screens"`

---

## Task 13: Home and Overlap screens

**Files:** `app/(tabs)/index.tsx`, `app/(tabs)/overlap.tsx`, `src/components/WindowCard.tsx`

**Interfaces:** Consumes `store.windows`, `store.user`, `store.couple`, `api`, `src/time.ts`.

- [ ] **Step 1: Build `WindowCard`** — start/end in both zones, duration, score-derived emphasis, and a late-night marker when `reasonableBoth` is false.
- [ ] **Step 2: Build Home** — both partners' live clocks (tick once a minute, not once a second), a countdown to the next window, the next 5 windows, quick actions (add block, sync calendar, view all), and pull-to-refresh calling `api.latestOverlap`. **Filter out any window whose `endUtc` is in the past** before rendering — §9 notes the stored row can lag the clock.
- [ ] **Step 3: Build Overlap** — the full list with an any/30m/1h/2h filter (display-only per §0.7) and a detail view. The empty state distinguishes "no windows found" from "no blocks yet — add some or sync your calendar".
- [ ] **Step 4: Verify** — `npx tsc --noEmit` plus a visual check against seeded backend data.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): implement home and overlap screens"`

---

## Task 14: Calendar week view

**Files:** `app/(tabs)/calendar.tsx`, `src/components/WeekGrid.tsx`

**Interfaces:** Consumes `store.blocks`, `store.windows`, the positioning helper in `src/time.ts`.

- [ ] **Step 1: Build `WeekGrid`** — 7 day columns × 24 hour rows in the viewer's timezone, blocks positioned via `src/time.ts`, overlap windows layered underneath. A block whose own `timezone` differs from the viewer's renders at the viewer's wall clock.
- [ ] **Step 2: Add week paging** — anchor page 0 to a fixed epoch Monday so paging is deterministic; a horizontal pager for prev/next week; a "today" jump.
- [ ] **Step 3: Wire the taps** — a block opens a detail sheet (a partner's `onlyMe` block shows "Busy" with no title, because the server already nulled it); a window opens the same detail as Task 14; the FAB opens `block-form`.
- [ ] **Step 4: Verify** — `npx tsc --noEmit`; confirm a recurring block appears on every expected day and that a DST week does not visually shift.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): implement calendar week view"`

---

## Task 15: Block management and the block form

**Files:** `app/(tabs)/blocks.tsx`, `app/block-form.tsx`, `src/components/RecurrencePicker.tsx`

**Interfaces:** Consumes `api.createBlock`/`updateBlock`/`deleteBlock`, `store`.

- [ ] **Step 1: Build the blocks list** — own blocks only, filterable by source and category, swipe-to-delete with confirmation. Google-sourced rows are visibly read-only and have no edit affordance.
- [ ] **Step 2: Build `RecurrencePicker`** — none / daily / weekly (with weekday selection) / monthly, emitting an RRULE string. Only emit rules the backend accepts (§3.2), since Task 7 rejects anything else at write time.
- [ ] **Step 3: Build the form** — title, type, category, start/end date-time pickers in the user's zone, the recurrence picker, and a visibility toggle whose helper text states plainly that `onlyMe` hides the title from your partner but still blocks out the time. Validate a non-empty title and `end > start` client-side, and surface the server's 400 message when the server rejects anyway.
- [ ] **Step 4: Verify** — `npx tsc --noEmit`; create, edit and delete a recurring block and confirm the overlap list updates over the WS without a manual refresh.
- [ ] **Step 5: Commit** — `git commit -am "feat(app): implement block management and block form"`

---

## Task 16: Settings, Google Calendar sync, and notifications

**Files:** `app/(tabs)/settings.tsx`, `src/calendar.ts`, `src/notifications.ts`

**Interfaces:**
- Produces:
  ```ts
  // src/calendar.ts
  export function isConnected(): Promise<boolean>
  export function connect(): Promise<void>          // requests the calendar.readonly scope
  export function disconnect(): Promise<void>
  /** freeBusy.query on the primary calendar for the next 14 days → PUT /blocks/google.
   *  Returns 'rate-limited' when the last sync was under an hour ago. */
  export function sync(coupleId: string, opts?: { force?: boolean }):
    Promise<'synced' | 'rate-limited' | 'not-connected'>

  // src/notifications.ts
  export function requestPermissionAndRegister(): Promise<void>
  export function attachTapHandler(): () => void     // routes a tap to /overlap
  ```

- [ ] **Step 1: Implement `src/calendar.ts`**

Request exactly `https://www.googleapis.com/auth/calendar.readonly` as a scope escalation on the existing Google Sign-In. Call **only** `freeBusy.query` on `primary` for `now → now + 14d`. Map each busy interval to `{ startUtc, endUtc }` and `PUT /blocks/google`. **Never call `events.list`, never read a `summary` field.** Enforce the ≤1 call/hour limit locally and return `'rate-limited'` instead of calling. Exponential backoff on 429/503.

- [ ] **Step 2: Implement `src/notifications.ts`**

Request permission, get the FCM token, `api.registerFcmToken`, and re-register on token refresh. Foreground notifications **must actually display** — the previous build wired a display interface that production never populated, so foreground notifications were silently dead. Add a check that proves display is wired, not merely called.

- [ ] **Step 3: Build Settings**

Connect/disconnect Google with a last-sync timestamp and a manual sync button; change timezone; a notifications toggle that calls `api.patchUser({ notificationsEnabled })` — it must change server behaviour, not just local state (§0.5); a late-night-windows toggle via `api.patchUser`, after which the overlap list visibly changes; unpair behind a confirmation dialog; sign out.

- [ ] **Step 4: Verify each toggle end-to-end**

Flip notifications off and assert the server stops pushing. Flip late-night on and assert new windows appear. Both were fake in the old build — prove they are not now.

- [ ] **Step 5: Commit** — `git commit -am "feat(app): implement settings, google calendar sync and notifications"`

---

## Task 17: CI, git hooks, and documentation

**Files:**
- Create: `.github/workflows/ci.yml`, `.githooks/pre-commit`, `.githooks/pre-push`, `README.md`, `CLAUDE.md`
- Modify: `PRD.md`, `ARCHITECTURE.md` (add a superseded header to each)

**Interfaces:** Consumes everything.

- [ ] **Step 1: Write `.github/workflows/ci.yml`**

Two jobs on `ubuntu-latest`, both gating PRs. The previous CI ran static analysis only and explicitly skipped tests — 3,000+ lines of tests sat ungated. Do not repeat that.

```yaml
# job: backend  — pnpm install --frozen-lockfile; pnpm build; pnpm test
#                 with a postgres:16 service container and TEST_DATABASE_URL set,
#                 so the migration tests actually run
# job: app      — npm ci; npx tsc --noEmit; npm run lint; npm test
```

- [ ] **Step 2: Delete the stale Flutter git hooks; do not replace them**

`.githooks/pre-commit` and `pre-push` were deleted in Task 1 because they ran `flutter analyze` and
`dart format`. Do **not** write TypeScript replacements. CI (Step 1) already gates build and tests on
every PR, and a pre-push hook that runs the full suite is friction that gets `--no-verify`'d within a
week — at which point it gates nothing while still costing everyone time. `commit-msg` stays as-is:
it is fast, it enforces the conventional-commit format, and CI cannot retroactively fix a bad commit
message.

- [ ] **Step 3: Write `README.md`**

What the product is, the two-deployable layout, how to run the backend locally (one compose command), how to run the app (`npm start`), the required environment variables, and the human-only setup steps: Firebase project config files (`google-services.json`, `GoogleService-Info.plist`), the Google OAuth client IDs, enabling the Calendar API, and the Apple Developer account needed for Apple Sign-In.

- [ ] **Step 4: Write `CLAUDE.md`**

Replace the deleted Flutter version. Correct stack, correct commands, the **server-side** overlap architecture, `pnpm` for the backend and `npm` for the app, and the standing decisions from §0. Every command in it must be one you have actually run.

- [ ] **Step 5: Mark the stale docs**

`PRD.md` and `ARCHITECTURE.md` both describe Flutter, Firestore and device-side compute. Add a one-line header to each: superseded by `docs/REBUILD-SPEC.md`, retained for product history only. Leaving them unmarked is how the contradictions in this rebuild started.

- [ ] **Step 6: Verify CI is actually green**

Push the branch and confirm both jobs pass. A red pipeline here means an earlier task's tests only ever ran locally.

- [ ] **Step 7: Commit** — `git commit -am "ci: gate backend and app tests; rewrite project docs"`

---

## Self-Review

**Spec coverage.** §1 screens → Tasks 10, 12–16. §2 data model → Task 2. §3 engine → already built; its integration → Task 5; the hour-bucket staleness fix → Task 7. §4 auth + pairing → Tasks 3, 6, 12. §5 Google Calendar → Tasks 7 (`PUT /blocks/google`) and 16 (client). §6 realtime + push → Tasks 8, 11. §7 REST surface → Tasks 6, 7, 8. §8 non-negotiables → distributed, each with a named test: freebusy-only (Task 7 Step 1, Task 16 Step 1), token verification (Task 3), `assertMember` (Task 4), `onlyMe` (Tasks 4, 7), the admin token (Task 8), CORS + fail-fast (Tasks 3, 9), Spark plan (no task adds a Blaze feature), idempotent migrations (Task 2). §9 ceilings → comments required in Tasks 4, 5, 8.

**Ponytail pass — five things deleted from an earlier draft of this plan, recorded so nobody re-adds them:**
1. **The DTO mapping layer** (`toUserDto`/`toBlockDto`/`toCoupleDto`). Rows now go out `snake_case` as `pg` returns them. `wire.ts` keeps only the two functions that carry real logic.
2. **A whole task** that hand-copied wire types into `src/types.ts` and added a key-set-assertion `contract.test.ts` to police the copy. Replaced by one type-only import across the repo — one definition, nothing to drift, no test needed to detect drift that cannot happen.
3. **`readStored` and `closePool`** — zero call sites anywhere in the plan.
4. **Laying out nine screens twice.** Task 10 stubs them in one line each; Tasks 12–16 write them once, properly.
5. **TypeScript `pre-commit`/`pre-push` hooks.** CI gates the same things and cannot be `--no-verify`'d.

**One bug caught during that pass:** `pg` returns `BIGINT` as a **string** by default. Without the int8 parser now required in `db.ts` (Task 2), every `*_utc` field would arrive as `"1712345678000"` while `wire.ts` declared it a `number` — the timestamps would have type-checked and been wrong. Asserted in the migration test.

**Two spec corrections found while planning**, from the engine implementer's report, to be applied to `docs/REBUILD-SPEC.md` in Task 1 Step 1:
1. §3 step 8's "a fall-back day must yield a 25-hour segment" is only reachable on the `showLateNightWindows: true` midnight-split path. The waking-hours clip is 07:00–23:00, so it yields 16 hours by construction and *cannot* produce 25. The engine tests assert 25/23 for the full-day split and 16/16 with pinned UTC boundaries for the waking clip, which is what actually catches a `+ 86_400_000` regression. Correct the wording.
2. `durationMinutes ≤ 1560` is likewise only reachable via the midnight-split path (25 h = 1500). Server-side validation must still allow 1560 — asserted in Task 7 Step 3.

**Known gap, deliberately unresolved:** there is no server-side Google OAuth refresh token, so a calendar sync needs the app in the foreground. §9 records it; no task closes it.
