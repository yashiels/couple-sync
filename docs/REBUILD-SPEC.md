# Couple Sync — RN rebuild spec (authoritative)

Repo: `<repo-root>/.worktrees/chore-couple-sync-react-native`
All prior code deleted. Greenfield. Expo (managed) app at repo root, Fastify backend in `backend/`.

**This file is the single source of truth. `PRD.md` and `ARCHITECTURE.md` are stale — ignore them
where they conflict. In particular they say the *device* computes overlap. It does not. The backend
does.**

Ponytail mode: build the minimum that works. No speculative abstractions. Mark deliberate
simplifications with a short comment naming the ceiling and the upgrade path.

---

## 0. Decisions already made — do not relitigate

1. **Overlap is computed on the backend**, not on the device. The client never computes, never
   hashes, never publishes windows — it reads them. This keeps the app lean and lets compute scale
   independently.
2. **Scoring formula**: base over *hours*, bonuses 5/5, evening 18:00–21:00 in partner A's tz,
   `timeDecay = max(0, 10 − daysFromNow*0.5)`, no rounding. (Section 3.)
3. **Recurrence is anchored to `block.timezone`**, not expanded as UTC. A weekly 09:00-local block
   must stay 09:00 local across a DST transition. `ALGO_VERSION = 1`.
4. **`visibility: onlyMe` is enforced server-side.** The server owns compute, so an `onlyMe` block
   still shapes the overlap while its `title` and `category` are never sent to the partner. The old
   build shipped this control as a pure no-op — don't repeat that.
5. **Notification toggle is real**: `users.notifications_enabled BOOLEAN NOT NULL DEFAULT true`.
   The server checks it before sending FCM. No fake toggles.
6. **App name**: "Couple Sync". Deep-link scheme `couplesync://`, https fallback deferred.
6a. **Android only, Google sign-in only.** Every build and every verification runs on Android. Apple
   Sign-In and iOS are deferred (paid developer account, iOS-only). No email/password, no anonymous.
6b. **Recurrence is expanded server-side and shipped to the client.** The client has no `rrule`, so
   `GET /blocks` takes a `from`/`to` range and returns per-block `occurrences: {start_utc,end_utc}[]`
   built from the engine's `expandBlock`. A calendar view must never read `recurrence_rule` directly.
6c. **Google Calendar is the product, and Google sign-in is the only door.** Signing in with Google
   *is* connecting the calendar — `signInWithGoogle()` requests `calendar.readonly` in the same
   consent flow. There is no connect-calendar screen, no Settings connect/disconnect, and no
   `connect()`/`disconnect()`/`isConnected()` API. The loop is *sign in with Google -> pull
   free/busy -> show free spots.*
6d. **Never assume the calendar scope was granted.** Google lets a user finish sign-in while
   declining the calendar consent, and a grant can be revoked later. So `sync()` returns
   `'scope-missing'` and the Free time screen shows one inline "Allow calendar access" row calling
   `ensureScope()`. One row, never a screen, never a router guard.
7. **Min window is 30 min, hard-coded.** The Overlap screen's duration filter is display-only.
   No `couples.settings` table.
8. **Not building** (v1 non-goals): iOS builds, Apple Sign-In, email/password or anonymous auth, a
   separate Blocks tab, a routine setup wizard, a partner profile screen, relationship stats, daily
   digest, analytics, quiet hours, Terraform/GCP IaC, Apple Calendar, Microsoft Graph, Firestore,
   Cloud Functions, paywall, i18n, offline write queue, calendar webhooks, multiple calendars per
   user, and any client-side interval or recurrence math.
9. **Timestamps**: UTC epoch millis everywhere — wire, storage (`BIGINT`), TS (`number`).
   Timezones: IANA IDs.
10. **Tests**: real ones that fail if the logic breaks. The overlap engine and the auth/membership
    guards get thorough tests. UI does not get a test per component.

---

## 1. Screens

