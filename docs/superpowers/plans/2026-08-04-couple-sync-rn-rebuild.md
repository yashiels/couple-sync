# Couple Sync React Native Rebuild — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the deleted Flutter app with an Expo React Native app talking to a Fastify + Postgres backend that runs in Docker, computes overlap windows server-side, and fans them out over WebSocket + FCM.

**Architecture:** One repo, two deployables. The Expo app at the repo root is a thin client — it renders windows the server computed and holds no interval math. `backend/` is a single Fastify process serving REST + a WebSocket, with Postgres for storage; overlap is a pure function (`backend/src/overlap/`, already built and tested) called inline on any write that could change the result. Firebase provides Auth (ID token verification) and FCM only — no Firestore, no Cloud Functions.

**Tech Stack:** Expo SDK 57 / React Native 0.86 / React 19.2 / expo-router / zustand / luxon · Node 22 / TypeScript strict / Fastify 5 / `pg` / `ws` / `firebase-admin` / vitest / pnpm · Postgres 16 · Docker + Docker Compose · Firebase Auth + FCM (Spark plan)

**Specification:** `docs/REBUILD-SPEC.md` (moved there by Task 1). Sections are cited per task as **§n**. The spec is authoritative; `PRD.md` and `ARCHITECTURE.md` are stale and must not be used as a source of truth.

---

## Global Constraints

Every task's requirements implicitly include this section.

- **`windows[0]` is NOT the next window.** The engine sorts by **score descending** (`compareWindows`),
  so `windows[0]` is the *best* window, which can be days away. Anything showing "next" must
  `reduce` to the minimum `startUtc` — this already bit the FCM notification body in Task 8, and the
  Free time screen's countdown is the other place it matters.
- **Timestamps** are UTC epoch milliseconds everywhere: `BIGINT` in Postgres, `number` in TypeScript, plain integers on the wire. Never an ISO string, never a `Date` in a payload.
- **The wire shape is the row shape.** Database rows go out over REST and WS in `snake_case`, exactly as Postgres returns them. There is no DTO mapping layer, because renaming `couple_id` to `coupleId` buys nothing and costs a mapper per entity plus a drift-detection test. The two transforms that carry real logic — scrubbing an `onlyMe` block and stripping `fcm_tokens` — live in `backend/src/wire.ts` and are the only functions between a row and a response. The one exception is `OverlapWindow`, which is the engine's own computed type and stays `camelCase` (`startUtc`, `durationMinutes`) because it is not a row.
- **The app imports its wire types directly from the backend, type-only:** `import type { UserRow } from '../backend/src/wire'`. One repo, one definition, no hand-copy and no contract test to police the copy. `import type` is erased before Metro sees it, so no backend code is ever bundled — and an accidental *value* import fails loudly at bundle time when Metro tries to resolve `pg`.
- **Timezones** are IANA IDs (`America/New_York`, `Africa/Johannesburg`). Never an abbreviation, never a UTC offset.
- **Package manager** is `pnpm` in `backend/` (declared via `packageManager`) and `npm` at the repo root (an `npm`-generated `package-lock.json` already exists there). Never mix.
- **TypeScript** is `strict` in both projects. `backend/tsconfig.json` additionally sets `noUncheckedIndexedAccess` — the existing engine code depends on it, do not relax it.
- **Backend module system** is ESM. Relative imports carry a `.js` extension (`import { query } from './db.js'`).
- **Never use a named ESM import from a CJS-only dependency.** `rrule` has no `exports` map, so
  `import { RRule } from 'rrule'` resolves under `tsc` and vitest (both read the `module` field) but
  throws `does not provide an export named 'RRule'` under plain `node dist/…`. That made the built
  container unbootable while every test stayed green. Use `import pkg from 'rrule'` and destructure.
  `src/__tests__/boot-esm.test.ts` imports the **built output** in a real node process and statically
  scans `dist/` for the unsafe form, so this cannot regress — but it only runs after `pnpm build`,
  which is why every task gate is `pnpm build && pnpm test`, never `pnpm test` alone.
- **Overlap is computed server-side only.** The client never computes, hashes, or publishes windows. Any client-side interval algebra beyond positioning an already-expanded interval on the week grid is a defect.
- **Recurrence is expanded server-side too, and the server must hand the client the expanded occurrences.** The client has no `rrule` dependency, so it cannot turn `recurrence_rule: 'FREQ=WEEKLY;BYDAY=TU,WE'` into three rectangles on a week grid. `GET /blocks` therefore takes a `from`/`to` range and returns, per block, an `occurrences: { start_utc, end_utc }[]` array produced by the engine's existing `expandBlock`. Never re-add client-side expansion, and never ship a calendar view that reads `recurrence_rule` directly.
- **`git commit -am` is banned in this plan.** Most tasks create new files, and `-a` stages only *tracked* modifications, so a new file is silently left out. Every commit step names its paths: `git add <paths> && git commit -m "…"`. This exact failure already cost this project its whole backend directory once — it was untracked, so nothing protected it.
- **Android is the only target for now.** Every verification step runs `npx expo run:android` on an emulator or device. iOS is not built, not tested, and not shipped in this plan — keep the code platform-neutral, but do not spend a step on it.
- **Google is the only sign-in method.** Apple Sign-In is dropped from this plan: it needs a paid Apple Developer account, it is iOS-only, and Android is the priority. Do not add `expo-apple-authentication`. There is no email/password and no anonymous auth either.
- **Google Calendar is the product, and Google sign-in is the only door.** Signing in with Google *is* connecting the calendar: `signInWithGoogle()` requests `calendar.readonly` in the same consent flow, so there is no separate "connect your calendar" step, screen, or Settings toggle, and no `connect()`/`disconnect()`/`isConnected()` API. The core loop is *sign in with Google → we pull your free/busy → we show both partners' free spots*.
- **But do not assume the scope was granted.** Google lets a user complete sign-in while declining the calendar consent, and a granted scope can be revoked later from their Google account. So `src/calendar.ts` exposes `ensureScope()` and `sync()` returns `'scope-missing'`, which the Free time screen surfaces as an inline "Allow calendar access" button — one row, not a screen, and never a router guard.
- **The app requires an Expo development build, not Expo Go.** `@react-native-firebase/*` ships native modules and remote push needs a real build, so `expo-dev-client` is a dependency and `npx expo run:android` is how every "verify on a device" step is executed. Any step that assumes Expo Go is unexecutable.
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
| `src/tz.ts` | `isValidTimezone` — luxon's `IANAZone.isValidZone` **plus** an offset rejection, because `isValidZone('+02:00')` returns true and a fixed offset carries no DST rules. Used by invite redeem, `PATCH /users/:uid`, and every block write. |
| `src/wire.ts` | Row interfaces (the wire shape), the `onlyMe` scrub, `fcm_tokens` stripping, the `WsMessage` union. Imported type-only by the app. |
| `src/sockets.ts` | `uid → WebSocket` registry, `sendTo`, `isOnline` |
| `src/overlap/**` | **Existing.** Pure engine. §3. |
| `src/overlapService.ts` | The only caller of `computeOverlap`: load rows → compute → dedup on `input_hash` → upsert → fan out → push |
| `src/push.ts` | FCM send + invalid-token pruning |
| `src/cron.ts` | Daily invite expiry timer + `POST /admin/cleanup` |
| `src/routes/auth.ts` | `POST /auth/verify`, `POST`/`DELETE /auth/fcm-token` |
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
| `app/(tabs)/_layout.tsx` | Bottom tab bar — **three** tabs |
| `app/(tabs)/index.tsx` | Free time: next window, then the full list with a duration filter. Also the connect-your-calendar state. |
| `app/(tabs)/calendar.tsx` | Week view; also where blocks are managed |
| `app/(tabs)/settings.tsx` | Settings |
| `app/block-form.tsx` | Create/edit block (modal, opened from the calendar) |
| `src/api.ts` | Typed REST client; injects the bearer token; maps errors |
| `src/ws.ts` | WS client with reconnect backoff; dispatches into the store |
| `src/auth.ts` | Firebase Auth: Google sign-in (with the calendar scope), sign-out, token access |
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

- [ ] **Step 6: Remove `rrule` from the root `package.json` and regenerate the lockfile**

The client does no recurrence expansion (§0.1). `luxon` stays — the client needs it for display formatting and grid positioning. Add `expo-dev-client` in the same edit (see Global Constraints).

Removing it from `package.json` alone is not enough — `rrule` stays a direct dependency in `package-lock.json` until the lockfile is rebuilt:

```bash
npm install
grep -c '"rrule"' package-lock.json   # expect 0
grep -c 'expo-dev-client' package-lock.json  # expect > 0
```

- [ ] **Step 7: Re-export `expandBlock` from the engine's public surface**

`backend/src/overlap/recurrence.ts:49` already exports `expandBlock(block, windowStart, windowEnd): Interval[]`, but `index.ts` does not re-export it. Task 7's occurrence endpoint needs it. Add to `backend/src/overlap/index.ts`:

```ts
export { expandBlock } from './recurrence.js'
export type { Interval } from './intervals.js'   // NOT types.ts — Interval is declared in intervals.ts
```

Verify the source path before writing this: `recurrence.ts:3` imports `Interval` from `./intervals.js`.
Do not change any engine logic — this is a visibility change only, and all 135 tests must still pass.

- [ ] **Step 8: Rewrite the controlling agent doc**

`AGENTS.md` (deleted from this branch in the bulk removal, but still present on `main`) states at line 92 that *"the device computes overlap and publishes it over WS — the server does not compute overlap"* and lists *"Move overlap computation to the server"* under **Do not**. That is now exactly backwards and it is a file agents read as authoritative. Write a fresh `AGENTS.md` reflecting server-side compute, the Expo stack, and `pnpm`-for-backend / `npm`-for-app. Do not defer this to Task 17 — a subagent picking up Task 2 would read the stale rule first.

- [ ] **Step 9: Install and prove the engine suite runs green**

```bash
cd backend && pnpm install && pnpm build && pnpm test
```

Expected: `tsc` exits 0; vitest reports **135 passed** across 6 files. If the count is lower, `include` is still wrong. If any test fails after a clean `pnpm install`, a dependency version is wrong — fix the version, never the test.

- [ ] **Step 10: Ignore the worktree directory in the parent repo**

```bash
echo '.worktrees/' >> "$(git rev-parse --git-common-dir)/info/exclude"
```

- [ ] **Step 11: Commit**

```bash
git add -A   # -A is correct HERE (a bulk delete + many new files); every LATER task names its paths
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
  // src/db.ts — the surviving draft is already correct. VERIFY it, keep it, do not rewrite it.
  export const pool: pg.Pool
  export type Querier = {
    query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>
  }
  /** Returns ROWS, not a QueryResult — so callers write `const [row] = await query(...)`. */
  export function query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>
  /** BEGIN/COMMIT, ROLLBACK + rethrow on throw, always releases. The callback receives a Querier
   *  bound to the one client, so every statement inside really is in the transaction. */
  export function withTx<T>(fn: (q: Querier) => Promise<T>): Promise<T>
  /** SELECT 1. Throws — called at boot so a bad DB crashes instead of reporting healthy. */
  export function assertReachable(): Promise<void>
  ```

**`query()` returns `T[]`, deliberately.** The draft already does this and it is the better API: every
call site reads `const [row] = await query(...)` instead of destructuring `.rows`, and the two
surviving draft consumers (`couples.ts:9`, `routes/auth.ts:14`) already depend on it. Specifying
`QueryResult<T>` instead would break both of them and make Task 3's `pnpm build` fail before Tasks 4
and 6 get a chance to rewrite them.

No `rowCount` is needed anywhere: a `DELETE ... RETURNING id` returns rows, so `.length === 0` is the
404 signal. One function covers reads, writes and deletes.

