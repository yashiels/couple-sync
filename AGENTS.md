# Agent Guide

This document is for AI agents (and developers) working in this repository. Read it before making changes.

---

## Before making changes

- For product requirements and feature specs, see [PRD.md](./PRD.md) — use that vocabulary in code, comments, and PRs. For system structure see [ARCHITECTURE.md](./ARCHITECTURE.md).
- Read existing code before modifying it. Do not assume structure — verify it.
- Check existing providers under `lib/services/` before adding a new service. The pattern you need may already exist there.
- The backend lives in `backend/` (self-hosted Fastify + Postgres + WebSocket). It is NOT on Firebase — Firebase is used only for Auth (ID-token verification) + FCM + hosting. There is no `functions/` directory and no Firestore.

---

## Finding things

| What you are looking for       | Where to look                       |
| ------------------------------ | ----------------------------------- |
| Flutter app screens / routes   | `lib/features/`                     |
| Reusable UI components         | `lib/core/theme/`, `lib/features/*/widgets/` |
| State management (Riverpod)    | `lib/services/` (providers)        |
| Data models                    | `lib/core/models/`                  |
| Router / navigation guards     | `lib/core/router/`                  |
| REST + WS client, block cache, overlap compute | `lib/services/sync_service.dart` |
| Backend route handlers (REST)  | `backend/src/routes/*.ts`           |
| Backend overlap WS handler     | `backend/src/overlap.ts`            |
| Backend cron / admin           | `backend/src/cron.ts`               |
| Backend auth (Firebase verify) | `backend/src/auth.ts`                |
| Couple-membership guard        | `backend/src/couples.ts` (`assertMember`) |
| Postgres schema + migrations   | `backend/src/migrations/001_init.sql` |
| DB pool + query helper         | `backend/src/db.ts`                  |
| Firebase Admin init            | `backend/src/firebase.ts`            |
| Env config                     | `backend/src/config.ts`              |
| GitHub Actions workflows       | `.github/workflows/`                 |
| Deploy script                  | `deploy.sh`                          |
| Docker compose (prod)          | `docker-compose.yml`                 |
| Docker compose (local dev)     | `docker-compose.override.yml`         |

---

## Running things

Install Flutter dependencies:

```bash
flutter pub get
```

Common targets:

```bash
# Run the app
flutter run

# Run tests
flutter test

# Static analysis
flutter analyze

# Format check
dart format --set-exit-if-changed .

# Build iOS (no signing)
flutter build ios --no-codesign

# Build Android APK
flutter build apk --debug
```

Backend (in `backend/`, pnpm — not npm):

```bash
cd backend && pnpm install   # install deps
pnpm build                   # tsc → dist/
pnpm test                    # vitest run
pnpm dev                     # tsx watch src/index.ts → http://localhost:3000
pnpm migrate                 # apply src/migrations/001_init.sql
```

Full stack locally (bundled postgres via the override file):

```bash
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --build
```

---

## Important context