**Android is the only build target for v1. Google is the only sign-in method.** Apple Sign-In and iOS
are deferred — Apple Sign-In needs a paid developer account and is iOS-only.

**Three tabs**, not five. The product loop is *connect Gmail -> we pull free/busy -> we show both
partners' free spots*, and the screen count follows that loop and nothing else.

| Screen | User does | Data |
|---|---|---|
| Auth | One Google sign-in button, requesting `calendar.readonly` in the same consent. States plainly that only busy/free is read, never event titles | -> Firebase ID token, uid, email, name, photo, **and the calendar grant** |
| Timezone setup | Confirm the detected IANA zone or pick from a searchable list showing each candidate's current local time | device tz; writes `users.timezone` |
| Pairing | "Share" tab: generate + share a 6-char code. "Enter" tab: redeem partner's code | own `couple_id` (null), invite code + expiry |
| **Free time** (tab 1) | Both live clocks, countdown to the next window, then every window with an any/30m/1h/2h filter. Pull-to-refresh syncs the calendar *and* refetches windows | both users' tz + name, overlap windows, calendar-connected state, last sync ms |
| **Calendar** (tab 2) | Page by week; tap own block to edit, a google block for a read-only sheet, a window for detail; FAB -> block form. Also the block-management surface - there is no separate Blocks tab | own + partner's blocks **with server-expanded `occurrences`**, overlap windows |
| Block form (modal) | Title, type, category, start/end in local tz, recurrence, visibility, delete. Validate title non-empty and `end > start` | user tz; block on edit |
| **Settings** (tab 3) | Calendar: the signed-in Google account, last sync, "Sync now" (**no disconnect** — the grant is the login). You: timezone, late-night toggle. Notifications: one toggle. Couple: partner, unpair (confirm), sign out | user row, couple row, calendar scope state |

**Router guards, in order**: `!authenticated -> /auth`; `!user.timezone -> /timezone-setup`;
`!user.couple_id -> /pairing`; else the tabs. There is deliberately **no** calendar guard. A
`couplesync://invite/:code` deep link must survive the sign-in round-trip and land pre-filled on the
Enter tab.

The client renders overlap windows straight from the API, and renders blocks from the
**server-supplied `occurrences` array**. It has **no** `rrule` dependency, no overlap logic, and no
interval math beyond positioning an already-expanded interval on the week grid.

## 2. Data model

**users**: `uid` PK · `email` NOT NULL · `display_name` · `photo_url` ·
`timezone` **nullable** (NULL until confirmed in onboarding — a `NOT NULL DEFAULT 'UTC'` makes the `!user.timezone` router guard permanently false and onboarding unreachable) · `couple_id` FK nullable · `fcm_tokens` TEXT[] NOT NULL DEFAULT '{}' ·
`show_late_night_windows` BOOL NOT NULL DEFAULT false · `notifications_enabled` BOOL NOT NULL DEFAULT true ·
`created_at` BIGINT NOT NULL

**couples**: `id` PK · `user_a_uid` NOT NULL · `user_b_uid` NOT NULL · `status` 'active'|'inactive' ·
`paired_at` BIGINT · `created_at` BIGINT. Scoring uses **A's** timezone.

**invites**: `code` PK (6-char alnum, unambiguous alphabet — no O/0/I/1) · `created_by_uid` NOT NULL ·
`couple_id` nullable · `expires_at` BIGINT NOT NULL (created + 48h) ·
`status` 'pending'|'accepted'|'expired' · `created_at` BIGINT. Rows are preserved after use.

**timeblocks**: `id` PK · `couple_id` NOT NULL · `user_id` NOT NULL · `title` NOT NULL ·
`type` 'busy'|'free'|'tentative' · `category` nullable (work, study, commute, exercise, social,
meals, sleep, personal, other) · `start_utc` BIGINT NOT NULL (DTSTART for recurring) ·
`end_utc` BIGINT NOT NULL (duration = end − start, reused per instance) · `timezone` NOT NULL (IANA,
**used by recurrence expansion**) · `recurrence_rule` nullable (RFC 5545 RRULE, `RRULE:` prefix
optional) · `source` 'google'|'manual' · `visibility` 'bothPartners'|'onlyMe' · `created_at` BIGINT