No `closePool` and no `getPool()` — nothing in this plan calls either.

**The int8 parser is already in the draft** (`pg.types.setTypeParser(pg.types.builtins.INT8, Number)`)
— keep it. Without it every `*_utc` column arrives as `"1712345678000"` while `wire.ts` declares it a
`number`: it type-checks and is wrong. Assert it in a **`db.test.ts` unit test with `config.js`
mocked**, not in the migration test — `db.ts` imports `config.ts`, which demands Firebase credentials
and `CORS_ORIGINS`, and the migration test must stay runnable with only a database URL.

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
  -- NULL until the user confirms it in onboarding. Do NOT default to 'UTC':
  -- the router guard is `!user.timezone -> /timezone-setup`, and a NOT NULL DEFAULT
  -- makes that guard permanently false, so onboarding becomes unreachable.
  -- Safe to be null: a couple cannot exist before pairing, and pairing is gated behind
  -- timezone setup, so the overlap engine never sees a null zone.
  timezone                 TEXT,
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

Read every `*.sql` in `src/migrations/` sorted by filename, run each in its own transaction, log each filename, exit non-zero on failure.

```ts
/** @param url explicit connection string. Required — migrate.ts must NOT import config.ts. */
export function runMigrations(url: string): Promise<void>
```

**`migrate.ts` must not import `config.ts` or `db.ts`.** It creates its own throwaway `pg.Client`
from the `url` argument and closes it. If it imported `db.ts`, importing it would load `config.ts`,
which demands `FIREBASE_SERVICE_ACCOUNT_JSON` and `CORS_ORIGINS` — so the migration test could not
run without inventing Firebase credentials, and a pre-deploy migration job would need the full
server env. As a standalone entrypoint it reads `process.env.DATABASE_URL` itself:

```ts
if (import.meta.url === `file://${process.argv[1]}`) {
  const url = process.env.DATABASE_URL
  if (!url) { console.error('DATABASE_URL required'); process.exit(1) }
  runMigrations(url).catch((e) => { console.error(e); process.exit(1) })
}
```

- [ ] **Step 3: Write `db.ts` to the interface above**

`pool` is created eagerly at module load from the configured connection string (the draft already does
this, and `config.ts` has validated the URL by then — so anything importing `db.ts` needs a valid
config, which is exactly why `db.test.ts` mocks `config.js` and `migrate.ts` never imports `db.ts`). `withTx` must `ROLLBACK` on throw and `release()` in a `finally`. Verify what the draft `db.ts` does today and rewrite whatever differs — in particular confirm the client is released on the error path.

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
  it('allows a user row with a null timezone', async () => { /* onboarding depends on it */ })
})
```

The int8-parser assertion lives in `src/__tests__/db.test.ts` with `config.js` mocked, **not** here:
this suite must run with only `TEST_DATABASE_URL`, and importing `db.ts` would pull in `config.ts` and
its Firebase requirements.

```ts
// src/__tests__/db.test.ts — vi.mock('../config.js')
it('parses BIGINT as a number, not a string')   // insert 1712345678000, expect typeof 'number'
it('withTx rolls back and rethrows when the callback throws')
it('withTx releases the client on both the success and the error path')
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

First prove the whole tree still compiles, so Task 3 does not inherit a broken build:

```bash
cd backend && pnpm build && pnpm test    # tsc must exit 0 with every draft file still present
```

If `pnpm build` fails on a draft file, you changed a shared signature — either keep the draft's
signature (usually correct, as with `query()` returning `T[]`) or fix that draft now. Do not leave a
red tree for a later task.

```bash
git add backend/src/migrations backend/src/migrate.ts backend/src/db.ts backend/src/__tests__
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
    firebaseServiceAccount: ServiceAccount // FIREBASE_SERVICE_ACCOUNT_JSON, parsed into
                                   // firebase-admin's ServiceAccount type (camelCase:
                                   // projectId/clientEmail/privateKey). Typing it `object`
                                   // makes the project-id comparison below a compile error.
    corsOrigins: string[]          // CORS_ORIGINS, comma-separated; required, '*' rejected
    adminToken: string | null      // ADMIN_TOKEN, optional
  }>

  // src/firebase.ts
  /** Returns firebase-admin's DecodedIdToken — the full claim set, not a narrowed subset.
   *  req.claims is typed DecodedIdToken, so narrowing here would not assign. */
  export function verifyIdToken(token: string): Promise<DecodedIdToken>
  export function sendEach(tokens: string[], payload: unknown):
    Promise<{ token: string; errorCode: string | null }[]>

  // src/auth.ts
  /** Fastify preHandler. 401 on a missing/invalid token.
   *  Sets BOTH req.uid AND req.claims — Task 6's /auth/verify upsert needs email/name/picture
   *  from the decoded token, and re-verifying it there would be a second network round trip. */
  export const requireAuth: preHandlerHookHandler
  /** For the WS upgrade: Authorization header first, then ?token=. Throws HttpError(401). */
  export function uidFromRequest(req: IncomingMessage): Promise<string>

  // src/http.ts
  export class HttpError extends Error { constructor(status: number, code: string, detail?: string) }
  export function registerErrorHandler(app: FastifyInstance): void
  ```
  Both `req.uid: string` and `req.claims: DecodedIdToken` (from `firebase-admin/auth`) are declared on
  `FastifyRequest` via module augmentation, so every route reads them type-safely. The surviving draft
  calls this `req.tokenClaims`; pick one name, declare it, and make the draft match — Task 6 fails to
  compile if the augmentation is missing.

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
it('sets req.claims with email, name and picture from the decoded token')
it('reads the token from the Authorization header on a WS upgrade')
it('falls back to ?token= on a WS upgrade when no header is present')
it('prefers the header over ?token= when both are present')
```

- [ ] **Step 5: Implement `http.ts` and `index.ts`**

`registerErrorHandler` maps `HttpError` → `{ error: code, detail? }` at its status. Fastify's own sub-500 errors (unparseable JSON body, schema validation) pass through with their own status — otherwise a malformed request body answers 500. Everything else → 500, stack logged but not returned. `index.ts`:

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

- [ ] **Step 6: Write boot tests that prove fail-fast actually fails**

`cert()` accepts a structurally valid service account whose key is unusable, so parsing is not
proof. The bootstrap must probe the credential before `listen`, and that must be tested:

```ts
// src/__tests__/boot.test.ts
it('exits non-zero when the service account parses but the credential is rejected')
it('exits non-zero when the database is unreachable')
it('does NOT begin listening in either case')   // the old build listened and 401'd everything
it('exits non-zero when FIREBASE_PROJECT_ID does not match the service account projectId')
it('reports healthy only after both probes passed')
```

**Do not probe with `verifyIdToken('not-a-token')`** — it cannot validate the service-account key.
`firebase-admin` resolves the project id and then rejects the malformed JWT during *decoding*
(`token-verifier.js:117`), before the credential is ever used, so a completely bogus private key
still produces the same "invalid token" error. That probe would pass with unusable credentials, which
is the exact false-confidence being removed.

Probe the credential directly instead:

```ts
// Actually exercises the private key: mints a real OAuth2 access token from Google.
// cert() returns a Credential exposing getAccessToken() (firebase-admin/lib/app/credential.d.ts).
const credential = cert(config.firebaseServiceAccount)
await credential.getAccessToken()          // throws on a bad or unusable private key
// And catch the silent-misconfiguration case: right key, wrong project.
// NOTE camelCase — ServiceAccount is projectId, not project_id.
if (config.firebaseServiceAccount.projectId !== config.firebaseProjectId) {
  throw new Error('FIREBASE_PROJECT_ID does not match the service account projectId')
}
```

The draft `firebase.ts` already had this probe shape — keep it, and make it fatal rather than a warn.

- [ ] **Step 7: Verify**

```bash
cd backend && pnpm build && pnpm test
```

Expected: tsc clean; config, auth, boot, migration and the 135 engine tests all pass.

- [ ] **Step 8: Commit**

```bash
git add backend/src/config.ts backend/src/firebase.ts backend/src/auth.ts backend/src/http.ts backend/src/index.ts backend/src/__tests__
git commit -m "feat(backend): add fail-fast config, firebase init, auth, and error handling"
```

---

## Task 4: Membership guard, the wire module, and the socket registry

**Files:**
- Rewrite: `backend/src/couples.ts`, `backend/src/sockets.ts`, `backend/src/push.ts`
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
    timezone: string | null      // null until confirmed in onboarding — the router guard depends on it
    couple_id: string | null
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

  /** snake_case row -> the engine's camelCase Block: the single place the two vocabularies meet.
   *  The engine's Block has EXACTLY six fields (overlap/types.ts:8) — map them one for one:
   *    user_id -> userId, type -> type, start_utc -> startUtc,
   *    end_utc -> endUtc, timezone -> timezone, recurrence_rule -> recurrenceRule
   *  Nothing else is passed: id, couple_id, title, category, source, visibility are irrelevant to
   *  computation, and forwarding a title into the engine would be a privacy smell.
   *  Used by overlapService.ts AND the occurrence endpoint. */
  export function toEngineBlock(row: BlockRow): Block

  // Engine types come from overlap/types.js — NOT overlap/index.js.
  // types.ts has ZERO imports (verified); index.ts pulls in recurrence.ts -> rrule, and the app
  // typechecks this file without installing backend deps. A re-export alone does not create a
  // local binding, so these must be imported AND re-exported to be usable in WsMessage below.
  import type { Block, OverlapWindow } from './overlap/types.js'
  export type { Block, OverlapWindow }

  /** A block plus every instance intersecting a requested [from,to], already clamped to it.
   *  Returned only by GET /blocks (Task 7); never present on a block:set broadcast, because the
   *  server cannot know a client's visible range. Declared here so Track 2 can start after Task 4. */
  export interface BlockWithOccurrences extends BlockRow {
    occurrences: { start_utc: number; end_utc: number }[]
  }

  export type WsMessage =
    | { t: 'hello';       uid: string; couple_id: string | null }
    | { t: 'block:set';   block: BlockRow }
    | { t: 'block:del';   id: string }
    /** One message for a whole-set replacement (PUT /blocks/google). Emitting block:set per
     *  interval would cause one ranged GET per busy interval, and an empty replacement cannot be
     *  expressed as a block:set at all. Receivers refetch their visible range once. */
    | { t: 'blocks:changed'; couple_id: string }
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

  // src/push.ts — delivered by THIS task, because Task 5 imports it.
  /** Sends to every token for uid; prunes only hard-invalid tokens; no-op when tokens is empty.
   *  Rejects rather than throwing synchronously, so callers can Promise.allSettled it. */
  export function pushOverlapChanged(
    uid: string, tokens: string[], windows: OverlapWindow[], timezone: string
  ): Promise<void>
  ```

Task 3 left a temporary `messaging()` export in `firebase.ts` purely so the draft `push.ts` compiled.
Rewriting `push.ts` here means that shim can go — delete it and use `sendEach`.

`pushOverlapChanged` takes the tokens explicitly rather than re-reading the user row: `refreshOverlap`
already loaded both rows inside its transaction, and a second query after commit could observe a
different value.

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
it('toEngineBlock maps all six engine fields and no others')  // exact key set, field by field
it('toEngineBlock passes through a null recurrence_rule as null')
```

The interval-preserving assertion is the important one: scrubbing must not remove the data the engine needs, or `onlyMe` blocks would stop shaping the overlap.

- [ ] **Step 3: Implement all three modules; run the tests**

Delete the draft `backend/src/dto.ts` — `wire.ts` replaces it. Fix the `import type { UserRow } from './dto.js'` in the draft `push.ts` to point at `./wire.js`.

`sockets.ts` holds a `Map<string, Set<WebSocket>>` so a user with two devices works. Comment the ceiling: in-memory, single-replica only; Redis pub/sub is the upgrade path.

