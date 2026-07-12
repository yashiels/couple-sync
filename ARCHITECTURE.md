# ARCHITECTURE.md

## System Overview

Couple Sync v1 is a mobile app for long-distance couples to find mutual free time across timezones. The architecture prioritizes real-time sync, privacy, and low operational cost. The **device computes overlap**; the server only validates, stores, and fans out.

```
┌──────────────────────┐         ┌──────────────────────┐
│   Partner A App      │         │   Partner B App      │
│   (Flutter)          │         │   (Flutter)          │
│  - iOS + Android     │         │  - iOS + Android     │
│  - Riverpod state    │         │  - Riverpod state    │
│  - go_router         │         │  - go_router         │
│  - overlap compute   │         │  - overlap compute   │
└──────────┬───────────┘         └──────────┬───────────┘
           │ HTTP REST                       │
           │  (/auth, /blocks, /couples,     │
           │   /invites, /overlaps)          │
           └──────────────┬──────────────────┘
                          │
                          ▼
          ┌─────────────────────────────────┐
          │  Fastify backend (backend/)      │
          │  - REST routes (routes/*.ts)     │
          │  - WebSocket /sync (routes/sync) │
          │  - overlap handler (overlap.ts)  │
          │  - assertMember (couples.ts)     │
          │  - auth.ts (Firebase ID verify)  │
          └──────┬──────────────┬────────────┘
                 │              │
                 ▼              ▼
         ┌──────────────┐  ┌────────────────────────────┐
         │  Postgres    │  │  Firebase Admin SDK         │
         │  (pg.Pool)   │  │  - Auth: verifyIdToken      │
         │  - users     │  │  - FCM: sendEachForMulticast│
         │  - couples   │  └────────────────────────────┘
         │  - invites   │
         │  - timeblocks│  ┌────────────────────────────┐
         │  - overlaps_ │  │  node-cron                 │
         │    latest    │  │  - daily 03:00 UTC         │
         └──────────────┘  │    invite cleanup         │
                           └────────────────────────────┘
```

The WebSocket path carries the live sync: block create/update/delete broadcasts (`block:set` / `block:del`) and overlap publish (`overlap`). REST is used for auth, block CRUD, couple state, invites, and reconnect-fetch of the stored latest overlap.

## Data Flow

### 1. Auth Flow
```
User taps "Sign in with Google/Apple"
    ↓
Firebase Auth issues an ID token (client-side)
    ↓
App POSTs the token to /auth/verify on the backend
    ↓
backend/src/auth.ts verifies the Firebase ID token
    ↓
users row upserted (uid, email, timezone, fcm_tokens)
    ↓
Router checks auth state → redirects to appropriate screen
```

### 2. Pairing Flow
```
Partner A POSTs /invites → backend inserts an invites row (status: pending, 48h expiry)
    ↓
Backend returns the 6-char code; Partner A shares it with Partner B
    ↓
Partner B POSTs /invites/:code/redeem
    ↓
backend/src/routes/invites.ts atomically: validates code, creates couples row,
  sets couple_id on both users rows
    ↓
Both apps detect coupleId change → navigate to home
```

### 3. Block Sync Flow
```
User adds manual block OR Google Calendar sync runs
    ↓
App POSTs/PUTs /blocks (REST) → backend writes timeblocks row + broadcasts
  `block:set` (or `block:del`) to the partner's live WS socket
    ↓
Partner's app receives the WS message → updates local cache + UI
```

### 4. Overlap Flow (device-computed)
```
Either partner's device computes overlap windows from cached blocks
  (expand recurrence → intersect free times → clip waking hours → score → top N)
    ↓
App sends `{"t":"overlap", coupleId, windows, inputHash, computedBy}` over WS /sync
    ↓
backend/src/routes/sync.ts authorizeOverlapMessage:
  assert computedBy === socketUid (prevents forging another uid)
    ↓
backend/src/overlap.ts handleOverlapMessage:
  1. validateWindows(windows)         — shape/duration/sanity
  2. dedup via inputHash              — skip if matches overlaps_latest.input_hash
  3. upsert overlaps_latest           — store couple's latest overlap
  4. partner live?  → forward `overlap` over the partner's WS socket
     partner offline? → FCM push + prune invalid tokens
```

The server **does not compute overlap**. It validates, dedups, stores, and fans out.

## Core Components

### Flutter App

**Entry Point**: `lib/main.dart`
- Initializes Firebase (Auth + FCM; no Firestore)
- Wraps app in `ProviderScope` (Riverpod)
- Renders `MyApp` with `MaterialApp.router`

**Router**: `lib/core/router/app_router.dart`
- Defines all routes
- Implements redirect guards:
  - `!isAuthenticated` → `/auth`
  - `!hasTimezone` → `/timezone-setup`
  - `!hasCouple` → `/pairing`
  - `hasCouple` → `/home`