**overlaps_latest** (exactly one row per couple): `couple_id` PK · `windows` JSONB NOT NULL (≤20) ·
`computed_at` BIGINT NOT NULL · `input_hash` TEXT NOT NULL
(no `computed_by` — the server is the only computer)

**OverlapWindow** (JSON element = WS payload = API payload):
`startUtc: number` · `endUtc: number` · `durationMinutes: number` (0 < d ≤ 1560) ·
`score: number` · `reasonableBoth: boolean`

This is the one **camelCase** payload — it is the engine's computed type, not a database row.
Everything else on the wire is the row shape in `snake_case`, with no DTO mapping layer.

Indexes: `timeblocks(couple_id, user_id)`, `timeblocks(couple_id, source)`,
`invites(status, expires_at)`, `users(couple_id)`.

## 3. Overlap engine — backend, pure function, no I/O

Lives at `backend/src/overlap/`. Pure: no db, no clock, no network. `now` is an argument.

Constants: `HORIZON_DAYS=14`, `MIN_WINDOW_MINUTES=30`, `MAX_WINDOWS=20`, `WAKE_HOUR=7`,
`SLEEP_HOUR=23`, `ALGO_VERSION=1`.

### Exported contract — both the engine and the server code depend on exactly this

```ts
// backend/src/overlap/index.ts
export const ALGO_VERSION = 1

export interface Block {
  userId: string
  type: 'busy' | 'free' | 'tentative'
  startUtc: number
  endUtc: number
  timezone: string          // IANA, anchors recurrence expansion
  recurrenceRule: string | null
}
export interface Prefs { showLateNightWindows: boolean }
export interface OverlapWindow {
  startUtc: number
  endUtc: number
  durationMinutes: number
  score: number
  reasonableBoth: boolean
}
export interface OverlapInput {
  blocksA: Block[]
  blocksB: Block[]
  timezoneA: string         // couple.user_a_uid's zone — scoring anchor
  timezoneB: string
  prefsA: Prefs
  prefsB: Prefs
  now: number               // UTC epoch ms; the engine floors it to the hour itself
}

/** Never mutates `input`. Deterministic for a given input. */
export function computeOverlap(input: OverlapInput): OverlapWindow[]

/** 16-hex-char cache key over the semantic inputs. Order-independent w.r.t. block array order. */
export function computeInputHash(input: OverlapInput): string
```

### Algorithm

`now` is floored to the hour inside the engine, so results are stable within an hour and
`computeInputHash` is a usable cache key.

1. `windowStart = now`; `windowEnd = now + 14 * 86_400_000`.
2. **Expand recurrence** per block:
   - No RRULE → emit `[max(start, windowStart), min(end, windowEnd)]`, or nothing if it misses the
     horizon entirely.
   - With RRULE → strip an optional `RRULE:` prefix. **DTSTART is `start_utc` interpreted in
     `block.timezone`**, so occurrences keep their local wall-clock time across DST.
     `duration = end_utc − start_utc`. Iterate ascending; `break` when `occStart >= windowEnd`; keep
     when `occStart + duration > windowStart` (an instance starting before the horizon but bleeding
     into it is retained). Clamp each kept instance to the horizon.
   - Support `FREQ=DAILY|WEEKLY|MONTHLY|YEARLY` + `INTERVAL` + `BYDAY` + `COUNT` + `UNTIL`.
3. **Busy timeline**: keep `type ∈ {busy, tentative}`. `free` blocks are dropped entirely.
4. **Merge** per partner: sort by start, coalesce touching/overlapping.
5. **Invert to free** within the horizon: cursor at `windowStart`; per merged busy interval emit
   `[cursor, busy.start]` when `cursor < busy.start`, then `cursor = max(cursor, busy.end)`;
   finally emit `[cursor, windowEnd]` when `cursor < windowEnd`.