- [ ] **Step 4: Commit**

```bash
git add backend/src/couples.ts backend/src/wire.ts backend/src/sockets.ts backend/src/push.ts backend/src/__tests__
git rm -q backend/src/dto.ts
git commit -m "feat(backend): add membership guard, wire scrubbing, and socket registry"
```

---

## Task 5: The overlap service — the only caller of the engine

**Files:**
- Create: `backend/src/overlapService.ts`
- Test: `backend/src/__tests__/overlapService.test.ts`

**Interfaces:**
- Consumes: `computeOverlap`, `computeInputHash`, `OverlapInput`, `Block`, `OverlapWindow` from `./overlap/index.js`; `withTx` and the `Querier` it yields; `toEngineBlock` from `wire.ts`; `sendTo` from `sockets.ts`; `pushOverlapChanged` from `push.ts`.
  **Deliberately NOT `assertMember`/`partnerUid`** — both use the pool-level `query`, so calling them
  here would run outside the transaction and outside the advisory lock. This module loads the couple
  row itself with the transaction's `Querier` and re-checks `status = 'active'` there. Routes still
  call `assertMember` before `refreshOverlap`; that check is about the caller, not about the lock.
  **`push.ts` is delivered in Task 4, not Task 8** — Task 5 imports it, so it must exist first. Task 4 renames the draft's `pushOverlap(partner, windows)` to `pushOverlapChanged(uid, tokens, windows, timezone)` — taking tokens explicitly, since `refreshOverlap` already loaded both user rows — and Task 8 only hardens it (token-pruning tests, body formatting).
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
it('pushes to the partner only when sendTo returned false for them')
it('does not push when the partner has notifications_enabled false')
it('returns 15 windows for a couple with no blocks on either side')  // NOT [] — see below
it('computes for a couple where only one partner has any blocks')
it('passes ONE OverlapInput object to both computeInputHash and computeOverlap')
it('serializes two concurrent refreshes for the same couple')
it('never stores an older result when two writes race')
it('does not serialize refreshes for different couples')
```

**Two people with no blocks are free all the time, so the engine correctly returns windows, not an
empty list.** `backend/src/overlap/index.test.ts:57` asserts exactly 15 for the default fixture
(a partial first local day + 13 whole days + a partial last day). Any test here that expects `[]`
for an empty couple will fail against the real engine. Verify the exact count against the engine's
own fixture rather than hard-coding 15 blindly — it depends on the timezone and `now` you pass.

- [ ] **Step 2: Implement `refreshOverlap`**

The whole body runs inside one `withTx`, and its **first statement takes a per-couple advisory lock**:

```ts
export async function refreshOverlap(
  coupleId: string,
  triggeredBy: string | null,
  log: FastifyBaseLogger,     // passed in: this module has no logger of its own, and a failed
                              // post-commit push must be logged somewhere real
): Promise<RefreshResult> {
  // NOT `return withTx(...)` — the fan-out must happen AFTER the commit, so the tx result is
  // captured first and the side effects run outside it. See the fan-out section below.
  const committed: Committed = await withTx(async (c) => {
    // Serializes refreshes for THIS couple only; different couples never block each other.
    // Without it, two concurrent writes can interleave load→compute→upsert and store the
    // older result, and every concurrent first-read after an hour rollover would write,
    // fan out, and push. Released automatically at COMMIT/ROLLBACK.
    await c.query('SELECT pg_advisory_xact_lock(hashtext($1))', [coupleId])

    // one captured `now`, one input object, used for BOTH the hash and the compute —
    // calling Date.now() twice can straddle an hour boundary and make the hash describe
    // a different computation than the one that ran.
    const now = Date.now()
    const input: OverlapInput = { blocksA, blocksB, timezoneA, timezoneB, prefsA, prefsB, now }

    const hash = computeInputHash(input)
    if (hash === stored?.input_hash) {
      return { windows: stored.windows, computedAt: stored.computed_at, changed: false,
               coupleId, recipients: [/* same shape as below */] }
    }

    // ponytail: inline on the request thread. ~100ms for 500 recurring blocks/partner
    // against a 500ms budget. A job queue is the upgrade path only if p99 write latency matters.
    const windows = computeOverlap(input)
    // upsert, then RETURN a COMPLETE Committed — no WS, no FCM, no network call in the tx.
    // recipients carries what fanOut needs and what a post-commit re-read could not safely observe.
    return {
      windows, computedAt: now, changed: true,
      coupleId,
      recipients: [userA, userB].map((u) => ({
        uid: u.uid, timezone: u.timezone!, tokens: u.fcm_tokens,
        notificationsEnabled: u.notifications_enabled,
      })),
    }
  })

  if (committed.changed) await fanOut(committed, triggeredBy, log)
  // preserve the real value — hardcoding `changed: true` here erases the dedup result the
  // early-return path just computed, and every "unchanged hash" test would silently pass.
  return { windows: committed.windows, computedAt: committed.computedAt, changed: committed.changed }
}
```

The early-return branch must also produce a complete `Committed` (with `changed: false` and the same
`recipients`), so the function has one return shape.

Load in one round trip inside the lock: the couple row, both user rows (`timezone`,
`show_late_night_windows`, `notifications_enabled`, `fcm_tokens`), and every `timeblocks` row for the
couple. Partition by `couple.user_a_uid`. `onlyMe` blocks go into the engine input unscrubbed —
scrubbing is a presentation concern.

An **inactive couple, or either partner missing a timezone**, returns
`{ windows: [], computedAt: now, changed: false }` with no upsert and no fan-out. Pairing is gated
behind timezone onboarding and re-enforced in the redeem transaction, so a null timezone here means
the couple is simply not computable — do not make a `timezone!` assertion load-bearing.

**Fan-out and push — and the distinction matters.** The WS `overlap` message goes to **both**
partners including `triggeredBy`: the writer's own window list changed and their store must be
updated, otherwise the device that made the edit is the one showing stale windows. Only the **push**
is suppressed for `triggeredBy` — nobody should get an FCM notification about their own action.

The transaction must hand out the recipient data it already loaded — `RefreshResult` alone does not
carry it, and re-querying after commit could observe different rows:

```ts
/** Private. What the transaction returns internally. */
interface Committed extends RefreshResult {
  coupleId: string
  recipients: { uid: string; timezone: string; tokens: string[]; notificationsEnabled: boolean }[]
}

async function fanOut(c: Committed, triggeredBy: string | null, log: FastifyBaseLogger) {
  const msg: WsMessage = {
    t: 'overlap', couple_id: c.coupleId, windows: c.windows, computed_at: c.computedAt,
  }

  // 1. BOTH WS sends first, synchronously, before ANY await. An await between them would let a
  //    newer refresh's message overtake an older one and leave the store on stale windows.
  const delivered = new Map(c.recipients.map((r) => [r.uid, sendTo(r.uid, msg)]))

  // 2. Then the pushes. allSettled + log, because the mutation is already committed: a dead FCM
  //    endpoint must not turn a successful write into an HTTP 500.
  const results = await Promise.allSettled(
    c.recipients
      .filter((r) => r.uid !== triggeredBy && !delivered.get(r.uid) && r.notificationsEnabled)
      .map((r) => pushOverlapChanged(r.uid, r.tokens, c.windows, r.timezone)),
  )
  for (const r of results) if (r.status === 'rejected') log.warn({ err: r.reason }, 'push failed')
}
```

`refreshOverlap` returns only the public `RefreshResult`; `Committed` never leaves the module.

The WS `overlap` goes to **both** partners including `triggeredBy` — the writer's own window list
changed and their store must update, or the very device that made the edit shows stale data. Only the
**push** is suppressed for `triggeredBy`; nobody should be notified about their own action.

Use `sendTo`'s boolean, not a separate `isOnline` call — check-then-send is two round trips with a
disconnect window between them.

**Nothing here runs inside `withTx`.** A notification sent inside the transaction can reach a device
before the data is committed and readable, and awaiting an FCM call while holding a pool connection
starves the pool exactly when concurrent refreshes need one.

`hashtext` returns a 32-bit int, so distinct couple ids can theoretically collide and serialize
against each other. That is harmless (a spurious wait, never a wrong result) — note it and move on.

- [ ] **Step 3: Verify**

```bash
cd backend && pnpm build && pnpm test    # build too: this task's types are easy to get subtly wrong
```

- [ ] **Step 4: Commit**

```bash
git add backend/src/overlapService.ts backend/src/__tests__
git commit -m "feat(backend): add overlap service with input-hash dedup and fan-out"
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
it('POST /invites returns 201 with a 6-character code and expires_at 48h out')
it('generates codes from an unambiguous alphabet — no O, 0, I or 1')
it('POST /invites 409s when the caller already has a couple_id')
it('redeem pairs two unpaired users and returns couple_id')
it('redeem sets couple_id on BOTH user rows and stamps the invite accepted')
it('redeem 404s on an unknown code')
it('redeem rejects an expired code and does not pair')
it('redeem rejects an already-accepted code')
it('redeem rejects self-pairing by the invite creator')
it('redeem 409s when the redeemer already has a couple')
it('redeem 409s when the inviter has since paired with someone else')
it('redeem 409s when either user has a NULL timezone')          // engine would get an invalid zone
it('redeem 409s when either timezone is not a valid IANA id')
it('locks both user rows ordered by uid, not just the invite')  // two codes sharing one user
it('two concurrent redemptions of DIFFERENT codes sharing one user create only ONE couple')
it('redeem uses SELECT ... FOR UPDATE and performs every write in one transaction')
it('redeem rolls back completely on a mid-transaction failure — no orphan couple row')
it('redeem triggers refreshOverlap and a pairing WS message to the inviter')
```

- [ ] **Step 2: Implement `invites.ts`**

The redeem handler is a single `withTx`, and the **lock order is the correctness-critical part**:

```sql
-- 1. lock the invite
SELECT * FROM invites WHERE code = $1 FOR UPDATE;
-- 2. lock BOTH user rows, ordered by uid, in one statement.
--    Locking only the invite is not enough: two DIFFERENT invite codes that share one user can
--    redeem concurrently and create two active couples for that user. Ordering by uid is what
--    prevents two concurrent redemptions from deadlocking on each other.
SELECT uid, couple_id, timezone FROM users
 WHERE uid IN ($2, $3) ORDER BY uid FOR UPDATE;
```

Then every check from §4, **plus one the client cannot be trusted with**: both users' `timezone`
must be non-null and a valid IANA zone. The router guard makes this unreachable through the UI, but a
direct API call could pair two users with `NULL` timezones, and the `refreshOverlap` that runs
immediately after would hand the engine an invalid zone. Reject with 409 and a clear code.

Then insert the couple, stamp the invite, update both users, `COMMIT`. **Only after the commit:**
`refreshOverlap(coupleId, uid)`, a best-effort `sendTo(inviterUid, { t: 'pairing', … })`, and nothing
else — no network call belongs inside the transaction.

**Every couple-mutating path takes the same advisory lock as `refreshOverlap`.** `POST
/couples/:id/unpair` in particular must `SELECT pg_advisory_xact_lock(hashtext($coupleId))` as its
first statement and re-check `status = 'active'` under that lock. Without it, an unpair can delete
`overlaps_latest` while a refresh is mid-compute, and the refresh then recreates the row for a couple
that no longer exists — a resurrected overlap for an inactive couple, invisible until someone
wonders why unpairing did not stick.

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
it('PATCH rejects setting timezone back to null')
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
it('unpair takes the same pg_advisory_xact_lock(hashtext(coupleId)) as refreshOverlap')
it('a refresh that started before an unpair does not recreate overlaps_latest afterwards')
it('unpair re-checks that the couple is still active under the lock')
```

- [ ] **Step 5: Rewrite `routes/auth.ts`**