**Services**:
- `AuthService`: Firebase Auth (Google + Apple sign-in)
- `SyncService` (`lib/services/sync_service.dart`): REST + WS client, in-memory + Hive block cache, and the **overlap compute + publish** path. Connects to `wss://<api>/sync?token=<Firebase ID token>`, sends `overlap` messages, and handles `block:set` / `block:del` / `overlap` / `unpair` fan-in.
- `CalendarService`: Google Calendar OAuth + freebusy sync
- `NotificationService`: FCM token registration + foreground notifications

**State Management**:
- Riverpod `StateNotifierProvider` for each domain (auth, user, couple, blocks, overlaps)
- All state is immutable, updated via `copyWith()`
- WS messages from the backend trigger state updates

### Backend (`backend/`)

**Bootstrap** (`backend/src/index.ts`): Fastify + `@fastify/cors` + `@fastify/websocket`, registers route plugins, starts the daily cleanup cron, and shuts down gracefully on SIGINT/SIGTERM.

**Auth** (`backend/src/auth.ts`): `authenticate()` verifies the Firebase ID token from either the `Authorization: Bearer <token>` header (REST) or the `?token=` query param (WS handshake). `authPreHandler` is the Fastify preHandler that attaches the decoded token to `request.user`.

**Couple membership** (`backend/src/couples.ts`): `assertMember(coupleId, uid)` loads the couple row and throws `ForbiddenError` (403) if `uid` is neither `user_a_uid` nor `user_b_uid`. Non-existent couples also surface as 403 to avoid leaking existence. Every couple-scoped REST + WS path calls this.

**Overlap handler** (`backend/src/overlap.ts`):
- `validateWindows()` — pure; throws on malformed shape/duration
- `parseOverlapMessage()` — typed envelope parse
- `handleOverlapMessage()` — validate → dedup (inputHash) → upsert `overlaps_latest` → forward to partner's live socket or FCM-push + prune invalid tokens
- `filterInvalidFcmTokens()` — only hard-invalid codes (`messaging/invalid-registration-token`, `messaging/registration-token-not-registered`) are pruned; transient errors are logged

**WS sync** (`backend/src/routes/sync.ts`): `/sync` upgrade verifies the token, stashes `uid` on the socket, and authorizes every incoming message. `authorizeOverlapMessage` asserts `computedBy === socketUid`; the outer wrapper additionally calls `assertMember(coupleId, uid)`.

**Cron** (`backend/src/cron.ts`): `node-cron` schedule at `0 3 * * *` UTC flips expired+pending invites to `status='expired'` (row preserved for audit + idempotent-redeem guards). `POST /admin/cleanup-invites` is the manual trigger, guarded by `ADMIN_TOKEN`.

**Migrations** (`backend/src/migrate.ts` + `backend/src/migrations/001_init.sql`): idempotent schema. Migrations run on container start (the image CMD runs `node dist/migrate.js` before `node dist/index.js`).

## Data Model

Postgres schema (from `backend/src/migrations/001_init.sql`). All timestamps are `BIGINT` UTC milliseconds since epoch.

### `users`
| Column | Type | Notes |
|---|---|---|
| `uid` | TEXT PK | Firebase Auth uid |
| `email` | TEXT NOT NULL | |
| `display_name` | TEXT | |
| `photo_url` | TEXT | |
| `timezone` | TEXT NOT NULL default `'UTC'` | IANA ID |
| `couple_id` | TEXT | null if unpaired |
| `fcm_tokens` | TEXT[] NOT NULL default `'{}'` | device push tokens |
| `show_late_night_windows` | BOOLEAN NOT NULL default FALSE | |
| `created_at` | BIGINT NOT NULL | UTC ms |

### `couples`
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | |
| `user_a_uid` | TEXT NOT NULL → users(uid) | |
| `user_b_uid` | TEXT NOT NULL → users(uid) | |
| `status` | TEXT NOT NULL default `'active'` | `active` / `inactive` |
| `paired_at` | BIGINT NOT NULL | UTC ms |
| `created_at` | BIGINT NOT NULL | UTC ms |
| `unpair_history` | JSONB NOT NULL default `'[]'` | |

### `invites`
| Column | Type | Notes |
|---|---|---|
| `code` | TEXT PK | 6-char alphanumeric |
| `created_by_uid` | TEXT NOT NULL → users(uid) | |
| `couple_id` | TEXT → couples(id) | set on redemption |
| `expires_at` | BIGINT NOT NULL | 48h from creation, UTC ms |
| `status` | TEXT NOT NULL default `'pending'` | `pending` / `accepted` / `expired` |
| `created_at` | BIGINT NOT NULL | UTC ms |

### `timeblocks`
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | |
| `couple_id` | TEXT NOT NULL → couples(id) | |
| `user_id` | TEXT NOT NULL → users(uid) | |
| `title` | TEXT NOT NULL | |
| `type` | TEXT NOT NULL | `busy` / `free` / `tentative` |
| `category` | TEXT | work/study/commute/exercise/social/meals/sleep/personal/other |
| `start_utc` | BIGINT NOT NULL | UTC ms |
| `end_utc` | BIGINT NOT NULL | UTC ms |
| `timezone` | TEXT NOT NULL | IANA ID where created |
| `recurrence_rule` | TEXT | RFC 5545 RRULE |
| `source` | TEXT NOT NULL | `google` / `manual` |
| `visibility` | TEXT NOT NULL | `bothPartners` / `onlyMe` |
| `created_at` | BIGINT NOT NULL | UTC ms |

