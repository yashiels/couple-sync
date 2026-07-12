# Couple Sync Cleanup & Critical Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the couple-sync repo's stale instruction layer (docs/CI describe a deleted Firebase Functions backend), delete the junk, fix the critical data/crash bugs, and harden the backend container — so the repo stops lying to its agents and the app behaves correctly.

**Architecture:** Flutter app talks to a self-hosted **Fastify + Postgres + WebSocket** backend in `backend/` (Firebase Admin used only for Auth token verification + FCM). Overlap is computed on-device and published over WS; the server validates shape, dedups, stores, and fans out. **All server-side time is UTC (ms-since-epoch ints); the device renders in the device's local IANA timezone.** The backend runs as a lightweight Docker container (multi-stage, non-root).

**Tech Stack:** Flutter `^3.11.0`, Riverpod, go_router, `package:timezone`; Fastify 4, pg, node-cron, firebase-admin, pino, vitest, pnpm, Node 22, Postgres, Docker.

## Global Constraints

- **Server-side time is UTC everywhere** (BIGINT ms-since-epoch). **Device renders in device-local IANA timezone.** No server-side local-TZ math.
- **Backend container = lightweight**: multi-stage build, non-root runtime user, `--frozen-lockfile`, prod-only deps in runtime stage.
- **Backend package manager = pnpm** (never npm). Tests via `vitest`. No ESLint config exists — do not claim one does.
- **Flutter project**: `nexion-ai-prod` Firebase project (Auth + FCM + hosting only — no Firestore, no Functions).
- **Commit format**: `<type>(<scope>): <message>` conventional commits (no `[TICKET]` suffix on the `feature/ui-cleanup` branch unless a ticket is introduced).
- **No new dependencies** without justification in the task. YAGNI. Deletion over addition.
- **Trust boundary**: the server trusts client-computed overlap windows (shape-validated only). This is an accepted 2-person-app trade-off — do NOT add server-side recompute in this plan.

---

## File Structure

**Backend (`backend/`):**
- `backend/src/migrations/001_init.sql` — modify: `users.timezone` default `'UTC'` → `''` (fresh DBs only).
- `backend/src/migrations/002_timezone_default_empty.sql` — create: `ALTER TABLE users ALTER COLUMN timezone SET DEFAULT ''` (changes the column default only — does NOT touch existing rows; see Task 4 for why a data flip is unsafe).
- `backend/src/migrate.ts` — modify: run ALL `migrations/*.sql` files in lexical order (currently hardcodes `001_init.sql` only, so any new migration file is silently ignored).
- `backend/src/routes/invites.ts` — modify: reject redeem when inviter or redeemer is already paired (guard in the happy-path `else` branch).
- `backend/src/routes/blocks.ts` — modify: run `PUT` body through `readInt`/`readString` validators.
- `backend/src/routes/users.ts` — modify: broadcast partner update with `includeFcm=false`.
- `backend/src/cron.ts` — modify: `cron.schedule(..., { timezone: 'UTC' })`; constant-time admin-token compare.
- `backend/src/auth.ts` — modify: delete unused `authPreHandler` (or wire it — Task 7 decision).
- `backend/src/routes/sync.ts` — modify: handle `pairing`/`unpair`/`user:update` WS messages; drop the 10s poll dependency (Task 10).
- `backend/src/__tests__/{pairing,blocks,users,cron}.test.ts` — modify/extend: cover the new guards.
- `backend/Dockerfile` — modify: non-root runtime user + HEALTHCHECK.
- `backend/README.md` — modify: fix admin-route path mismatch (`/admin/cleanup` not `/admin/cleanup-invites`).

**Flutter (`lib/`):**
- `lib/core/models/user_model.dart` — modify: `displayName` → `String?`; extract `_parseDateTime` (Task 5 only fixes the cast; extraction deferred).
- `lib/features/blocks/screens/blocks_screen.dart` — **delete** (dead placeholder).
- `lib/features/blocks/screens/block_management_screen.dart` — wire into navigation (Task 8).
- `lib/features/home/screens/home_screen.dart` — modify: `context.go(AppRoutes.blockForm)` → `context.push`; add "Manage Blocks" entry.
- `lib/core/router/routes.dart` — modify: remove dead `goToBlocks`/`goToBlockForm` extensions or wire them.
- `lib/features/blocks/widgets/block_list_tile_widget.dart`, `lib/features/calendar/block_event_widget.dart` — modify: replace inline `_getCategoryColor` with `AppTheme.getCategoryColor`.
- `lib/services/providers/auth_state_provider.dart` — modify: `hasTimezone` treats `''` as unset; delete dead `isLoadingProvider`.
- `lib/services/providers/calendar_provider.dart` — modify: delete dead `calendarConnectionProvider` if confirmed unused (Task 8 verification step).