6. **Intersect** freeA × freeB, two-pointer: `s = max(a.start,b.start)`, `e = min(a.end,b.end)`,
   emit when `s < e`, advance whichever ends first.
7. **Clip once per partner, sequentially** (A's output feeds B's):
   - `showLateNightWindows === false` → split into per-local-calendar-day segments bounded by
     07:00 and 23:00 **wall clock** in that partner's zone.
   - `true` → split at local midnight only, keeping the full day, so multi-day windows still render
     one window per day.
8. **DST**: all day-walking increments the **calendar day field** of a zoned datetime, then reads
   07:00 / 23:00 / 00:00 wall clock in that zone. Never add `86_400_000` ms, never do UTC ms day
   math. A fall-back day yields a 25h segment — that's why `durationMinutes` allows up to 1560.
   Spring-forward (2024-03-10 America/New_York) and fall-back (2024-11-03) are **required** tests,
   for both the clipping and the recurrence expansion.
9. **Score**:
   ```
   durationHours = (endUtc - startUtc) / 3_600_000
   base          = log2(durationHours + 1) * 10
   localA        = startUtc rendered in timezoneA
   eveningBonus  = (localA.hour >= 18 && localA.hour < 21) ? 5 : 0
   weekendBonus  = (localA.weekday is Sat or Sun)          ? 5 : 0
   daysFromNow   = (startUtc - now) / 86_400_000          // fractional
   timeDecay     = max(0, 10 - daysFromNow * 0.5)
   score         = base + eveningBonus + weekendBonus + timeDecay
   ```
   `reasonableBoth = !prefsA.showLateNightWindows && !prefsB.showLateNightWindows` (couple-level,
   not per-window). Scoring is anchored on the window **start** and on **A's timezone only** —
   asymmetric by design.
10. **Filter** `durationMinutes >= 30`, where `durationMinutes = round((end−start)/60000)`. Runs
    *after* scoring, on the rounded value.
11. **Sort** by `score` descending, **tiebreak by `startUtc` ascending**.
12. **Cap** to 20.

`computeInputHash`: `sha256(...).slice(0,16)` over
`ALGO_VERSION ‖ nowHourBucket ‖ tzA ‖ tzB ‖ prefsA ‖ prefsB ‖ blocksA ‖ blocksB`, where each block
contributes `startUtc:endUtc:recurrenceRule:type:timezone` and blocks are sorted by `startUtc` (then
by the rest of the tuple) before hashing. Must be independent of the caller's array order and must
not mutate the arrays.

Budget: < 500 ms for a 14-day computation, and it must hold with ~500 recurring blocks per partner.

### When the server recomputes