### `overlaps_latest`
| Column | Type | Notes |
|---|---|---|
| `couple_id` | TEXT PK → couples(id) | one row per couple |
| `windows` | JSONB NOT NULL | array of `{startUtc, endUtc, durationMinutes, score, reasonableBoth}` |
| `computed_at` | BIGINT NOT NULL | UTC ms |
| `input_hash` | TEXT NOT NULL | client-computed dedup key |
| `computed_by` | TEXT | uid of the device that computed it |

### Indexes
- `idx_timeblocks_couple_user` on `timeblocks(couple_id, user_id)`
- `idx_timeblocks_couple_source` on `timeblocks(couple_id, source)`
- `idx_invites_status_expires` on `invites(status, expires_at)`
- `idx_users_couple` on `users(couple_id)`

## Security Model

**Principle**: Every couple-scoped REST and WS path verifies the Firebase ID token and asserts couple membership server-side. There are no Firestore rules (no Firestore is used).

- **Auth**: `backend/src/auth.ts authenticate()` verifies the Firebase ID token on every request. REST uses `Authorization: Bearer <token>`; WS uses `?token=<token>` on the upgrade (browsers cannot set headers on WS).
- **Couple membership**: `backend/src/couples.ts assertMember(coupleId, uid)` (line 58) is called on every couple-scoped REST + WS path. Non-members get 403; non-existent couples also surface as 403 to avoid leaking existence.
- **WS overlap authorship**: `backend/src/routes/sync.ts authorizeOverlapMessage` additionally asserts `msg.computedBy === socketUid` — a client cannot publish an overlap attributed to another uid.
- **Admin routes**: `POST /admin/cleanup-invites` is guarded by a separate `ADMIN_TOKEN` shared secret (responds 503 when unset).
- **`visibility: onlyMe` blocks**: filtered client-side, not server-enforced (accepted trade-off for v1 — the server returns both partners' blocks; the app hides `onlyMe` blocks from the partner).

## Timezone Handling

- **Storage**: All timestamps as UTC milliseconds (`BIGINT` in Postgres, `int` in Dart)
- **User timezone**: stored in `users.timezone`
- **Block timezone**: stored in `timeblocks.timezone` (where the block was created)
- **Display**: convert UTC to the viewer's local timezone using the `timezone` package
- **Overlap computation** (device-side): uses both partners' timezones for waking-hours clipping (7am–11pm local)
- **Backend**: timezone-agnostic — stores UTC ms only, no Luxon

## Privacy Model

- **Google Calendar**: freebusy API only — no event titles fetched or stored
- **Manual blocks**: title visible to partner if `visibility: bothPartners`, otherwise shows as unnamed busy time
- **Server data**: only busy/free intervals + overlap windows stored, no calendar content

## Offline Behavior

- Hive block cache (`lib/services/sync_service.dart`) keeps blocks available offline
- Manual blocks queue and sync when the WS reconnects
- Calendar sync requires connectivity
- On reconnect: `GET /overlaps/latest?coupleId=X` fetches the stored latest overlap (404 → null)

## Deployment

**Backend**:
- Coolify builds the `backend/Dockerfile` image on push (`deploy.sh` triggers the push; Coolify handles build + roll). The platform reverse proxy (Traefik on Coolify) terminates TLS and routes to the container's port 3000. **No Caddy, no host port binding** — `docker-compose.yml` only `expose`s 3000.
- Postgres is provisioned as a separate managed resource on the platform; `DATABASE_URL` is injected.
- Migrations run automatically on container start (image CMD: `node dist/migrate.js && node dist/index.js`).
- GitHub Actions CI (`.github/workflows/ci.yml`) runs `flutter analyze`, `flutter test`, and `cd backend && pnpm install && pnpm build && pnpm test` on PRs and pushes to `main`.
- Future: a separate v1-part-2 plan (issue #62) will move backend deploy to a self-hosted GHA runner on a Hetzner CX23. Out of scope here.

**App stores**:
- iOS: App Store via Fastlane (`.github/workflows/deploy-stores.yml`)
- Android: Play Store via Fastlane

**Firebase Hosting**: `firebase.json` configures hosting only (Flutter web build + `/.well-known/apple-app-site-association` + `/assetlinks.json` headers + `/invite/**` rewrite). Deployed via `firebase deploy --only hosting` if needed.

## Cost Model

| Service | Free allowance | Expected usage |
|---------|---------------|----------------|
| Firebase Auth | 50k MAU (Spark) | <10 users |
| FCM | Unlimited (Spark) | Minimal |
| Firebase Hosting | Generous Spark quota | Single web app |
| Postgres (managed) | Platform-dependent | Tiny DB |
| Coolify container | Self-hosted | One small container |

**Estimated monthly cost**: ~$0–5 (managed Docker host + free Firebase Spark tier).