**Repo-level:**
- `CLAUDE.md`, `ARCHITECTURE.md`, `AGENTS.md`, `.agents/startup-context.md`, `BACKLOG.md`, `README.md`, `wiring-checklist.json` — rewrite to reflect Fastify+Postgres+WS.
- `.github/workflows/ci.yml` — replace broken jobs.
- `.github/workflows/deploy-backend.yml` — delete (triggers on non-existent paths).
- `scripts/run-e2e-tests.sh`, `infra/scripts/deploy-functions.sh`, `infra/scripts/deploy-rules.sh` — delete.
- `.baseline-failures.txt`, `.baseline-gate.log` — delete + gitignore.

**Deferred (separate plan, noted at end):** `SyncService` god-object split into per-domain repositories; Hive → `isar`/`shared_preferences` migration (Hive is archived); full localization (ARB/i18n); a11y `Semantics` sweep; `flutter_localizations` wiring.

---

## Task 1: Rewrite the stale instruction layer (docs)

The entire doc layer describes a deleted `functions/` + Firestore backend. Every agent that reads it is misled. This is the single highest-leverage agentic-repo fix.

**Files:**
- Modify: `CLAUDE.md`, `ARCHITECTURE.md`, `AGENTS.md`, `.agents/startup-context.md`, `BACKLOG.md`, `README.md`, `wiring-checklist.json`

**Truth source:** `backend/README.md` + `backend/src/` + the audit findings. The backend computes nothing; the device computes overlap and publishes over WS.

- [ ] **Step 1: Rewrite `README.md`** (currently default `flutter create` boilerplate). Replace with: one-paragraph product description (long-distance couples, mutual free time), the stack (Flutter + Fastify + Postgres + WS, Firebase Auth/FCM/hosting only), and quickstart — `make deps`, `make backend-build`, `make backend-test`, `flutter run`, link to `PRD.md`/`ARCHITECTURE.md`. Keep under ~60 lines.

- [ ] **Step 2: Rewrite `CLAUDE.md`** File Structure + Build/Test + Notes sections. The `lib/` structure stays (still accurate). Replace the `functions/` block and all `firebase deploy --only functions/firestore` commands with:
  ```
  Backend (backend/, self-hosted Fastify + Postgres + WebSocket):
    cd backend && pnpm install      # Install deps
    pnpm build                      # tsc → dist/
    pnpm test                       # vitest
    # No ESLint config yet — do not run `npm run lint` (it does not exist).
  
  # Run locally (bundled postgres):
  docker compose -f docker-compose.yml -f docker-compose.override.yml up
  
  # Deploy: Coolify auto-builds on push (see deploy.sh). No `firebase deploy --only functions`.
  ```
  Replace Notes: "Data layer = Postgres via Fastify backend (`lib/services/sync_service.dart`). Firebase Auth + FCM + hosting only. Security enforced server-side via `backend/src/couples.ts assertMember()`, not Firestore rules (no rules file exists, none needed)."

- [ ] **Step 3: Rewrite `ARCHITECTURE.md`** system diagram + "Core Components" + "Data Model" + "Security Model" + "Deployment" sections. New diagram (text):
  ```
  Flutter app ──HTTP REST──┐
       │                   ├──► Fastify backend (backend/) ──► Postgres
       └──WebSocket────────┘            │
            (overlap publish,           └──► Firebase Admin (Auth verify + FCM send)
             block fan-out)              └──► node-cron (daily 03:00 UTC invite cleanup)
  ```
  Data Model: list the Postgres tables from `001_init.sql` (`users`, `couples`, `invites`, `timeblocks`, `overlaps_latest`) with their columns. Security Model: "Firebase ID-token verification (`backend/src/auth.ts`) on every REST + WS path; couple membership enforced via `assertMember()` (`couples.ts:58`); WS `overlap` messages additionally require `computedBy === socketUid`." Deployment: "Coolify builds the `backend/Dockerfile` image on push (`deploy.sh`); Fastlane (`deploy-stores.yml`) for app stores; GitHub Actions CI (`ci.yml`)."

- [ ] **Step 4: Rewrite `AGENTS.md`** — update the "Finding things" table (point `backend logic` at `backend/src/routes/*.ts` + `backend/src/overlap.ts` + `backend/src/cron.ts`, not `functions/src/`); "Running things" (`cd backend && pnpm install && pnpm build && pnpm test`); "Important context" ("backend stores in Postgres; **the device computes overlap and publishes it over WS — the server does not compute overlap**"); Testing Strategy (vitest in `backend/src/__tests__/`, Flutter `test/`, Maestro `.maestro/` flows — no Firestore emulator); Tech Stack table (Fastify 4 + Postgres + Node 22, drop "Cloud Functions v2").