Recompute → upsert `overlaps_latest` → fan out, on **any** of:
- block create / update / delete / google batch replace
- `PATCH /users/:uid` changing `timezone` or `showLateNightWindows`
- pairing (both partners' blocks first become visible to each other)
- `GET /overlaps/latest` when the stored row's `input_hash` no longer matches the freshly computed
  hash for the current hour bucket — this is what keeps windows from going stale as `now` advances,
  with no cron needed

If the newly computed `input_hash` equals the stored one, skip the write, skip the WS fan-out, and
skip the push. Unpair deletes the row.

## 4. Auth + pairing

**Auth**: client obtains a Firebase ID token → `POST /auth/verify` upserts the user row and returns
it → app hydrates user + couple + blocks + windows **before** rendering a route → guards run. Every
REST call carries `Authorization: Bearer <idToken>`; the WS upgrade carries the token in a header
(RN can set them) with a `?token=` fallback.

**Pairing**: `POST /invites` mints a code (48h TTL). `POST /invites/:code/redeem` runs **one
transaction** with `SELECT ... FOR UPDATE`: code exists and `status='pending'`; not expired;
redeemer ≠ creator (no self-pair); both users' `couple_id` are null (else **409**); insert couple,
stamp invite `accepted`, set `couple_id` on both rows, COMMIT. Then compute the first overlap and
best-effort WS `pairing` to the inviter. Cron `0 3 * * *` UTC flips expired pending invites to
`expired`; manual `POST /admin/cleanup` behind a separate `ADMIN_TOKEN` (timing-safe compare, 503
when unset).

**Edge cases**: deep link before sign-in → code retained through auth; already-accepted code →
rejected; either party already paired → 409 with no partial writes; non-member on any couple-scoped
path → **403**, and a non-existent couple also returns 403 (never leak existence).
**On unpair**: set `couples.status='inactive'`, null both `couple_id`s, delete that couple's
`timeblocks` and its `overlaps_latest` row, broadcast WS `unpair`.

## 5. Google Calendar

Google only. Scope: exactly `https://www.googleapis.com/auth/calendar.readonly`, requested as part
of the **sign-in** consent rather than a later escalation, because Google sign-in is the only way
into the app. Calendar API v3
**`freeBusy.query` only** — never `events.list`. Primary calendar, 14-day lookahead. Store the
returned busy intervals as `source='google'`, `type='busy'`, with a placeholder title; discard the
raw response. **Event titles are never fetched, stored, or displayed — hard
rule.**
Sync = delete this user's `source='google'` blocks then batch-insert the fresh set, in one
transaction, then recompute overlap once.
Auto-sync on launch only if last sync > 1h ago; manual sync from pull-to-refresh and Settings.
**Quota rule, stated precisely:** at most one *automatic* freebusy call per device per hour.
The user-initiated / state-transition syncs that additionally bypass the limiter are the Settings
"Sync now" button, a successful `ensureScope()`, the moment a couple first pairs, the Settings
device-calendar toggle, and pull-to-refresh (guarded by a short client-side cooldown so repeated
tugs don't each spend a call). Each corresponds to a discrete user action and cannot loop.
Exponential backoff on 429/503 is used **only** by these forced syncs; an *automatic* call is exactly
one request with no retry, so a 429/503 there simply fails the Google source for that run and leaves
the device source untouched. (The limiter is per device, not per user: server-side enforcement would
need a last-sync column on `users` — the recorded upgrade path.)

**Two sources, one gate.** Only Google freebusy is metered, so only Google is hourly-gated (persisted
`calendar.googleGateMs`, reserved *before* the request and fail-closed if that write throws). The
device OS calendar read is **local and unmetered**, so it runs on *every* sync — cold start,
foreground return, and pull — and is never gated. Because of that split the app re-syncs on a real
background→foreground transition (device refreshes immediately; Google respects its gate) and Settings
shows per-source freshness (`calendar.googleSuccessMs` / `calendar.deviceSuccessMs`) rather than one
combined "last synced" — a device-only refresh is never labelled as a Google sync.

The client already holds the grant from sign-in, calls `freeBusy.query` itself, and posts the
resulting busy intervals to `PUT /blocks/google`. **No OAuth refresh token is stored server-side**, so
a sync only happens while the app is open — that is the accepted ceiling. Server-side sync would need
encrypted refresh-token storage and a scheduler; not v1.

A user may decline the calendar consent while still completing sign-in, or revoke it later. Handle it
as one inline prompt (`ensureScope()`), never a blocking screen — the app must stay usable with
manual blocks alone.

## 6. Realtime + push

WS `GET /sync`, `uid → socket` map for fan-out. **Server → client only.** The client sends nothing
but an optional keepalive ping; any inbound message with an unrecognised `t` is dropped for
forward-compat.

| Message | Trigger |
|---|---|
| `hello` | on connect: `{uid, coupleId}` |
| `block:set` | block create/update (sent to both partners; `onlyMe` scrubbed for the non-owner) |
| `block:del` | block delete |
| `blocks:changed` | a whole-set replacement (`PUT /blocks/google`): one message, not one `block:set` per interval, and the only way to express an *empty* replacement. Receivers refetch their visible range once |
| `overlap` | server recomputed and the result changed: `{coupleId, windows, computedAt}` |
| `unpair` | unpair |
| `pairing` | invite redeemed |
| `user:update` | profile patch (strip `fcmTokens`) |

**Push**: FCM fires only when the overlap changed **and** the recipient has no live socket **and**
`recipient.notifications_enabled` is true. The user whose own action triggered the recompute is not
pushed. Prune only hard-invalid tokens (`messaging/invalid-registration-token`,
`messaging/registration-token-not-registered`); keep tokens on transient failures.

## 7. REST surface

```
GET    /health                          no auth  → {status, time}
POST   /auth/verify                              → {user}   (upsert)
POST   /auth/fcm-token         {token}           → append with dedup
DELETE /auth/fcm-token         {token}           → remove on sign-out (self only), so a shared
                                                   handset never keeps a previous user's token
GET    /blocks?coupleId=X&from=&to=              → couple's blocks + server-expanded `occurrences`
                                                   for [from,to] (onlyMe scrubbed per recipient;
                                                   range required, max 60 days)
POST   /blocks                                   → create,  recompute, broadcast
GET    /blocks/:id?coupleId=X                    → one block
PATCH  /blocks/:id                               → update,  recompute, broadcast
DELETE /blocks/:id                               → delete,  recompute, broadcast
PUT    /blocks/google                            → atomic replace of caller's google blocks,
                                                   then recompute + broadcast
GET    /overlaps/latest?coupleId=X               → windows, recomputing first if the stored
                                                   input_hash is stale for this hour bucket
GET    /users/me                                 → own profile incl. fcmTokens
GET    /users/:uid                               → self or partner (fcmTokens omitted for partner)
PATCH  /users/:uid                               → self only: timezone, showLateNightWindows,
                                                   notificationsEnabled, displayName;
                                                   recompute when tz or late-night changed;
                                                   broadcast user:update
GET    /couples/:id                              → couple, membership enforced
POST   /couples/:id/unpair                       → see §4
POST   /invites                                  → {code, expiresAt} 201
POST   /invites/:code/redeem                     → {coupleId}
POST   /admin/cleanup          ADMIN_TOKEN       → expire stale invites, 503 when unset
```

`assertMember(coupleId, uid)` guards **every** couple-scoped path. Non-member and non-existent
both → 403.

## 8. Non-negotiables

- Freebusy only, never an event title, anywhere.
- Verify the Firebase ID token on every REST and WS path.
- `assertMember` on every couple-scoped path.
- `onlyMe` blocks shape the overlap but their `title`/`category` never reach the partner.
- Admin routes behind a distinct `ADMIN_TOKEN`; 503 when unset.
- UTC epoch millis on the wire and in storage. IANA tz IDs.
- Firebase **Spark** plan: Auth + FCM only. No Blaze, no Firestore, no Cloud Functions.
- Postgres behind the Fastify container. Migrations run before the server process starts.
- `CORS_ORIGINS` must **not** default to `*`. Fail fast when unset.
- Fail fast on missing/invalid Firebase credentials and on an unreachable database — the old build
  soft-warned and booted "healthy" while 401-ing every request.
- The overlap engine stays a pure function with no db or clock access, so it can be tested exactly
  and later moved to a worker without a rewrite.

## 9. Known ceilings to write down, not solve

- `uid → socket` map is in-memory: single replica only. Comment it; Redis pub/sub is the upgrade.
- Overlap runs inline on the request thread. Fine at <500 ms and this user count; a job queue is the
  upgrade path if p99 write latency ever matters. Note it where `computeOverlap` is called.
- No `schema_migrations` version table yet: migrations must stay idempotent DDL.
- No server-side Google OAuth refresh token: a sync needs the app in the foreground.