- **Backend stores in Postgres; the device computes overlap and publishes it over WS — the server does not compute overlap.** The server only validates shape, dedups via `inputHash`, stores `overlaps_latest`, and fans out (WS forward to the partner's live socket, or FCM push + token prune when the partner is offline).
- **Security is enforced server-side, not via Firestore rules.** `backend/src/auth.ts` verifies the Firebase ID token on every REST + WS path; `backend/src/couples.ts assertMember()` enforces couple membership on every couple-scoped path; WS `overlap` messages additionally require `computedBy === socketUid`. There are no Firestore rules (no Firestore is used).
- **Backend uses pnpm, not npm.** Tests run on `vitest` (`cd backend && pnpm test`). There is **no ESLint config and no `lint` script** — do not run `npm run lint`; it does not exist.
- **Firebase project**: `nexion-ai-prod` (Spark plan — Auth + FCM + hosting only). No Blaze, no Cloud Functions, no Firestore.
- **No `functions/` directory, no `firestore.rules`, no `firestore.indexes.json`.** If a doc or command references them, it is stale.
- **Previous implementation was reset.** v1 is a rebuild with a simplified architecture: the device computes overlap, the backend is a thin validate/store/fan-out server.

---

## Do not

- Add multiple calendar providers — Google Calendar only in v1
- Store or display event titles from Google Calendar — freebusy only
- Move overlap computation to the server — it is intentionally device-side
- Use Firestore Timestamps — store UTC milliseconds as `BIGINT` (Postgres) / `int` (Dart)
- Run `npm install` or `npm run lint` in `backend/` — use `pnpm install` / `pnpm build` / `pnpm test`
- Commit `.env` files or any file containing credentials or secrets
- Assume the backend service is running — verify it first (`curl http://localhost:3000/health`)
- Add complex auth state management — keep it simple with Riverpod StateNotifier

---

## Verification before claiming done

Before marking a task complete, verify the affected code passes all of the following:

```bash
# Static analysis passes
flutter analyze

# Tests pass
flutter test

# Format is clean
dart format --set-exit-if-changed .
```

If backend code was changed, also verify:

```bash
cd backend
pnpm build
pnpm test
```

If you changed wiring (new files, new routes, renamed symbols), also run the wiring check:

```bash
./scripts/wiring-check.sh
```

---

## Branch Convention

Branch names follow `<type>/<issue-number>-<kebab-description>`:

```
feat/DEV-96-add-week-view
fix/DEV-104-null-timezone
chore/DEV-111-update-gitignore
```

- **GitHub issue number is required** in the branch name — create or identify an issue before branching
- `type` follows Conventional Commits: `feat`, `fix`, `chore`, `refactor`, `docs`, `ci`, etc.
- Description is kebab-case and optional but recommended
- Bypass branches (no issue required): `main`, `develop`, `master`, `release/*`, `hotfix/*`

---

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Frontend | Flutter (Dart 3.x) | Latest stable |
| State management | Riverpod | Latest stable |
| Routing | go_router | Latest stable |
| Backend | Fastify 4 | `^4.28.1` |
| WebSocket | `@fastify/websocket` + `ws` | `^10.0.1` / `^8.18.0` |
| Database | Postgres 16 via `pg` | `^8.13.0` |
| Server runtime | Node 22 + TypeScript 5 | pnpm |
| Auth | Firebase Auth (Google + Apple) — verified via Admin SDK | Spark plan |
| Push notifications | FCM via `firebase-admin` | `^12.6.0` |
| Cron | `node-cron` | `^3.0.3` |
| Logging | `pino` | `^9.4.0` |
| Calendar | Google Calendar API v3 (freebusy) | — |
| Timezone (Flutter) | `timezone` package | Latest |
| Block cache (Flutter) | Hive (`hive` + `hive_flutter`) | `^2.2.3` |
| WS client (Flutter) | `web_socket_channel` | `^3.0.3` |

## Testing Strategy

### Flutter Tests

```bash
flutter test                              # All tests
flutter test test/core/models/            # Specific directory
flutter test --coverage                   # With coverage
```

**Test patterns:**
- **Model tests**: fromJson/toJson round-trip, field validation, copyWith
- **Service tests**: mock HTTP/WS/caches; for `SyncService`, inject a fake `WsConnection` and `BlockCache` and assert the overlap compute + publish path
- **Widget tests**: `flutter_test`, pumpWidget, verify UI state and interactions
- **Router tests**: Mock auth state, verify redirect guards

### Backend Tests

```bash
cd backend && pnpm test
```

Tests live in `backend/src/__tests__/` (vitest). Covers: auth verify, block CRUD + broadcast, pairing atomicity + unpair, overlap WS handler (validate/dedup/broadcast/push/token-prune), `GET /overlaps/latest`, and the `computedBy === socket-uid` assertion. There is no Firebase emulator suite — the Firebase Admin SDK is soft-failed in dev and mocked in tests.

### End-to-end (Flutter)

Maestro flows live in `.maestro/`. Run on a connected device or emulator.

```bash
maestro test .maestro/
```

---

## Conventions

### Naming

- **DB tables**: plural lowercase (`users`, `couples`, `invites`, `timeblocks`, `overlaps_latest`)
- **DB columns**: snake_case (`start_utc`, `end_utc`, `couple_id`, `display_name`)
- **Dart fields**: camelCase (`startUtc`, `endUtc`, `coupleId`, `displayName`)
- **Dart files**: snake_case (`user_model.dart`, `sync_service.dart`)
- **Dart classes**: PascalCase (`UserModel`, `SyncService`)
- **Providers**: camelCase with `Provider` suffix (`authStateProvider`, `syncServiceProvider`)

### Data Storage

- **Timestamps**: UTC milliseconds since epoch (`BIGINT` in Postgres, `int` in Dart) — never Firestore Timestamp
- **Timezone**: IANA string (e.g., `"America/New_York"`, `"Africa/Johannesburg"`)
- **Postgres tables**: `users`, `couples`, `invites`, `timeblocks`, `overlaps_latest` (see `backend/src/migrations/001_init.sql`)
- **Overlap dedup**: `overlaps_latest.input_hash` (client-computed hash of the inputs; server skips persist+fan-out when it matches the stored value)

### State Management

```dart
// Provider pattern
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AsyncValue<UserModel?>>((ref) {
  return AuthStateNotifier(ref.read(authServiceProvider));
});

// Usage in widget
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(...);
  }
}
```

### Router Guards

```dart
// go_router redirect pattern
redirect: (context, state) {
  final authState = ref.read(authStateProvider);
  final isAuthenticated = authState.value != null;
  final hasTimezone = authState.value?.timezone != null;
  final hasCouple = authState.value?.coupleId != null;

  if (!isAuthenticated && state.location != '/auth') return '/auth';
  if (isAuthenticated && !hasTimezone && state.location != '/timezone-setup') return '/timezone-setup';
  if (isAuthenticated && hasTimezone && !hasCouple && state.location != '/pairing') return '/pairing';
  if (isAuthenticated && hasCouple && state.location == '/auth') return '/home';
  return null;
}
```

### Error Handling

```dart
// Service layer throws domain exceptions
class SyncException implements Exception {
  final String message;
  final String code;
  SyncException(this.message, this.code);
}

// Providers wrap in AsyncValue
state = AsyncValue.loading();
try {
  final user = await syncService.getUser(uid);
  state = AsyncValue.data(user);
} catch (e) {
  state = AsyncValue.error(e, StackTrace.current);
}
```

## Discovered Patterns (from previous implementation)

**What worked:**
- IANA timezone storage
- FCM for notifications
- WS-based real-time fan-out for blocks + overlap
- Device-side overlap compute (simpler, testable, no server cold-start)

**What failed (avoid):**
- Complex auth state management → Use simple Riverpod StateNotifier
- Multiple calendar providers → Google only in v1
- Server-side overlap computation → moved to the device in v1 (no cold starts, no Functions debounce bugs)
- Firestore rules as the security boundary → replaced by server-side `assertMember()` on every path

## Cost-Conscious Design

- **Firebase Spark plan** (free): Auth + FCM + hosting
- **Postgres** on a managed Docker platform (Coolify) — tiny DB, one small container
- **Optimizations:**
  - Device-side overlap compute — no server compute cost, no cold starts
  - `inputHash` dedup on `overlaps_latest` — skips redundant persist + fan-out
  - `overlaps_latest` is one row per couple — constant storage per couple
  - Minimal data: no event titles, 14-day horizon
- **Monitoring**: Set a GCP budget alert at $1/month regardless