`POST /auth/verify` upserts from the decoded token (`uid`, `email`, `name`, `picture`) — on conflict, refresh `email`/`display_name`/`photo_url` but never overwrite `timezone`, `couple_id` or the preference columns — and returns the full row (this is the caller's own row, so `fcm_tokens` stays). `POST /auth/fcm-token` appends with dedup so a repeat is a no-op. **Also add `DELETE /auth/fcm-token`** (body `{ token }`, self-only) — the app calls it on sign-out so a shared handset never keeps a previous user's token. Add tests: a first-time sign-in creates the row; a repeat sign-in does not reset the timezone; a repeated FCM token does not duplicate; DELETE removes only the named token and leaves the user's other device tokens intact; DELETE for a token the user does not own is a no-op, not an error.

- [ ] **Step 6: Verify and commit**

**Conventions fixed by this task — Task 11's `api.ts` must match them:**

- **Envelopes:** `{ user }` for the four user-returning routes, `{ couple }` for `GET /couples/:id`,
  flat bodies elsewhere (`{ code, expires_at }`, `{ couple_id }`, `{ fcm_tokens }`, `{ ok: true }`).
- **Error codes:** 404 `unknown_code`; 409 `invite_used`, `invite_expired`, `self_pair`,
  `already_paired`, `inviter_already_paired`, `timezone_required`, `invalid_timezone`.
- Invite codes are stored and compared **upper-case**; redeem upper-cases what the client submits.
- `refreshOverlap` fires when a `PATCH` body *contains* `timezone` or `show_late_night_windows`, not
  on a value diff — `refreshOverlap` already dedups on `input_hash`, so a no-op patch costs one
  compute and no write, no WS, no push. A `display_name`-only patch never refreshes.
- Redeem answers **200 even if the post-commit `refreshOverlap` throws**. The pairing is durable at
  that point and a 500 would read to the client as "not paired".

```bash
cd backend && pnpm build && pnpm test
git add backend/src/routes backend/src/index.ts backend/src/tz.ts backend/src/__tests__
git commit -m "feat(backend): add auth, users, couples and invites routes"
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
it('GET /blocks/:id nulls title and category on the partners onlyMe block')
it('GET /blocks/:id keeps title and category on the callers own onlyMe block')
it('GET /blocks/:id 403s for a block belonging to another couple')
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
it('PUT /blocks/google broadcasts exactly ONE blocks:changed, not one block:set per interval')
it('PUT /blocks/google with an empty interval list still broadcasts blocks:changed')
```

That second-to-last test is a hard privacy boundary from §5: even if a client tried to send an event title, the server must refuse it.

- [ ] **Step 2: Implement `blocks.ts` — every write takes the couple's advisory lock**

A block write racing an unpair is a real corruption path: unpair deletes the couple's blocks and its
`overlaps_latest`, then the in-flight write inserts a block and its `refreshOverlap` recreates the
overlap row — for a couple that no longer exists. So every write handler (`POST`, `PATCH`, `DELETE`,
`PUT /blocks/google`) runs in a transaction whose first statement is
`SELECT pg_advisory_xact_lock(hashtext($coupleId))`, and which then **re-reads the couple and refuses
when `status !== 'active'`** — `assertMember` ran before the lock was held, so its answer is stale by
the time the write happens.

Belt and braces: `refreshOverlap` itself re-checks `status = 'active'` under its own lock and returns
without upserting when the couple is inactive. Either check alone leaves a window; both together
close it.

```ts
// src/__tests__/blocks.test.ts
it('a block create that starts before an unpair commits does not survive it')
it('an unpair that starts before a block create still leaves no blocks behind')
it('PUT /blocks/google racing an unpair does not repopulate blocks')
it('refreshOverlap refuses to upsert for an inactive couple')
```

Validate the body explicitly (Fastify JSON schema or hand-rolled — no new dependency). Validate the body's `recurrence_rule` field (snake_case, like every other field) by attempting to parse it with `rrulestr` and rejecting anything whose `FREQ` is outside the supported set, so an unparseable rule fails at write time rather than silently producing zero occurrences later.

- [ ] **Step 3: Add server-side occurrence expansion to `GET /blocks`**

This is what makes a server-only-compute calendar view possible at all. The client has no `rrule`,
so it cannot expand `FREQ=WEEKLY;BYDAY=TU,WE` into rectangles. The server does it, reusing the
engine's `expandBlock` (re-exported in Task 1 Step 7 — no new code, no new dependency).

```ts
// GET /blocks?coupleId=X&from=<epochMs>&to=<epochMs>
// `from`/`to` are required and must span at most 60 days (a week view asks for ~7).
// BlockWithOccurrences is already declared in wire.ts by Task 4 — do not redeclare it.
// Build each occurrences array with expandBlock(toEngineBlock(row), from, to).
```

```ts
// src/__tests__/blocks.test.ts
it('GET /blocks 400s when from or to is missing')
it('GET /blocks 400s when the range exceeds 60 days')
it('a non-recurring block in range yields exactly one occurrence equal to its own bounds')
it('a non-recurring block outside the range yields an empty occurrences array')
it('a weekly BYDAY=TU,WE block yields two occurrences in a Mon-Sun range')
it('occurrences are clamped to the requested range, not to the 14-day overlap horizon')
it('a recurring 09:00-local block keeps 09:00 local across a DST transition in the range')
it('occurrences are computed for the partners blocks too, and respect the onlyMe scrub')
```

The DST test matters: the same `expandBlock` bug the old Dart build had would show up here as a
block drawn an hour off on the far side of a transition.

- [ ] **Step 4: Write the overlaps tests, then implement `overlaps.ts`**

```ts
// src/__tests__/overlaps.test.ts
it('GET /overlaps/latest 403s for a non-member')
it('returns the stored windows when the recomputed hash matches')
it('does not write to the database when the hash matches')
it('recomputes and returns fresh windows when the stored hash is stale')
it('recomputes when the hour bucket rolled over even though no block changed')  // the staleness fix
it('computes and UPSERTS for a couple that has never computed')   // §3: not an empty response
it('passes the requesting uid as triggeredBy, so a read never pushes to the reader')
it('accepts a window whose durationMinutes is 1560')   // camelCase: engine type, not a row
```

Two corrections to an earlier draft of this task. First, a couple that has never computed must
**recompute and store**, not return `[]` — §3 makes the read path the staleness fix, and two
block-less partners legitimately have ~15 windows. Second, the handler calls
`refreshOverlap(coupleId, req.uid)` — **not** `null`. Passing `null` means the reader is not excluded
from the fan-out, so a user with no live socket gets an FCM push triggered by their own pull-to-refresh.

- [ ] **Step 4: Write the route-wide security matrices**

Per-function unit tests on `requireAuth` and `assertMember` prove the functions work; they prove
nothing about a handler that forgot to call them. A route registered without the guard passes every
test in Tasks 3 and 4. So drive the matrix from a **list of every route**, in
`backend/src/__tests__/guards.matrix.test.ts`:

```ts
// One table. Adding a route without adding it here should be the thing that breaks.
const PROTECTED = [
  ['POST',   '/auth/verify'],           ['POST',   '/auth/fcm-token'],
  ['DELETE', '/auth/fcm-token'],
  ['GET',    '/users/me'],              ['GET',    '/users/:uid'],   ['PATCH', '/users/:uid'],
  ['GET',    '/blocks'],                ['POST',   '/blocks'],       ['GET',   '/blocks/:id'],
  ['PATCH',  '/blocks/:id'],            ['DELETE', '/blocks/:id'],   ['PUT',   '/blocks/google'],
  ['GET',    '/overlaps/latest'],       ['GET',    '/couples/:id'],  ['POST',  '/couples/:id/unpair'],
  ['POST',   '/invites'],               ['POST',   '/invites/:code/redeem'],
]
// POST /auth/verify IS protected — it verifies a Bearer token to upsert the row. Omitting it
// was the hole in an earlier draft of this table.
const COUPLE_SCOPED = PROTECTED.filter(/* the /blocks, /overlaps, /couples paths */)

it.each(PROTECTED)('%s %s 401s with no token',            /* … */)
it.each(PROTECTED)('%s %s 401s with an invalid token',    /* … */)
it.each(COUPLE_SCOPED)('%s %s 403s for a non-member',     /* … */)
it.each(COUPLE_SCOPED)('%s %s 403s — not 404 — for a couple id that does not exist', /* … */)

it('every registered route except /health and /admin/cleanup appears in PROTECTED', () => {
  // Collect routes with a root-level onRoute hook — NOT printRoutes(), whose output is a
  // formatted tree meant for humans and painful to diff:
  //   const seen = []
  //   app.addHook('onRoute', (r) => seen.push([r.method, r.url]))   // before registering plugins
  // Then normalize before diffing:
  //   - r.method can be an ARRAY when a route declares several verbs — flatten it
  //   - Fastify auto-adds HEAD for every GET, and OPTIONS when CORS is registered. Drop both;
  //     they are not separately authored routes and would look like permanent table gaps.
  //   - drop '/health' and '/admin/cleanup' (public / separately guarded by ADMIN_TOKEN)
  // A new unguarded route then fails CI instead of shipping.
})
```

That last test is the one that actually holds the line — the tables go stale otherwise.

- [ ] **Step 5: Prove the `onlyMe` scrub survives the WS fan-out, not just `GET /blocks`**

`GET /blocks` scrubbing is not enough: `block:set` is broadcast to both partners, and scrubbing is
**per recipient** — the owner must get the title, the partner must not, from the same broadcast.

```ts
// src/__tests__/blocks.test.ts
it('block:set sends the owner their own title and the partner a nulled title, from one write')
it('block:del broadcasts only the id, never the block body')
it('an onlyMe block still changes the computed overlap windows')   // reaches the engine unscrubbed
```

The first test is the door the old build's privacy bug would walk back through.

- [ ] **Step 6: Verify and commit**

```bash
cd backend && pnpm build && pnpm test
git add backend/src/routes backend/src/wire.ts backend/src/index.ts backend/src/__tests__
git commit -m "feat(backend): add block routes with onlyMe enforcement and overlap read path"
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
  /** Declared in Task 4. Listed here because Task 8 hardens it: token pruning + body formatting. */
  export function pushOverlapChanged(
    uid: string, tokens: string[], windows: OverlapWindow[], timezone: string
  ): Promise<void>

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
it('sends hello with uid and couple_id immediately on connect')
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
it('compares the admin token in constant time')
it('does not throw on a SHORTER supplied token')   // timingSafeEqual throws on length mismatch
it('does not throw on a LONGER supplied token')
it('rejects an empty supplied token')
```

Use a plain `setInterval` that checks the clock — no `node-cron` dependency for one daily job. Comment the ceiling: it drifts on a long-running process and only fires on the replica that owns it.

**`crypto.timingSafeEqual` throws `RangeError` when the two buffers differ in length**, which turns a wrong-length token into a 500 and leaks the expected length through the error path. Hash both sides to a fixed width first, then compare:

```ts
import { createHash, timingSafeEqual } from 'node:crypto'
const digest = (s: string) => createHash('sha256').update(s).digest()   // always 32 bytes

// Precomputed ONCE at module load. Hashing the secret on every request makes the request's
// duration depend on the secret's length, which is the leak timingSafeEqual exists to close.
const EXPECTED = config.adminToken === null ? null : digest(config.adminToken)

const ok = EXPECTED !== null && timingSafeEqual(digest(supplied), EXPECTED)
```

- [ ] **Step 5: Verify and commit**

```bash
cd backend && pnpm build && pnpm test
git add backend/src/sync.ts backend/src/cron.ts backend/src/push.ts backend/src/index.ts backend/src/__tests__
git commit -m "feat(backend): add websocket fan-out, FCM push, and invite expiry"
```

---

## Task 9: Docker, Compose, and the backend README

**Files:**
- Create: `backend/Dockerfile`, `backend/README.md`, `backend/.dockerignore`, `docker-compose.yml`, `docker-compose.override.yml`

**Interfaces:**
- Consumes: a fully built backend.
- Produces: a container that migrates then serves on port 3000, and a one-command local stack.

- [ ] **Step 1: Write `backend/Dockerfile`**

The compose file uses `build: ./backend`, so the build context is `backend/` — a `.dockerignore` at
the repo root is **not read**. It must be `backend/.dockerignore`, excluding at minimum
`node_modules`, `dist`, and `src/**/*.test.ts`.

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

Start the api with `CORS_ORIGINS` unset; with a garbage service-account value; with a *structurally
valid but unusable* service account (generate a throwaway RSA key — Google answers `invalid_grant`);
and with `FIREBASE_PROJECT_ID` not matching the service account's `projectId`. All four must exit
non-zero, and all four are testable **without** real credentials — only Step 4's 200 from `/health`
needs them. A container that boots healthy in either case is a Task 3 regression — fix it there.

- [ ] **Step 6: Write `backend/README.md`**

Required environment variables in a table, the local-run command, how to run migrations standalone, and how deploy works (git push → Coolify builds `backend/Dockerfile`). Keep it short.

- [ ] **Step 7: Commit**

```bash
git add backend/Dockerfile backend/README.md backend/.dockerignore docker-compose.yml docker-compose.override.yml
git commit -m "feat(backend): containerize with healthcheck and local compose stack"
```

---

## Task 10: Expo scaffold, routing, guard chain, and store

**Files:**
- Create: `app.config.ts`, `vitest.config.ts` (repo root), `app/_layout.tsx`, `app/auth.tsx`, `app/timezone-setup.tsx`, `app/pairing.tsx`, `app/(tabs)/_layout.tsx` + the **three** tab screens (`index`, `calendar`, `settings`), `app/block-form.tsx`, `src/store.ts`, `src/theme.ts`, `.env.example`
- Modify: `tsconfig.json`, `package.json` (root)

**Interfaces:**
- Consumes: `backend/src/wire.ts` from Task 4, imported type-only.
- Produces:
  ```ts
  // src/store.ts
  import type { UserRow, CoupleRow, BlockWithOccurrences, OverlapWindow } from '../backend/src/wire'

  interface State {
    hydrated: boolean
    user: UserRow | null                          // own row, so fcm_tokens is present
    partner: Omit<UserRow, 'fcm_tokens'> | null    // Home clocks + window detail need their name/tz
    couple: CoupleRow | null
    blocks: BlockWithOccurrences[]
    windows: OverlapWindow[]
    computedAt: number | null
    pendingInviteCode: string | null               // parked across the sign-in round trip
    lastCalendarSyncMs: number | null              // persisted, not in-memory only — see Task 16
    visibleRange: { from: number; to: number } | null   // the Calendar tab's current week
    hydrationError: string | null                  // set on a failed cold start; drives a retry screen
  }
  interface Actions {
    setHydrated(v: boolean): void
    setHydrationError(e: string | null): void
    setUser(u: UserRow | null): void
    setPartner(p: Omit<UserRow, 'fcm_tokens'> | null): void
    setCouple(c: CoupleRow | null): void
    setBlocks(b: BlockWithOccurrences[]): void
    removeBlock(id: string): void
    /** The week the Calendar tab is showing. The WS layer reads it to refetch the right range. */
    setVisibleRange(from: number, to: number): void
    setWindows(w: OverlapWindow[], computedAt: number): void
    setPendingInvite(code: string | null): void
    setLastCalendarSync(ms: number): void
    /** Unpair: keep the authenticated user and their timezone, drop everything couple-scoped. */
    resetCouple(): void
    /** Sign-out: drop everything including the user. */
    reset(): void
  }
  export const useStore: UseBoundStore<StoreApi<State & Actions>>
  ```

Four things this fixes that a naive store gets wrong:

1. **`partner` is a separate slot.** Home renders two clocks and the window detail shows both zones, so
   the partner's row is required state. Critically, a `user:update` WS message can be for *either*
   party — routing it into `user` unconditionally would overwrite the signed-in user with their
   partner's row. Dispatch on `msg.user.uid`.
2. **`resetCouple()` is distinct from `reset()`.** Unpair must leave the user signed in with their
   timezone intact and send them to `/pairing`; sign-out must clear everything. One function cannot do
   both — with only `reset()`, unpairing logs the user out and re-runs timezone setup.
3. **`setHydrated` and `setLastCalendarSync` are declared**, because later tasks mutate both.
4. **There is no `upsertBlock`, deliberately.** A `block:set` broadcast carries a `BlockRow` with no
   `occurrences` — the server cannot know the client's visible week — so merging it into state would
   put an un-renderable block on the grid. Instead the WS handler reads `visibleRange` and calls
   `api.listBlocks(coupleId, from, to)`, replacing the list via `setBlocks`. One extra request per
   partner edit, always correct, no occurrence-merge logic to get wrong. `setVisibleRange` exists so
   the WS layer knows what to refetch; the Calendar tab sets it on every week change. When
   `visibleRange` is null (Calendar never opened), skip the refetch entirely — nothing is rendering
   blocks.

The root `tsconfig.json` **already has** the needed `include` — it was narrowed during Task 4, because
without it tsc swept all of `backend/src` and the app typecheck was meaningless whenever
`backend/node_modules` was absent. Verify it still lists `backend/src/wire.ts` and nothing else from
`backend/`.

**Verify this with `backend/node_modules` absent**, because the app CI job never installs backend
dependencies:

```bash
mv backend/node_modules /tmp/bnm && npx tsc --noEmit ; mv /tmp/bnm backend/node_modules
```

It must pass. This is why `wire.ts` imports engine types from `overlap/types.js` and never from
`overlap/index.js` — `types.ts` has zero imports, while `index.ts` reaches `recurrence.ts` which
imports `rrule`, a package the app deliberately does not have. Also confirm a Metro bundle does not
pull in `pg`: if it does, someone wrote a value import where `import type` was required.

- [ ] **Step 1: Write `app.config.ts`**

Name `Couple Sync`, slug `couple-sync`, scheme `couplesync`, Android package `money.stitch.couplesync` (set the iOS bundle to the same string for later, but do not configure iOS beyond that), the existing `assets/*.png` wired as icon/splash/adaptive icon, and the `@react-native-firebase/app`, `@react-native-google-signin/google-signin`, `expo-notifications`, `expo-build-properties`, `expo-dev-client` plugins. **No `expo-apple-authentication`.** Read **both** `API_BASE_URL` and `GOOGLE_WEB_CLIENT_ID` from `process.env` into `extra`, and list
both in `.env.example`. `@react-native-google-signin` needs the **Web** OAuth client id (not the
Android one) as `webClientId`; sign-in fails at runtime without it. `configureGoogleSignIn()` throws
at module load when it is missing, so the failure is a clear startup error rather than a silent
sign-in that never returns.

- [ ] **Step 2: Build the route tree and the guard chain in `app/_layout.tsx`**

Order per §1, evaluated only once `hydrated` is true:

```
!user                → /auth
!user.timezone       → /timezone-setup
!user.couple_id      → /pairing        // couple_id, snake_case — there is no `coupleId`
otherwise            → /(tabs)
```

While `hydrated` is false, render a splash — never a screen. A wrong-route flash on cold start was a real defect class in the old build's redirect chain.

- [ ] **Step 3: Implement deep-link parking**

`couplesync://invite/:code` must call `setPendingInvite(code)` and survive sign-in. Once authenticated and unpaired, `/pairing` opens on the Enter tab with the code pre-filled, and `setPendingInvite(null)` runs after it is consumed. Handle both cold start (`Linking.getInitialURL`) and warm (`Linking.addEventListener`).

- [ ] **Step 4: Create `google-services.placeholder.json`**

Task 17's CI copies this file, and Task 10's own prebuild check needs it, but no task has created it
until now. Write a minimal, clearly-labelled stub with the structure the plugin copies (it never
parses it) and a `"_comment"` field stating that it is a CI placeholder and not real credentials. Add
`google-services.json` (the real one) to `.gitignore` in the same step.

- [ ] **Step 5: Write the root `vitest.config.ts` now, not in Task 17**

Vitest's default `include` is `**/*.{test,spec}.?(c|m)[jt]s?(x)`, so without this the app's `npm test`
walks into `backend/src/**/*.test.ts` and fails — the app job never installs backend dependencies.
Task 11 is the first task to run `npm test`, so the config has to exist before it.

```ts
import { defineConfig } from 'vitest/config'
export default defineConfig({ test: { include: ['src/**/*.test.ts'], environment: 'node' } })
```

Verify: `npm test` reports 0 app tests and does **not** mention the 135 engine tests.

- [ ] **Step 6: Write `src/theme.ts` and `src/store.ts`**

Theme: colors (light + dark), spacing scale, type scale. Plain objects, no styling library. Store: exactly the interface above, no persistence yet.

- [ ] **Step 7: Create every screen as a one-line stub**

Literally `export default () => <Text>auth</Text>` per screen — six files, one line each. Do **not**
lay out the screens here: Tasks 12–16 rewrite every one of them, and laying them out twice is a
wasted pass. The only files with real content in this task are `_layout.tsx` (the guard chain) and
`(tabs)/_layout.tsx` (the **three**-tab bar: Free time, Calendar, Settings), because those are what
you are actually verifying.

- [ ] **Step 8: Verify**

```bash
npx tsc --noEmit && npx expo-doctor
# prebuild needs a real google-services.json — see the note below before running it
npx expo prebuild --platform android --clean
```

**`expo prebuild` cannot succeed without `google-services.json` on disk.** The
`@react-native-firebase/app` config plugin throws when `android.googleServicesFile` is missing or
points at a nonexistent path, and it only *copies* the file — it never parses it
(`@react-native-firebase/app/plugin/src/android/copyGoogleServices.ts:14`).

Separate the two needs, and point `app.config.ts` at the **real** filename:

```ts
android: { googleServicesFile: './google-services.json' }   // real file, gitignored
```

- **Locally and in any real build:** the developer drops the real `google-services.json` from the
  Firebase console at the repo root. It stays gitignored.
- **In CI**, where no real file exists, the workflow copies the committed placeholder into place
  immediately before prebuild: `cp google-services.placeholder.json google-services.json`.

Do **not** point the config permanently at the placeholder. CI would go green while `expo run:android`
silently consumed a fake config, and Google Sign-In would fail at runtime with nothing explaining why
— blocking Task 12's device walk, not just Task 13's.

A placeholder-driven prebuild proves only that the config plugins *execute*. It is not evidence of a
working native build and must not be reported as one. **Do not** claim prebuild passes without having
run it; if no real file is available, stop at `tsc --noEmit && expo-doctor`, say so explicitly, and
list `google-services.json` under the human prerequisites.

Expected: tsc clean; `prebuild` generates `android/` without error. Report every `expo-doctor` warning
honestly rather than suppressing it.


**`expo prebuild` is the checkpoint, not `expo start`.** `@react-native-firebase/*` ships native
modules, so this app can never run in Expo Go — every later verification step needs a development
build (`npx expo run:android`). Add `expo-dev-client` and confirm the config plugins resolve here, at
the scaffold, rather than discovering it in Task 12 when a screen refuses to load. The Firebase credential file
(`google-services.json`) does not exist yet, so `prebuild` succeeding while `run:android` cannot yet
launch is the expected state — say so in your report. **Android only** — do not prebuild iOS.

- [ ] **Step 9: Commit**

```bash
git add app app.config.ts vitest.config.ts src tsconfig.json package.json .env.example .gitignore google-services.placeholder.json
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
  import type { UserRow, CoupleRow, BlockRow, BlockWithOccurrences, OverlapWindow } from '../backend/src/wire'

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
    redeemInvite(code: string): Promise<{ couple_id: string }>   // snake_case, like every other payload
    /** from/to are REQUIRED — the server needs a range to expand occurrences into. */
    listBlocks(coupleId: string, from: number, to: number): Promise<BlockWithOccurrences[]>
    // coupleId-first, like listBlocks: the server requires it (body on create/patch, query on
    // delete) and Partial<NewBlock> cannot carry a required field.
    createBlock(coupleId: string, b: NewBlock): Promise<BlockRow>
    updateBlock(coupleId: string, id: string, patch: Partial<NewBlock>): Promise<BlockRow>
    deleteBlock(coupleId: string, id: string): Promise<void>
    /** Returns the server's `{ count }` — the number of blocks written, not the rows. */
    putGoogleBlocks(coupleId: string, intervals: { start_utc: number; end_utc: number }[]): Promise<number>
    latestOverlap(coupleId: string): Promise<{ windows: OverlapWindow[]; computed_at: number }>
    registerFcmToken(token: string): Promise<void>
    /** Called on sign-out so a shared handset never keeps a previous user's token. */
    deleteFcmToken(token: string): Promise<void>
  }
  export class ApiError extends Error { status: number; code: string }

  // src/ws.ts
  export function connect(): void       // idempotent; reconnects with backoff
  export function disconnect(): void

  // src/auth.ts
  export const CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar.readonly'
  /** Call once at module load, BEFORE any sign-in:
   *  GoogleSignin.configure({ webClientId, scopes: [CALENDAR_SCOPE] })
   *  Requesting the scope here is what makes login and calendar consent one step. */
  export function configureGoogleSignIn(): void
  export function signInWithGoogle(): Promise<void>
  export function signOut(): Promise<void>
  /** Firebase ID token — for OUR backend only. Cannot authorize the Google Calendar API. */
  export function getIdToken(): Promise<string | null>
  /** Google OAuth access token — for the Calendar API only. Never sent to our backend. */
  export function getGoogleAccessToken(): Promise<string | null>
  export function onAuthChange(cb: (uid: string | null) => void): () => void
  ```

  **Two different tokens, and confusing them is the most likely bug in this task.**
  `getIdToken()` returns a Firebase ID token; the Calendar API rejects it. Calendar calls need
  `const { accessToken } = await GoogleSignin.getTokens()`. `getGoogleAccessToken()` wraps that and
  exists so `src/calendar.ts` never reaches for the wrong one. Add a test asserting the Calendar
  request's `Authorization` header carries the Google access token, not the Firebase ID token.

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
it('refetches the visible range via listBlocks on block:set, and calls setBlocks')
it('refetches exactly once on blocks:changed')
it('does NOT refetch on block:set when visibleRange is null')
it('applies block:del to the store via removeBlock')
it('applies overlap to the store via setWindows')
it('applies user:update to the store')
it('resets the store and routes to /pairing on unpair')
it('refetches user and couple on pairing')
it('ignores a message with an unknown t')
it('calls hydrateFromServer on hello when the server couple_id differs from local')
it('does NOT rehydrate on hello when the server couple_id matches local')   // no refetch storm
it('resetCouple()s on hello when the server reports couple_id null')        // unpaired elsewhere
it('refetches the latest overlap after a reconnect')   // catches anything missed while offline
it('refetches the visible range on blocks:changed')
it('does NOT refetch on blocks:changed when visibleRange is null')
```

- [ ] **Step 4: Implement `src/auth.ts` and wire the sign-in screen**

Google via `@react-native-google-signin/google-signin` → Firebase credential. Request the `calendar.readonly` scope **here, at sign-in**, not later — see Task 12a. `onAuthChange` drives hydration in `_layout.tsx`. **The fetches are conditional** — an unconditional
couple/blocks/windows fetch throws for a first-time or unpaired user (no `couple_id`) and they never
reach their guard:

**One idempotent helper, three callers.** Cold start, the WS `hello`, and a successful invite redeem
all need exactly the same work, so write it once:

```ts
/** Idempotent AND single-flight. Safe to call from cold start, every WS hello, and invite redeem —
 *  including concurrently. Returns the couple_id it settled on.
 *
 *  Two hazards this must close:
 *   (a) concurrent signals. A `pairing` message and a `hello` can arrive together, both observe
 *       local couple_id === null, and both fire the forced first-pair sync. So share one in-flight
 *       promise: if a hydration is already running, await THAT one instead of starting another.
 *   (b) a cold start for an ALREADY-paired couple looks identical to a fresh pairing, because local
 *       state starts null either way. So the transition is judged against an explicit
 *       `authoritativeStateInitialized` sentinel, not against `couple === null`. The very first
 *       hydration only initializes; it never counts as a transition.
 */
let inFlight: Promise<string | null> | null = null
let authoritativeStateInitialized = false

export function hydrateFromServer(): Promise<string | null> {
  inFlight ??= doHydrate().finally(() => { inFlight = null })
  return inFlight
}

async function doHydrate(): Promise<string | null> {
  const me = await api.me()          // authoritative: local user.couple_id may be stale
  setUser(me)
  if (!me.couple_id) { resetCouple(); return null }
  const couple  = await api.getCouple(me.couple_id)
  const [partner, overlap] = await Promise.all([
    api.getUser(partnerUidOf(couple, me.uid)),
    api.latestOverlap(me.couple_id),
  ])
  setCouple(couple); setPartner(partner); setWindows(overlap.windows, overlap.computed_at)

  // Exactly-once first-pair sync: only on a real null -> set transition, and never on the
  // initializing hydration, so an already-paired cold start does not force a sync.
  const isTransition = authoritativeStateInitialized && previousCoupleId === null
  if (isTransition) void calendar.sync(me.couple_id, { force: true })

  return me.couple_id
}
```

**`authoritativeStateInitialized` must be set on BOTH branches** — the unpaired early return as well
as the paired path. Setting it only after the paired branch means an *unpaired* cold start (the
inviter — precisely the case the forced first sync exists for) leaves it false, so the pairing that
follows is misread as the initializing hydration and the sync never fires. Set it in a `finally`.

`previousCoupleId` is read from the store *before* `setUser`. Tests:

```ts
it('does not force a sync on a cold start for an already-paired couple')
it('forces exactly ONE sync when pairing and hello arrive concurrently')
it('forces a sync on the first genuine null -> set transition')
it('does not force a sync on a reconnect reporting the same couple_id')
it('shares one in-flight hydration when called twice concurrently')
```

Cold start:

```
uid arrives
  → ws.connect()          // BEFORE anything couple-related. An unpaired inviter needs a live socket
                          // or they never receive `pairing` and sit on the pairing screen forever.
  → try { await api.verify(); await hydrateFromServer() }
    catch (e) { setHydrationError(e) }     // NEVER leave the splash up forever
    finally  { setHydrated(true) }          // an error still renders something (a retry screen)
  → then, not blocking hydration: notifications + auto-sync (Task 13)
```

Blocks are **not** fetched here — they need a `from`/`to` range and only the Calendar tab knows one.
`partnerUidOf` returns whichever of `user_a_uid`/`user_b_uid` is not you.

The store needs `hydrationError: string | null` + `setHydrationError`, and the root layout renders a
retry screen when it is set. (A partner deleting their *Firebase* account leaves our `users` row
intact, so `getUser` keeps working — this path is about real failures, not account deletion.)

On sign-out: `disconnect()`, remove this device's FCM token server-side (see Task 13), then `reset()`.

- [ ] **Step 5: Write `src/time.ts`**

luxon helpers only — format a window range in a given zone, a live clock string, a relative countdown, and a block's `{ dayIndex, topMinutes, heightMinutes }` for the week grid. **No interval algebra** (§0.1): no merging, no intersecting, no recurrence expansion.

- [ ] **Step 6: Verify and commit**

```bash
npx tsc --noEmit && npm test
git add src app tsconfig.json
git commit -m "feat(app): add api client, websocket client, firebase auth and time helpers"
```

---

## Human prerequisites before Task 12

Tasks 1–11 need none of this. Task 12 onward runs on a real device, so a person must supply these
first — a subagent cannot obtain any of them, and every one of them fails *silently* if missing:

| Prerequisite | Why | Symptom when absent |
|---|---|---|
| `google-services.json` from the Firebase console | RNFirebase native config | prebuild throws, or Firebase no-ops at runtime |
| **Web** OAuth client id in `GOOGLE_WEB_CLIENT_ID` | `@react-native-google-signin` needs the Web id, not the Android one, as `webClientId` | sign-in never resolves |
| Debug **and** release SHA-1 fingerprints registered in Firebase | Android Google Sign-In verification | sign-in fails with no useful error — the single most common setup mistake |
| Google Calendar API enabled in the GCP project | `freeBusy.query` | 403 on every sync |
| Backend reachable at `API_BASE_URL` with valid `FIREBASE_SERVICE_ACCOUNT_JSON` | every request | 401 everywhere |
| An Android emulator or device with Google Play services | Google Sign-In + FCM | sign-in unavailable |
| A real Google account with some calendar events | proving the sync end to end | an empty but "successful" sync |
| A **second** account or device | pairing, and every two-sided WS path | pairing untestable |

If any are missing, stop and report which. Do not simulate a device walk or report it as passing.

---

## Human prerequisites

A subagent cannot obtain any of these, and nearly all of them fail *silently*. They are needed at two
different points, so they are listed by the first task that cannot complete without them.

**Needed by Task 9** (the container healthcheck mints a real Google OAuth token at boot — the
credential probe is not offline):

| Prerequisite | Symptom when absent |
|---|---|
| A real Firebase service account in `FIREBASE_SERVICE_ACCOUNT_JSON`, matching `FIREBASE_PROJECT_ID` | the container fails its own boot probe by design |
| Outbound network access to Google's token endpoint from the container | boot probe times out |
| `CORS_ORIGINS` set to something other than `*` | boot refuses to start by design |

Tasks 1–8 need none of the above — they mock `firebase.js` — and Tasks 10–11 need none of it either.

**Needed by Task 12** (first task that runs on a device):

| Prerequisite | Why | Symptom when absent |
|---|---|---|
| The real `google-services.json` | RNFirebase native config | prebuild throws, or Firebase no-ops at runtime |
| **Google** sign-in provider *enabled* in Firebase Auth | it is off by default | sign-in rejected with an opaque error |
| OAuth consent screen configured, with test users added while the app is unpublished | Google blocks unlisted testers | consent screen refuses the account |
| **Web** OAuth client id in `GOOGLE_WEB_CLIENT_ID` | the library needs the Web id, not the Android one | sign-in never resolves |
| Debug **and** release SHA-1 fingerprints registered in Firebase | Android sign-in verification | fails with no useful error — the most common setup mistake |
| Google Calendar API enabled in the GCP project | `freeBusy.query` | 403 on every sync |
| Backend reachable at `API_BASE_URL` | every request | 401/timeout everywhere |
| An emulator or device **with Google Play services** | Google Sign-In + FCM | sign-in unavailable |
| A real Google account with actual calendar events | proving sync end to end | an empty but "successful" sync |
| A second Google account **and** a second device/emulator | pairing needs two authenticated sessions at once, and WS fan-out needs two live sockets — one device cannot do it | pairing and every two-sided path untestable |

If any are missing, stop and report exactly which. Do not simulate a device walk, and do not report a
step as passing because it "should" work.

---

## Task 12: Onboarding screens — auth, timezone, pairing

**Files:** `app/auth.tsx`, `app/timezone-setup.tsx`, `app/pairing.tsx`, `src/timezones.ts`

**Interfaces:** Consumes `api`, `src/auth.ts`, `store`. Produces nothing later tasks depend on.

- [ ] **Step 1: Finish `app/auth.tsx`** — **one** Google sign-in button, a loading state, and an inline error message on failure. No Apple button, no email/password, no anonymous. One button is the whole screen; do not build a provider-list abstraction for a single provider.
- [ ] **Step 2: Write `src/timezones.ts`** — the IANA zone list grouped by region with a search filter. Use `Intl.supportedValuesOf('timeZone')` rather than shipping a hand-maintained list.
- [ ] **Step 3: Finish `app/timezone-setup.tsx`** — pre-select `expo-localization`'s detected zone, offer a searchable override, `api.patchUser` on confirm. Show each candidate's current local time so a wrong pick is obvious.
- [ ] **Step 4: Finish `app/pairing.tsx`** — Share tab (`api.createInvite`, show the code + expiry, copy button, `Share.share` with the `couplesync://invite/<code>` link) and Enter tab (6-char input, `api.redeemInvite`, distinct messages for expired / already-used / self-pair / already-paired). Consume `pendingInviteCode` when present.

**Both sides must navigate, by different routes.** The *inviter* is moved by the WS `pairing`
message (which is why hydration connects the socket before the `couple_id` branch). The *redeemer*
gets only an HTTP `{ couple_id }` response — no WS message goes to themselves — so on success
`redeemInvite` hydrates directly:

```
redeemInvite(code) -> { couple_id }
  → await hydrateFromServer()      // the SAME helper cold start uses. api.me() first is essential:
                                   // the local row still has couple_id null and the guard reads it,
                                   // so without the refetch the redeemer stays on /pairing.
```

The inviter is moved by the WS `pairing` message, and **`hello` is the safety net** for when that
message is missed — the socket may still be fetching its token when the redemption lands, or the
inviter may be offline entirely. On every `hello`, compare the server's authoritative `couple_id` to
local state and call `hydrateFromServer()` when they differ. Without that reconciliation the inviter
can stay locally unpaired indefinitely, and no amount of correct `pairing` delivery fixes the missed
case.

**Do not fetch blocks here** — `listBlocks` requires a `from`/`to` range and none exists until the
Calendar tab opens and sets `visibleRange`. **No polling loop** either way; the old build polled
every 3 s.

The forced first-pair calendar sync is **not** wired in this task — `src/calendar.ts` does not exist
until Task 13, which owns adding it to both pairing paths.
- [ ] **Step 5: Verify** — `npx tsc --noEmit`, then run on a simulator and walk sign-in → timezone → pairing.
- [ ] **Step 6: Commit** — `git add app src && git commit -m "feat(app): implement auth, timezone setup and pairing screens"`

---

## Task 13: Google Calendar connect + sync (the core product loop)

**Files:**
- Create: `src/calendar.ts`, `src/notifications.ts`
- Modify: `app/_layout.tsx` (auto-sync + notification wiring), `app/pairing.tsx` (forced sync after
  redeem), `src/ws.ts` (forced sync when `hello`/`pairing` reports a couple_id **transition**, not on
  every hello), `src/auth.ts` (delete the FCM token and clear the persisted limiter on sign-out),
  `src/store.ts` (clear `lastCalendarSyncMs` in both `reset()` and `resetCouple()`), `app/(tabs)/index.tsx`
  and `app/(tabs)/settings.tsx` (the `ensureScope` prompt row)
- Test: `src/__tests__/calendar.test.ts`, `src/__tests__/notifications.test.ts`

Every one of those modifications exists because something in this task must be *called* from
somewhere; an earlier draft of this plan produced the modules and wired none of them up, which is how
the previous build shipped notifications that existed only as an interface.

This task moved ahead of the screens deliberately. *Connect Gmail → pull free/busy → show free spots*
**is** the product; a Home screen with no calendar data is a demo. Build the data source first.

**Interfaces:** as specified in Task 16 below for `src/calendar.ts` and `src/notifications.ts` — that
task now owns only the Settings screen, so implement both modules here and read Task 16's interface
block and its Step 1/Step 2 detail as this task's specification.

- [ ] **Step 1 (executed in Task 13): `src/calendar.ts`** — per Task 16 Step 1 in full, including the persisted
      rate limit and the seven client-side privacy tests.
- [ ] **Step 2 (executed in Task 13): `src/notifications.ts`** — per Task 16 Step 2 in full.
- [ ] **Step 3: Wire both into `app/_layout.tsx`** — per the call table in Task 16's Interfaces block.
      Auto-sync on launch when `lastCalendarSyncMs` is over an hour old.
- [ ] **Step 4: Do NOT build a connect-calendar screen**

There is nothing to connect. Google sign-in already granted `calendar.readonly`, so a "connect your
calendar" screen would be a button that re-does what login did. Instead, `src/calendar.ts` exposes
`ensureScope()` for the one real case — the user declined the calendar consent while completing
sign-in, or revoked it later from their Google account — and the Free time screen renders that as a
single inline row. One row, no screen, no router guard, nothing to get trapped behind.

State the privacy sentence ("we read only busy/free times, never event titles") on the **auth**
screen, next to the sign-in button, where the consent actually happens.
- [ ] **Step 5: Verify on Android** — `npx expo run:android`; sign in, connect a real Google account,
      and confirm busy blocks appear via `GET /blocks`. Confirm the request log shows `freeBusy` and
      never `events`.
- [ ] **Step 6: Commit** — `git add app src && git commit -m "feat(app): add google calendar sync and notifications"`

---

## Task 14: Free time screen

**Files:** `app/(tabs)/index.tsx`, `src/components/WindowCard.tsx`

**Interfaces:** Consumes `store.windows`, `store.user`, `store.partner`, `api`, `src/time.ts`, `src/calendar.ts`.

One screen, not two. Home and a separate Overlap tab both rendered a list of windows differing only
in length and a filter — that is one screen with a filter.

The **countdown and "next window"** must pick the earliest `startUtc`, not `windows[0]` — the list is
score-sorted (see Global Constraints). Sort a copy by time for the countdown; keep score order for the
list itself, since that is what makes the good windows surface first.

- [ ] **Step 1: Build `WindowCard`** — start/end in both partners' zones, duration, score-derived emphasis, and a late-night marker when `reasonableBoth` is false. The marker is text or an icon, never colour alone.
- [ ] **Step 2: Build the screen** — both partners' live clocks (tick once a **minute**, not once a second), a countdown to the next window, then the full window list with an any/30m/1h/2h filter (display-only per §0.7). **Drop any window whose `endUtc` is already past** before rendering — §9 notes the stored row can lag the clock.
- [ ] **Step 3: Build the three empty states, which are the whole UX of this screen** — (a) `sync` returned `'scope-missing'` → an inline "Allow calendar access" row calling `ensureScope()`, above the list rather than replacing it, since manual blocks may still produce windows; (b) no windows → "you two have no shared free time in the next 14 days", with a link to the Calendar tab to review blocks; (c) loading → a skeleton, never a bare spinner over an empty list.
- [ ] **Step 4: Pull-to-refresh runs both** `calendar.sync(coupleId)` and `api.latestOverlap(coupleId)`, in that order. Refreshing windows without re-syncing the calendar is the bug a user will report as "it's out of date".
- [ ] **Step 5: Verify on Android** — `npx expo run:android`; check all three empty states and that the clocks show two different zones.
- [ ] **Step 6: Commit** — `git add app src && git commit -m "feat(app): implement free time screen"`

---

## Task 15: Calendar week view and block form

**Files:** `app/(tabs)/calendar.tsx`, `app/block-form.tsx`, `src/components/WeekGrid.tsx`, `src/components/RecurrencePicker.tsx`

**Interfaces:** Consumes `store.blocks` (`BlockWithOccurrences[]`), `store.windows`, `src/time.ts`, `api.createBlock`/`updateBlock`/`deleteBlock`.

The calendar **is** the block-management surface — there is no separate Blocks tab. Tapping a block
edits it; the FAB creates one.

- [ ] **Step 1: Build `WeekGrid`** — 7 day columns × 24 hour rows in the viewer's timezone. Render from each block's **server-supplied `occurrences`** array (Task 7 Step 3), never from `recurrence_rule`; the client cannot expand recurrence and must not try. Overlap windows layer underneath the blocks.
- [ ] **Step 2: Fetch the visible range** — `GET /blocks?coupleId=X&from=<weekStart>&to=<weekEnd>` on every week change, so occurrences always cover what is on screen. Anchor page 0 to a fixed epoch Monday so paging is deterministic; add a "today" jump.
- [ ] **Step 3: Wire the taps** — own block → `block-form` prefilled; google-sourced block → a read-only sheet with no edit affordance; partner's `onlyMe` block → "Busy", no title (the server already nulled it, so there is nothing to hide client-side); window → the same detail sheet as Task 14; FAB → empty `block-form`.
- [ ] **Step 4: Build `RecurrencePicker`** — none / daily / weekly (with weekday selection) / monthly, emitting an RRULE string. Emit **only** rules the backend accepts (§3.2), since Task 7 rejects anything else at write time.
- [ ] **Step 5: Build `block-form`** — title, type, category, start/end pickers in the user's zone, the recurrence picker, and a visibility toggle whose helper text says plainly that `onlyMe` hides the title from your partner but still blocks out the time. Validate non-empty title and `end > start` locally; surface the server's 400 when it rejects anyway. Delete lives here, behind a confirm.
- [ ] **Step 6: Verify on Android** — `npx expo run:android`; create a weekly block and confirm it appears on **every** expected day (this is what proves server-side expansion works end to end); confirm a DST week does not visually shift; confirm the free-time list updates over the WS without a manual refresh.
- [ ] **Step 7: Commit** — `git add app src && git commit -m "feat(app): implement calendar week view and block form"`

---

## Task 16: Settings

**Files:** `app/(tabs)/settings.tsx`

`src/calendar.ts` and `src/notifications.ts` are built in **Task 13**; the interface block and Steps 1–2 below are their specification and Task 13 executes them. This task builds only the screen that drives them.

**Interfaces:**
- Produces:
  ```ts
  // src/calendar.ts — no connect/disconnect/isConnected: the Google login IS the grant.
  /** True when the current Google grant still includes calendar.readonly. */
  export function hasCalendarScope(): Promise<boolean>
  /** GoogleSignin.addScopes({ scopes: [CALENDAR_SCOPE] }) — note the OBJECT argument; an array
   *  does not compile (google-signin/src/types.ts:88). The only correct use of addScopes here: a
   *  user who declined at sign-in or revoked later. On success the caller syncs immediately with
   *  { force: true }. Resolves false on user cancellation — never throws for that. */
  export function ensureScope(): Promise<boolean>
  /** freeBusy.query on the primary calendar for the next 14 days → PUT /blocks/google.
   *  'rate-limited' when the stored last sync is under an hour old.
   *  'scope-missing' when the grant lacks calendar.readonly — caller offers ensureScope(). */
  export function sync(coupleId: string, opts?: { force?: boolean }):
    Promise<'synced' | 'rate-limited' | 'scope-missing' | 'no-session'>

  // src/notifications.ts
  export function requestPermissionAndRegister(): Promise<void>
  export function attachTapHandler(): () => void     // routes a tap to /(tabs) — the Free time tab.
                                                     // NOT /overlap: that route no longer exists.
  ```

**Every one of these must be called from somewhere.** An earlier draft of this task produced them
and wired none of them up, which is how the old build ended up with notifications that existed only
as an interface. This task therefore also modifies `app/_layout.tsx` and `app/(tabs)/index.tsx`:

| Call | Where | When |
|---|---|---|
| `requestPermissionAndRegister()` | `app/_layout.tsx`, after hydration | once per launch, when signed in |
| `attachTapHandler()` | `app/_layout.tsx` mount | returns a cleanup, called on unmount |
| `sync(coupleId)` | `app/_layout.tsx`, after hydration | launch, only if `lastCalendarSyncMs` is over 1 h old (§5 auto-sync) |
| `ensureScope()` | Free time screen's inline prompt, and Settings | only when `sync` returned `'scope-missing'`; on success sync immediately with `{ force: true }` |
| `sync(coupleId, { force: true })` | on a couple_id **transition** from null to set — covers the redeemer's HTTP result, the inviter's `pairing` message, and a `hello` that reconciles a missed pairing, without firing again on every reconnect | a brand-new couple has zero google blocks; waiting up to an hour to populate them makes the app look broken at the exact moment the user first sees it |

**Clear the persisted limiter on unpair and on sign-out.** Unpair deletes the couple's blocks, so a
stale `lastCalendarSyncMs` would suppress the re-sync that repopulates them after re-pairing — the
user would see an empty calendar and a "synced 20 minutes ago" label. `resetCouple()` and `reset()`
both clear it.
| `sync(coupleId)` | `app/(tabs)/index.tsx` pull-to-refresh | alongside `latestOverlap`, not instead of it |
| `sync(coupleId, { force: true })` | Settings "Sync now" | one of exactly **three** allowed `force` callers |

`force` has exactly three permitted callers — the Settings button, a successful `ensureScope()`, and
first pairing — all listed in the table above. Comment it as such. It must never be passed from a
render path, an effect that can re-run, or a retry loop.

- [ ] **Step 1 (executed in Task 13): `src/calendar.ts`**

The scope is **already granted at sign-in** via `GoogleSignin.configure({ scopes: [CALENDAR_SCOPE] })` — this module does not escalate anything. It only spends the grant.

Call **only** `freeBusy.query` on `primary` for `now → now + 14d`, authorized with
`await getGoogleAccessToken()` (the Google OAuth access token, **not** the Firebase ID token). Map
each returned busy interval to `{ start_utc, end_utc }` epoch-ms and `PUT /blocks/google`.
**Never call `events.list`, never read a `summary` field.** Exponential backoff on 429/503.

**Carve-out to the global "never an ISO string" rule:** `freeBusy.query` *requires* RFC3339
`timeMin`/`timeMax`, so this one outbound third-party request uses ISO strings. Convert at the
boundary — `DateTime.fromMillis(ms, { zone: 'utc' }).toISO()` on the way out, back to epoch ms on the
way in. The rule governs *our* wire format; it cannot govern Google's.

**Persist the rate limit, do not hold it in a module variable.** An in-memory timestamp resets on
every app launch, which is exactly when auto-sync fires — so the ≤1 call/hour rule would be broken by
the very code path it exists to protect. Store `lastCalendarSyncMs` in `expo-secure-store` and read
it before deciding.

**The quota rule, stated precisely, because an earlier draft of this plan contradicted itself.**
§5 originally said "≤1 freebusy call per user per hour" full stop, while three separate places then
passed `{ force: true }`. The rule is now:

> **At most one *automatic* freebusy call per device per hour.** User-initiated and
> state-transition syncs additionally bypass the limiter: the Settings "Sync now" button, a
> successful `ensureScope()`, and the moment a couple first pairs. There are exactly three such
> callers and each corresponds to a discrete user action, so they cannot loop.

This is an explicit amendment to §5, recorded in the spec — not an oversight. It costs at most a
handful of extra calls against a 1-unit-per-call quota, and the alternative (a brand-new couple
staring at an empty calendar for up to an hour) is worse.

Two ceilings written down rather than solved:
- The limiter is **per device**, not per user, so a phone plus a tablet gets two automatic calls an
  hour. Server-side enforcement needs a last-sync column on `users`; that is the upgrade path.
- `resetCouple()` clears the persisted timestamp, so repeated pair/unpair cycles could force repeated
  syncs. Pairing requires a partner to redeem a fresh 6-char invite each time, which makes this
  expensive to abuse and self-limiting. If it ever matters, move the timestamp server-side.

**Handle the Google session explicitly — `getTokens()` rejects, it does not return null.** On Android
it throws when there is no cached account, and can throw during token recovery
(`RNGoogleSigninModule.java:300`). Those are expected states, not crashes: catch them and map to a
return value. On cold start, restore the session with `GoogleSignin.hasPreviousSignIn()` /
`signInSilently()` before the first `getTokens()`.

```ts
// src/__tests__/calendar.test.ts — mock the Google client
it('restores the Google session on cold start before requesting tokens')
it('returns no-session when there is no cached Google account')
it('returns scope-missing when the calendar scope was declined at sign-in')
it('returns scope-missing when the scope was revoked after having been granted')
it('returns scope-missing rather than leaking a native error when getTokens() rejects')
it('authorizes the Calendar request with the Google access token, NOT the Firebase ID token')
it('calls freeBusy.query and never events.list')
it('queries only the primary calendar')
it('sends timeMin/timeMax as RFC3339 strings')          // the documented ISO carve-out
it('sends no title field in the PUT /blocks/google payload')
it('returns rate-limited without calling the API when the stored sync is 30 minutes old')
it('calls the API when the stored sync is 90 minutes old')
it('calls the API regardless of the stored sync when force is true')

// src/__tests__/auth.test.ts — the scope assertion belongs HERE, at configure time
it('configures GoogleSignin with exactly [CALENDAR_SCOPE] as the additional scopes')
it('fails fast when the web client id is not configured')
```

Assert the **additional configured scopes**, not the final grant: Google Sign-In always adds identity
scopes of its own (`Utils.java:63`), so asserting "no email/profile scope" would fail against correct
behaviour.

- [ ] **Step 2 (executed in Task 13): `src/notifications.ts`**

Request permission, get the FCM token, `api.registerFcmToken`, and re-register on `onTokenRefresh`.

**Delete the token server-side on sign-out**, before clearing local auth. Without it, one physical
device's token stays attached to the previous user's row: sign out, sign in as the partner, and that
handset receives pushes meant for someone else — a privacy leak, not just noise. This needs
`DELETE /auth/fcm-token` (body `{ token }`, self-only), added in Task 6.

Foreground notifications **must actually display** — the previous build wired a display interface that
production never populated, so foreground notifications were silently dead. Test that display is
genuinely invoked, not merely that a function was called.

```ts
// src/__tests__/notifications.test.ts
it('registers the token after permission is granted')
it('re-registers on onTokenRefresh')
it('deletes the token server-side on sign-out, before clearing auth')
it('actually invokes the display API for a foreground message')
it('routes a notification tap to the Free time tab, not a nonexistent /overlap route')
```

- [ ] **Step 3: Build Settings**

Four groups, in this order. **Calendar**: the signed-in Google account email, last-sync time, and "Sync now" (the only caller allowed `{ force: true }`). **No connect or disconnect control** — the calendar grant is the login, so disconnecting means signing out. If `hasCalendarScope()` is false, show an "Allow calendar access" row calling `ensureScope()` instead. **You**: timezone (searchable, shows current local time per candidate), late-night-windows toggle via `api.patchUser({ show_late_night_windows })`. **Notifications**: one toggle calling `api.patchUser({ notifications_enabled })` — it must change *server* behaviour, not local state (§0.5). **Couple**: partner name, unpair behind a confirm naming what is deleted, sign out.

On a successful unpair response, the initiator calls `resetCouple()` **locally and immediately** —
do not wait for a WS `unpair` message, because that message is addressed to the partner and the
initiator may have no live socket. The partner's own `resetCouple()` is driven by the WS message.

Every row is a plain labelled control. No settings-schema abstraction for nine rows.

- [ ] **Step 4: Verify each toggle end-to-end on Android**

`npx expo run:android`. Flip notifications off and assert the server stops pushing (check the backend log, not the UI). Flip late-night on and assert the free-time list visibly gains windows. Change timezone and assert the windows shift. **All three were fake or dead in the old build** — a toggle that only writes local state is the exact defect being fixed, so prove each one reaches the server.

- [ ] **Step 5: Commit** — `git add app src && git commit -m "feat(app): implement settings screen"`

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
# job: app      — npm ci; npx tsc --noEmit; npm run lint; npm test;
#                 cp google-services.placeholder.json google-services.json   <-- CI only
#                 npx expo prebuild --platform android --no-install
#                 (the prebuild step is what catches config-plugin breakage; without it a broken
#                  app.config.ts or a missing googleServicesFile lands with CI fully green)
```

**Two config files must exist or both app steps fail, and they are this task's real work:**

1. `eslint.config.mjs` — ESLint 9 requires flat config. There is none, so `npm run lint` currently
   exits 2 and the CI job would be red on its first run:
   ```js
   import expo from 'eslint-config-expo/flat.js'
   export default [...expo, { ignores: ['backend/**', 'dist/**', 'ios/**', 'android/**'] }]
   ```
2. The root `vitest.config.ts` already exists — Task 10 Step 4 created it, because Task 11 is the
   first task to run `npm test` and would otherwise collect the backend suite. Just confirm it is
   still restricting `include` to `src/**/*.test.ts`.

Run all of it locally before pushing — `npm run lint`, `npm test`, and the Android prebuild must exit
0, and `npm test` must report only app tests, never the 135 engine tests. Also confirm the app
typecheck passes with `backend/node_modules` moved aside, since the CI app job never installs backend
dependencies.

- [ ] **Step 2: Delete the stale Flutter git hooks; do not replace them**

`.githooks/pre-commit` and `pre-push` were deleted in Task 1 because they ran `flutter analyze` and
`dart format`. Do **not** write TypeScript replacements. CI (Step 1) already gates build and tests on
every PR, and a pre-push hook that runs the full suite is friction that gets `--no-verify`'d within a
week — at which point it gates nothing while still costing everyone time. `commit-msg` stays as-is:
it is fast, it enforces the conventional-commit format, and CI cannot retroactively fix a bad commit
message.

- [ ] **Step 3: Write `README.md`**

What the product is, the two-deployable layout, how to run the backend locally (one compose command), how to run the app (`npm start`), the required environment variables, and the human-only setup steps: `google-services.json` from the Firebase console, the Android OAuth client ID **plus a Web client ID** (`@react-native-google-signin` needs the Web one as `webClientId`), the debug and release SHA-1 fingerprints registered in Firebase (Google Sign-In fails silently without them — the single most common setup mistake), and enabling the Google Calendar API in the GCP project. iOS setup is deliberately out of scope.

- [ ] **Step 4: Write `CLAUDE.md`**

Replace the deleted Flutter version. Correct stack, correct commands, the **server-side** overlap architecture, `pnpm` for the backend and `npm` for the app, and the standing decisions from §0. Every command in it must be one you have actually run.

- [ ] **Step 5: Fix `docs/deployment/coolify.md`, which actively contradicts the code**

It documents `CORS_ORIGINS` as optional and "defaults to `*`" — `config.ts` requires it and rejects
`*`, so following that doc yields a container that refuses to boot. It also describes a Flutter web
app, a root `Dockerfile`, and `lib/**` / `pubspec.yaml` watch paths, none of which exist. Rewrite it
for the current backend or delete it; a deploy doc that produces a dead container is worse than none.

- [ ] **Step 6: Mark the stale docs**

`PRD.md` and `ARCHITECTURE.md` both describe Flutter, Firestore and device-side compute. Add a one-line header to each: superseded by `docs/REBUILD-SPEC.md`, retained for product history only. Leaving them unmarked is how the contradictions in this rebuild started.

- [ ] **Step 7: Verify CI is actually green**

Push the branch and confirm both jobs pass. A red pipeline here means an earlier task's tests only ever ran locally.

- [ ] **Step 8: Commit** — `git add .github .githooks README.md CLAUDE.md AGENTS.md PRD.md ARCHITECTURE.md docs/deployment eslint.config.mjs && git commit -m "ci: gate backend and app tests; rewrite project docs"`

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