- [ ] **Step 5: Rewrite `.agents/startup-context.md`** — same corrections: "Self-hosted Fastify + Postgres backend in `backend/`", "no `functions/` directory", "device-computed overlap over WS", "Firebase Auth + FCM + hosting only".

- [ ] **Step 6: Rewrite `BACKLOG.md`** — drop the "v1 Cloud Functions — implemented, 89 jest tests" line (false). Reflect actual state: backend in `backend/` (vitest), deferred items (SyncService split, Hive migration, localization, a11y sweep) listed as future.

- [ ] **Step 7: Rewrite `wiring-checklist.json`** — replace assertions against `functions/src/index.ts` and `lib/services/firestore_service.dart` (both don't exist) with assertions against `backend/src/index.ts` and `lib/services/sync_service.dart`. Keep the pattern (declarative wiring the `scripts/wiring-check.sh` runs).

- [ ] **Step 8: Commit**
  ```bash
  git add CLAUDE.md ARCHITECTURE.md AGENTS.md .agents/startup-context.md BACKLOG.md README.md wiring-checklist.json
  git commit -m "docs: rewrite stale Firebase/Functions layer to match Fastify+Postgres backend"
  ```

---

## Task 2: Delete junk + fix .gitignore

Pure deletion. No behaviour change. Safe.

- [ ] **Step 1: Delete committed pipeline artifacts + dead scripts/workflows + the dead placeholder screen AND its test**
  ```bash
  git rm .baseline-failures.txt .baseline-gate.log
  git rm scripts/run-e2e-tests.sh
  git rm infra/scripts/deploy-functions.sh infra/scripts/deploy-rules.sh
  git rm .github/workflows/deploy-backend.yml
  git rm lib/features/blocks/screens/blocks_screen.dart
  git rm test/features/blocks/screens/blocks_screen_test.dart
  ```
  `test/features/blocks/screens/blocks_screen_test.dart` imports the `blocks_screen.dart` placeholder being deleted, so it must go too or `flutter test` breaks on a missing import.
  (If any path errors "did not match", skip it — the audits may have miscounted; do not fail the task, but check `git status` for any other test that imports `blocks_screen.dart` before proceeding: `grep -rn "blocks_screen" test/ lib/`.)

- [ ] **Step 2: Add gitignore entries** — append to `.gitignore`:
  ```
  # pipeline / baseline artifacts
  .baseline-*
  *.gate.log
  ```
  If `infra/scripts/` is now empty, leave the dir (git ignores empty dirs anyway).

- [ ] **Step 3: Commit**
  ```bash
  git add -A
  git commit -m "chore: remove dead Firebase-Functions scripts, CI workflow, and pipeline artifacts"
  ```

---

## Task 3: Fix CI — replace broken jobs with backend-test

`ci.yml` jobs `functions-lint-test` and `integration-test` reference `functions/` + Firestore emulators that don't exist.

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Read current `ci.yml`** to locate the `functions-lint-test` and `integration-test` jobs exactly. Run: `grep -n "functions-lint-test\|integration-test\|functions/\|firestore" .github/workflows/ci.yml`

- [ ] **Step 2: Replace those two jobs** with one `backend-test` job (mirror `Makefile backend-test`):
  ```yaml
    backend-test:
      runs-on: ubuntu-latest
      defaults:
        run:
          working-directory: backend
      steps:
        - uses: actions/checkout@v4
        - uses: pnpm/action-setup@v4
          with:
            version: 11.9.0
        - uses: actions/setup-node@v4
          with:
            node-version: '22'
            cache: pnpm
            cache-dependency-path: backend/pnpm-lock.yaml
        - run: pnpm install --frozen-lockfile
        - run: pnpm build
        - run: pnpm test
  ```
  Keep the existing `analyze` and `test` (flutter) and `build` (apk) jobs untouched. Ensure `backend-test` is in the `needs`/`if` graph wherever `functions-lint-test` was (or add it to the workflow's success gate if one exists).

- [ ] **Step 3: Commit**
  ```bash
  git add .github/workflows/ci.yml
  git commit -m "ci: replace dead functions/emulator jobs with backend-test (pnpm vitest)"
  ```

---

## Task 4: Fix the timezone-onboarding bypass (critical)

New users get `users.timezone='UTC'` from the SQL default → `hasTimezone` true → timezone-setup screen never fires. The fix lives entirely at the storage layer: default `''` for new rows, change the column default for existing DBs, and make `migrate.ts` actually run new migration files (it currently hardcodes `001_init.sql`).

**Why no data flip:** the onboarding screen (`timezone_setup_screen.dart:48`) auto-detects the device timezone and only falls back to `'UTC'` when detection *fails* — so a stored `'UTC'` is ambiguous: it could be a bypass victim (never saw the screen) OR a legit user whose device TZ couldn't be detected. Blanket-`UPDATE users SET timezone='' WHERE timezone='UTC'` would re-onboard legit UTC users. So: only change the *default* going forward (new rows get `''`), never mutate existing rows.

**Files:**
- Modify: `backend/src/migrations/001_init.sql`
- Create: `backend/src/migrations/002_timezone_default_empty.sql`
- Modify: `backend/src/migrate.ts`
- Modify: `lib/services/providers/auth_state_provider.dart`
- Test: `backend/src/__tests__/auth.test.ts`

- [ ] **Step 1: Write the failing backend test** — add to `backend/src/__tests__/auth.test.ts`:
  ```typescript
  it('upserts a new user with empty timezone (not UTC)', async () => {
    // reuse the test harness already in auth.test.ts for upsertUser
    await upsertUser({ uid: 'u-tz-1', email: 'a@b.com' });
    const full = await query('SELECT timezone FROM users WHERE uid = $1', ['u-tz-1']);
    expect(full.rows[0].timezone).toBe('');
  });
  ```
  Run: `cd backend && pnpm test auth` — expected FAIL (current default is `'UTC'`).

- [ ] **Step 2: Change the SQL default** in `backend/src/migrations/001_init.sql` (line 9):
  ```sql
  timezone    TEXT NOT NULL DEFAULT '',
  ```

- [ ] **Step 3: Create migration `002_timezone_default_empty.sql`** — column default only, no row mutation:
  ```sql
  -- Couple Sync — change the users.timezone default from 'UTC' to '' so new
  -- users hit the timezone-onboarding guard (hasTimezone is false on '').
  -- Existing rows are NOT touched: a stored 'UTC' is ambiguous (could be a
  -- legit user whose device-TZ detection failed and who saved 'UTC'), so a
  -- blanket flip would wrongly re-onboard them. The default change is enough
  -- to fix new signups.
  ALTER TABLE users ALTER COLUMN timezone SET DEFAULT '';
  ```

- [ ] **Step 4: Make `migrate.ts` run all migration files.** Currently `backend/src/migrate.ts:16` hardcodes `001_init.sql`, so `002` would be silently ignored. Replace the single-file read with a directory scan + ordered execution:
  ```typescript
  import { readFileSync, readdirSync } from 'node:fs';
  // ...
  export async function runMigrations(): Promise<void> {
    getConfig();
    const pool = getPool();
    const dir = join(__dirname, 'migrations');
    const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
    for (const file of files) {
      const sqlPath = join(dir, file);
      const sql = readFileSync(sqlPath, 'utf8');
      log.info({ sqlPath }, 'Running migration');
      await pool.query(sql);
    }
    log.info({ count: files.length }, 'Migrations complete');
  }
  ```
  Each migration must be idempotent (`CREATE TABLE IF NOT EXISTS` / `ALTER ... SET DEFAULT` are). Existing `001` already is.

- [ ] **Step 5: Run backend tests** — `cd backend && pnpm test` — expected PASS. Also verify `node dist/migrate.js` runs both files against a throwaway DB (or trust the new test covers the default).

- [ ] **Step 6: Verify the Flutter side.** In `lib/services/providers/auth_state_provider.dart`, `hasTimezone` is `userProfile?.timezone.isNotEmpty ?? false` — this already treats `''` as unset, so the SQL fix is what unblocks it; no Dart change needed for the bypass. While here, delete the dead `isLoadingProvider` (line ~230, never read — `grep -rn "isLoadingProvider" lib/` to confirm zero reads before deleting).

- [ ] **Step 7: Commit**
  ```bash
  git add backend/src/migrations/001_init.sql backend/src/migrations/002_timezone_default_empty.sql backend/src/migrate.ts backend/src/__tests__/auth.test.ts lib/services/providers/auth_state_provider.dart
  git commit -m "fix: default user timezone to empty + run all migrations so onboarding guard fires"
  ```

---

## Task 5: Fix `UserModel.displayName` non-null cast (critical)

`user_model.dart:27` casts `displayName` as non-null `String`, but `users.display_name` is nullable (Apple Sign-In can omit name). Any nameless user crashes `fromJson`.

**Files:**
- Modify: `lib/core/models/user_model.dart`
- Test: `test/core/models/user_model_test.dart`

- [ ] **Step 1: Write the failing test** — add to `test/core/models/user_model_test.dart`:
  ```dart
  test('UserModel.fromJson tolerates null displayName', () {
    final json = {
      'uid': 'u1',
      'email': 'a@b.com',
      'displayName': null, // Apple Sign-In with no name captured
      'photoUrl': null,
      'timezone': '',
      'fcmTokens': <String>[],
      'showLateNightWindows': false,
      'createdAt': 0,
    };
    final user = UserModel.fromJson(json);
    expect(user.displayName, isNull);
  });
  ```
  Run: `flutter test test/core/models/user_model_test.dart` — expected FAIL (`type 'Null' is not a subtype of type 'String'`).

- [ ] **Step 2: Make `displayName` nullable** in `lib/core/models/user_model.dart`:
  - Field: `final String? displayName;`
  - `fromJson`: `'displayName': json['displayName'] as String?,`
  - `toJson`: `'displayName': displayName,`
  - `copyWith`: keep the clear-null flag pattern the file already uses for other nullable fields.

- [ ] **Step 3: Audit downstream consumers** — `grep -rn "displayName" lib/` — any `user.displayName!` or non-null assumption must guard for null (e.g. fall back to email or `'You'`/`'Partner'`). Fix each call site to `displayName ?? email` (or the app's existing fallback).

- [ ] **Step 4: Run tests** — `flutter test test/core/models/ && flutter analyze` — expected PASS.

- [ ] **Step 5: Commit**
  ```bash
  git add lib/core/models/user_model.dart test/core/models/user_model_test.dart
  git commit -m "fix: make UserModel.displayName nullable to avoid fromJson crash"
  ```

---

## Task 6: Fix the redeem-orphan bug (critical)

`invites.ts:199` — an already-paired user can redeem another invite, orphaning their previous partner. Add a guard inside the redeem transaction.

**Files:**
- Modify: `backend/src/routes/invites.ts`
- Test: `backend/src/__tests__/pairing.test.ts`

- [ ] **Step 1: Write the failing test** — add to `backend/src/__tests__/pairing.test.ts`:
  ```typescript
  it('rejects redeem when the redeemer is already paired (409, no coupleId leak)', async () => {
    // Set up: inviter has a pending invite; redeemer already has a couple_id.
    // (Reuse the harness's helpers to seed an already-paired redeemer.)
    const res = await redeemInvite({ redeemerUid: alreadyPairedUid, code: 'XXXXXX' });
    expect(res.statusCode).toBe(409);
    expect(res.json().coupleId).toBeUndefined();
    // the redeemer's existing couple_id is unchanged
    const redeemer = await getUser(alreadyPairedUid);
    expect(redeemer.coupleId).toBe(originalCoupleId);
  });

  it('rejects redeem when the inviter is already paired (409)', async () => {
    // inviter created the invite, then got paired via a second invite, then
    // someone tries to redeem the first (stale) invite.
    const res = await redeemInvite({ redeemerUid: thirdPartyUid, code: staleCode });
    expect(res.statusCode).toBe(409);
  });
  ```
  Run: `cd backend && pnpm test pairing` — expected FAIL (current code allows the redeem).

- [ ] **Step 2: Add the guard** in `backend/src/routes/invites.ts`, inside the `else` happy-path branch (line ~199, after the `invite.created_by_uid === uid` self-redeem check, before the `INSERT INTO couples` at line 204). Use the redeemer variable `uid` (the auth'd caller) and `inviterUid`/`invite.created_by_uid` for the inviter — `redeemerUid` does not exist in this code:
  ```typescript
  } else {
    // Happy path: create the couple, stamp the invite, link both users.
    // Reject if either party is already in a couple — prevents orphaning an
    // existing couple (the previous partner would be left pointing at a now-
    // inactive couple with no notification). Placed in the happy path only so
    // the idempotent-redeemed branch above still returns the existing coupleId
    // for the two legitimate parties.
    const pairedCheck = await client.query<{ couple_id: string | null }>(
      'SELECT couple_id FROM users WHERE uid IN ($1, $2)',
      [invite.created_by_uid, uid]
    );
    for (const row of pairedCheck.rows) {
      if (row.couple_id !== null) {
        await client.query('ROLLBACK');
        return reply.code(409).send({ error: 'conflict', message: 'User is already paired' });
      }
    }
    inviterUid = invite.created_by_uid;
    coupleId = crypto.randomUUID();
    // ... existing INSERT couples / UPDATE invites / UPDATE users ...
  }
  ```
  The check uses `IN ($1, $2)` against both uids and does not indicate which was paired, so it doesn't leak which party is already taken.

- [ ] **Step 3: Run backend tests** — `cd backend && pnpm test` — expected PASS.

- [ ] **Step 4: Commit**
  ```bash
  git add backend/src/routes/invites.ts backend/src/__tests__/pairing.test.ts
  git commit -m "fix: reject invite redeem when either party is already paired"
  ```

---

## Task 7: Backend small-batch wonk fixes

Four minor-but-real backend defects, batched.

**Files:**
- Modify: `backend/src/routes/blocks.ts`, `backend/src/routes/users.ts`, `backend/src/cron.ts`, `backend/src/auth.ts`
- Test: `backend/src/__tests__/blocks.test.ts` (exists), `backend/src/__tests__/users.test.ts` (create), `backend/src/__tests__/cron.test.ts` (create)

- [ ] **Step 1: `PUT /blocks` field validation** (`blocks.ts:267`). Write a failing test that `PUT /blocks/:id { startUtc: "hello" }` returns 400 not 500:
  ```typescript
  it('PUT /blocks/:id with a non-integer startUtc returns 400', async () => {
    const res = await app.inject({ method: 'PUT', url: `/blocks/${blockId}`, payload: { startUtc: 'hello' }, ...authHeaders });
    expect(res.statusCode).toBe(400);
  });
  ```
  Run: `cd backend && pnpm test blocks` — FAIL. Then route the PUT body through the same `readInt`/`readString` guards POST uses. Re-run — PASS.

- [ ] **Step 2: `PATCH /users` FCM leak** (`users.ts:183`). The partner-broadcast call passes `rowToJson(row, true)` which includes `fcmTokens`. Change the broadcast to `rowToJson(row, false)` (or `includeFcm=false`). Add a test asserting the partner-socket receives no `fcmTokens` field.

- [ ] **Step 3: Cron UTC timezone + constant-time admin token.** In `backend/src/cron.ts`:
  - Line 29: `cron.schedule('0 3 * * *', async () => { ... }, { timezone: 'UTC' })`.
  - Line 54: replace `token !== expected` with a constant-time compare:
    ```typescript
    import { timingSafeEqual } from 'crypto';
    // ...
    const a = Buffer.from(token);
    const b = Buffer.from(expected);
    const ok = a.length === b.length && timingSafeEqual(a, b);
    if (!token || !ok) { return reply.code(401)... }
    ```

- [ ] **Step 4: Delete dead `authPreHandler`** in `backend/src/auth.ts:57` (exported, never used). `grep -rn "authPreHandler" backend/src` — if zero non-definition hits, delete it. If you instead wire it as a Fastify `preHandler` to remove per-route `getUid` duplication, that's a larger change — **do NOT do that here** (defer to the SyncService-split plan); just delete the dead export.

- [ ] **Step 5: Delete the dead `socket.uid` cast** in `backend/src/routes/sync.ts:142` (`grep -rn "\.uid" backend/src/routes/sync.ts` to confirm it's never read, then remove the line).

- [ ] **Step 6: Run + commit**
  ```bash
  cd backend && pnpm test && pnpm build
  git add backend/src/routes/blocks.ts backend/src/routes/users.ts backend/src/cron.ts backend/src/auth.ts backend/src/routes/sync.ts backend/src/__tests__
  git commit -m "fix: PUT block validation, FCM token leak, UTC cron, remove dead code"
  ```

---

## Task 8: UI fixes batch

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`, `lib/core/router/routes.dart`, `lib/features/blocks/widgets/block_list_tile_widget.dart`, `lib/features/calendar/block_event_widget.dart`
- (Delete of `blocks_screen.dart` done in Task 2.)

- [ ] **Step 1: Wire `BlockManagementScreen` into navigation.** In `lib/features/home/screens/home_screen.dart`, add a "Manage Blocks" entry to the quick-action sheet that calls `context.push(AppRoutes.blocks)`. (The route `/blocks` already exists in `app_router.dart:221`.) Run `flutter analyze`.

- [ ] **Step 2: Fix block-form navigation bug.** In `home_screen.dart:285`, change `context.go(AppRoutes.blockForm)` → `context.push(AppRoutes.blockForm)` so the form's `Navigator.pop(true)` (in `block_form_screen.dart:212`) has a screen to return to and the return value isn't lost. Verify the calendar FAB path (`week_view_screen.dart:224`) already uses `context.push` (it does) — leave it.

- [ ] **Step 3: Remove dead router extensions.** In `lib/core/router/routes.dart:68-74`, `goToBlocks`/`goToBlockForm` extension methods are never called. `grep -rn "goToBlocks\|goToBlockForm" lib/` — if zero non-definition hits, delete them.

- [ ] **Step 4: Dedup `_getCategoryColor`.** `AppTheme.getCategoryColor(category, brightness)` already exists. In `block_list_tile_widget.dart:140`, `block_event_widget.dart:87` (BlockEventWidget), and `block_event_widget.dart:269` (BlockDetailDialog), delete the local `_getCategoryColor` switch and call `AppTheme.getCategoryColor(category, Theme.of(context).brightness)` instead. Run `flutter analyze`.

- [ ] **Step 5: Verify `calendarConnectionProvider` is dead** — `grep -rn "calendarConnectionProvider\b" lib/` — if only the definition site in `lib/services/providers/calendar_provider.dart:20` references it (and the screen uses `calendarConnectionNotifierProvider`), delete the dead `calendarConnectionProvider`. If it's invalidated internally by the notifier, leave it.

- [ ] **Step 6: Run tests + analyze + commit**
  ```bash
  flutter analyze
  flutter test
  git add lib/features/home/screens/home_screen.dart lib/core/router/routes.dart lib/features/blocks/widgets/block_list_tile_widget.dart lib/features/calendar/block_event_widget.dart lib/services/providers/calendar_provider.dart
  git commit -m "fix: wire block management screen, fix block-form nav, dedup category color"
  ```

---

## Task 9: Lightweight Docker hardening

The Dockerfile is already multi-stage `bookworm-slim` with `--frozen-lockfile` + prod-only runtime deps — decent. Add minimal hardening; do NOT switch to alpine (firebase-admin/grpc native deps are fragile on musl) and do NOT switch to distroless in this task (the `sh -c` migrate-then-start CMD needs a shell; a custom entrypoint is out of scope).

**Files:**
- Modify: `backend/Dockerfile`

- [ ] **Step 1: Add a non-root runtime user + HEALTHCHECK** in `backend/Dockerfile` runtime stage, before `CMD`:
  ```dockerfile
  # Run as non-root. node:22-bookworm-slim ships a `node` user (uid 1000).
  RUN chown -R node:node /app
  USER node
  HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
  ```
  (If `/health` does not exist on the Fastify server, add a one-line `app.get('/health', async () => ({ ok: true }))` route in `backend/src/index.ts` first — and a test. If you'd rather not add a route, drop the HEALTHCHECK line; the non-root user is the higher-value change.)

- [ ] **Step 2: Build the image locally to confirm it still builds**
  ```bash
  cd backend && docker build -t couple-sync-api:hardened .
  ```
  Expected: build succeeds, `node dist/migrate.js && node dist/index.js` still the CMD.

- [ ] **Step 3: Commit**
  ```bash
  git add backend/Dockerfile backend/src/index.ts
  git commit -m "build: run backend container as non-root node user with healthcheck"
  ```

---

## Task 10: Handle pairing/unpair/user:update WS messages reactively

`sync_service.dart:265` `_CoupleSession._onMessage` handles only `block:set`, `block:del`, `overlap` — it silently drops `pairing`, `unpair`, `user:update`, so pairing/pref-changes rely on a 10s `Timer.periodic` poll in `overlap_controller.dart`.

**Architecture note (corrected):** `SyncService` is NOT Riverpod-aware — it can't invalidate providers. It already exposes block changes via a `StreamController` (`_blocksController`) that the OverlapController listens to. The fix follows that existing pattern: `_CoupleSession` emits session events on a new stream, and the OverlapController subscribes instead of polling.

**Files:**
- Modify: `lib/services/sync_service.dart`
- Modify: `lib/core/overlap/overlap_controller.dart`
- Test: `test/services/sync_service_test.dart`

- [ ] **Step 1: Write a failing test** in `test/services/sync_service_test.dart` asserting that feeding a `{'t':'pairing','coupleId':'c1'}` WS message into `_CoupleSession._onMessage` emits a `CoupleSessionEvent` of type `pairing` on the session's event stream. (Reuse the harness's mock WS / fake socket. Assert the stream emits before a 1s timeout.) This test FAILS today (the message is dropped).

- [ ] **Step 2: Add a session-event stream to `_CoupleSession` + a public accessor on `SyncService`.** `_CoupleSession` is private to `sync_service.dart`, but `OverlapController` lives in `lib/core/overlap/` and reaches session data only through public `SyncService` methods (`watchBlocks(coupleId)`, `watchOverlap(coupleId)` at lines ~481 and ~551). Follow that exact pattern. In `lib/services/sync_service.dart`:

  Define a small event type (top-level so it's importable):
  ```dart
  enum CoupleSessionEventType { pairing, unpair, userUpdate }
  class CoupleSessionEvent {
    final CoupleSessionEventType type;
    final Map<String, dynamic> payload;
    CoupleSessionEvent(this.type, this.payload);
  }
  ```
  In `_CoupleSession`, add a broadcast `StreamController<CoupleSessionEvent>` + getter:
  ```dart
  final _eventsController = StreamController<CoupleSessionEvent>.broadcast();
  Stream<CoupleSessionEvent> get events => _eventsController.stream;
  ```
  Extend the `switch` in `_onMessage` (line 269) with the three dropped cases:
  ```dart
  case 'pairing':
    _eventsController.add(CoupleSessionEvent(CoupleSessionEventType.pairing, msg));
    break;
  case 'unpair':
    _eventsController.add(CoupleSessionEvent(CoupleSessionEventType.unpair, msg));
    break;
  case 'user:update':
    _eventsController.add(CoupleSessionEvent(CoupleSessionEventType.userUpdate, msg));
    break;
  ```
  Close `_eventsController` in `_CoupleSession`'s dispose alongside `_blocksController`.

  Then expose it publicly on `SyncService`, mirroring `watchBlocks`/`watchOverlap` (both call `_ensureSession(coupleId)` at ~line 606 and return its stream):
  ```dart
  Stream<CoupleSessionEvent> watchSessionEvents(String coupleId) =>
      _ensureSession(coupleId).events;
  ```
  This is the accessor `OverlapController` subscribes through — without it, the private session's stream is unreachable from another library.

- [ ] **Step 3: Subscribe in `OverlapController`** (`overlap_controller.dart`). Replace the `Timer.periodic` 10s poll (lines ~115-118) with a subscription through the new public accessor (the controller already holds a `SyncService` ref and subscribes to `sync.watchBlocks(coupleId)` at ~line 121 — use the same handle):
  ```dart
  _sessionEventSub = sync.watchSessionEvents(coupleId).listen((event) {
    switch (event.type) {
      case CoupleSessionEventType.pairing:
      case CoupleSessionEventType.unpair:
      case CoupleSessionEventType.userUpdate:
        // re-resolve couple + both profiles (pairing/unpair) or partner
        // profile (userUpdate: timezone/prefs changed), then recompute
        _invalidateAndRecompute();
        break;
    }
  });
  ```
  Where `_invalidateAndRecompute()` does whatever the current 10s poll body does (re-fetch couple + profiles, recompute overlap). Cancel `_sessionEventSub` in `dispose()`.

- [ ] **Step 4: Decide on the safety-net poll.** If the WS reconnect path re-syncs on connect (verify by reading `_connect` / the `sub` handshake — it re-subscribes to the couple stream), drop the `Timer.periodic` entirely. If there's any state that only a poll would reconcile (e.g. partner who was offline during the event), keep a 60s poll as a cheap safety net instead of 10s. State the choice in a `// ponytail:` comment.

- [ ] **Step 5: Run tests + analyze + commit**
  ```bash
  flutter test test/services/sync_service_test.dart
  flutter analyze
  git add lib/services/sync_service.dart lib/core/overlap/overlap_controller.dart test/services/sync_service_test.dart
  git commit -m "fix: handle pairing/unpair/user:update WS messages reactively, drop 10s poll"
  ```

---

## Deferred to a separate plan

These are real but not blocking, and bundling them would make this plan unreviewable. Capture for a follow-up `docs/superpowers/plans/` doc:

1. **`SyncService` split** — the ~717-line god-object into `UserRepository`/`BlockRepository`/`InviteRepository`/`OverlapRepository` + thin facade.
2. **Hive deprecation** — `hive`/`hive_flutter` are archived (2024). Migrate to `isar` or `shared_preferences`+hydrated-state per cache use case.
3. **Localization** — zero i18n; add `flutter_localizations` + `.arb`, route strings through `AppLocalizations.of(context)`.
4. **a11y sweep** — `Semantics` only in `auth_screen.dart`; add labels app-wide; fix `Colors.grey` body text/icons (use `theme.colorScheme.onSurfaceVariant`).
5. **Two parallel overlap providers** — consolidate `overlapWindowsProvider` (stream) + `overlapControllerProvider` into one source of truth. (Touched in Task 10 but not fully consolidated — the week-view stream vs controller split remains.)
6. **ESLint** — add an ESLint config + `lint` script to `backend/package.json` (currently none, despite CLAUDE.md claiming one).
7. **`integration_test/`** — only a README; add real integration tests or document Maestro as the integration layer.

---

## Self-review notes

- **Spec coverage:** user asked (1) where UI must fix → Tasks 5, 8, deferred a11y/localization; (2) backend wonky → Tasks 6, 7, 10, deferred SyncService-split; (3) make it agentic → Tasks 1, 2, 3 (rewrite the lying docs + fix CI + delete dead agent-misleading scripts); (4) clean up junk → Task 2; (5) lightweight Docker → Task 9; (6) UTC server-side / device TZ on device → Tasks 4, 7 (cron UTC) + Global Constraint. All covered.
- **Placeholder scan:** no "TBD"/"add appropriate". The one conditional ("if `/health` does not exist…") gives both branches concretely. The cron `expected`-token compare shows full code.
- **Type consistency:** `upsertUser`, `hasTimezone`, `displayName`, `AppTheme.getCategoryColor`, `assertMember` referenced consistently with the audit's file:line citations.
- **Factual reconciliation:** the architecture audit's claim that "expired-invite cleanup is not ported" is wrong — `cron.ts:15-22` has it. This plan does NOT add a cleanup function (it already exists); Task 7 only fixes its timezone + token compare.
