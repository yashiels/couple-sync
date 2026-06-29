# Agent Guide

This document is for AI agents (and developers) working in this repository. Read it before making changes.

---

## Before making changes

- For product requirements and feature specs, see [PRD.md](./PRD.md) — use that vocabulary in code, comments, and PRs. For system structure see [ARCHITECTURE.md](./ARCHITECTURE.md).
- Read existing code before modifying it. Do not assume structure — verify it.
- Check existing providers under `lib/services/` before adding a new service. The pattern you need may already exist there.
- The Cloud Functions backend lives in `functions/`. It is deployed to Firebase project `nexion-ai-prod`.

---

## Finding things

| What you are looking for      | Where to look                       |
| ----------------------------- | ----------------------------------- |
| Flutter app screens / routes  | `lib/features/`                     |
| Reusable UI components        | `lib/core/theme/`, `lib/features/*/widgets/` |
| State management (Riverpod)   | `lib/services/` (providers)         |
| Data models                   | `lib/core/models/`                  |
| Router / navigation guards    | `lib/core/router/`                  |
| Cloud Functions               | `functions/src/`                    |
| Firestore security rules      | `firestore.rules`                   |
| Firestore indexes             | `firestore.indexes.json`            |
| GitHub Actions workflows      | `.github/workflows/`                |

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

# Cloud Functions (in functions/)
cd functions && npm install && npm run build
```

---

## Important context

- **Firestore is live.** The app reads/writes to Firestore in project `nexion-ai-prod`. Do not add mock data — use the real backend.
- **Overlap computation is server-side.** When a time block is written, Cloud Functions compute the overlap window and write to `overlaps/{coupleId}/windows/latest`. The Flutter app reads this, never computes overlaps client-side.
- **Security rules enforce couple membership.** Every read/write to couple-scoped data requires the user to be a member of that couple. Rules use `get()` on the parent couple doc (costs 1 read per check).
- **No min instances for Functions.** Cold starts are accepted to stay within free tier.
- **Previous implementation was reset.** v1 is a rebuild with simplified architecture. See "Discovered Patterns" below for what to avoid.

---

## Do not

- Add multiple calendar providers — Google Calendar only in v1
- Store or display event titles from Google Calendar — freebusy only
- Compute overlaps client-side — always use the server-side function result
- Commit `.env` files or any file containing credentials or secrets
- Assume the backend service is running — verify it first
- Use Firestore Timestamps — store UTC milliseconds as int
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

If Cloud Functions were changed, also verify:

```bash
cd functions
npm run build
npm test
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
| Frontend | Flutter (Dart 3.x) | Latest stable (April 2026) |
| State management | Riverpod | Latest stable |
| Routing | go_router | Latest stable |
| Backend | Firebase (Blaze plan) | — |
| Auth | Firebase Auth (Google + Apple) | — |
| Database | Cloud Firestore | — |
| Server logic | Cloud Functions v2 (Node.js 18) | TypeScript |
| Push notifications | FCM | — |
| Calendar | Google Calendar API v3 (freebusy) | — |
| Timezone (Flutter) | `timezone` package | Latest |
| Timezone (Functions) | Luxon | Latest |
| Recurrence (Functions) | rrule (npm) | Latest |

## Testing Strategy

### Flutter Tests

```bash
flutter test                              # All tests
flutter test test/core/models/            # Specific directory
flutter test --coverage                   # With coverage
```

**Test structure:**
```
test/
├── core/models/
│   ├── user_model_test.dart
│   ├── couple_model_test.dart
│   ├── time_block_test.dart
│   └── overlap_result_test.dart
├── services/
│   ├── auth_service_test.dart
│   ├── firestore_service_test.dart
│   └── calendar_service_test.dart
└── features/
    ├── auth_screen_test.dart
    └── ...
```

**Test patterns:**
- **Model tests**: fromJson/toJson round-trip, field validation, copyWith
- **Service tests**: Mock Firebase/Auth/Firestore with `mockito` or `firebase_auth_mocks`
- **Widget tests**: `flutter_test`, pumpWidget, verify UI state and interactions
- **Router tests**: Mock auth state, verify redirect guards

### Cloud Functions Tests

```bash
cd functions
npm test
```

**Test patterns:**
- Use `firebase-functions-test` for Firestore trigger testing
- Mock Firebase Admin SDK for unit tests
- Integration tests: deploy to Firebase, trigger with real writes

### Security Rules Tests

```bash
firebase emulators:exec --only firestore "npm test"
```

**Test patterns:**
- Use `@firebase/rules-unit-testing`
- Test each rule condition: owner access, partner access, deny others
- Test subcollection access requires couple membership

## Conventions

### Naming

- **Collections**: plural lowercase (`users`, `couples`, `invites`, `overlaps`)
- **Subcollections**: lowercase (`blocks`, `windows`)
- **Fields**: camelCase (`startUtc`, `endUtc`, `coupleId`, `displayName`)
- **Files**: snake_case (`user_model.dart`, `auth_service.dart`)
- **Classes**: PascalCase (`UserModel`, `AuthService`)
- **Providers**: camelCase with `Provider` suffix (`authStateProvider`, `firestoreServiceProvider`)

### Data Storage

- **Timestamps**: UTC milliseconds since epoch (int), NOT Firestore Timestamp
- **Timezone**: IANA string (e.g., `"America/New_York"`, `"Africa/Johannesburg"`)
- **Firestore paths**:
  - `users/{uid}`
  - `couples/{coupleId}`
  - `invites/{code}`
  - `timeblocks/{coupleId}/blocks/{blockId}`
  - `overlaps/{coupleId}/windows/latest`

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
class FirestoreException implements Exception {
  final String message;
  final String code;
  FirestoreException(this.message, this.code);
}

// Providers wrap in AsyncValue
state = AsyncValue.loading();
try {
  final user = await firestoreService.getUser(uid);
  state = AsyncValue.data(user);
} catch (e) {
  state = AsyncValue.error(e, StackTrace.current);
}
```

## Discovered Patterns (from previous implementation)

**What worked:**
- Firebase + Firestore real-time sync for couples
- Subcollections pattern for blocks
- IANA timezone storage
- FCM for notifications

**What failed (avoid):**
- Complex auth state management → Use simple Riverpod StateNotifier
- Multiple calendar providers → Google only in v1
- Intricate overlap bugs → Well-specified algorithm in spec
- Navigation confusion → Clear redirect guards

## Cost-Conscious Design

- **Free tier limits**: 50k Firestore reads/day, 20k writes/day, 2M Function invocations/month
- **Optimizations**:
  - Debounce overlap computation (2-second delay, hash comparison)
  - Batch writes for calendar sync (delete + create in one batch)
  - No min instances for Functions (accept cold starts)
  - Minimal data storage (no event titles, 14-day horizon only)
- **Monitoring**: Set GCP budget alert at $1/month, check Firebase Console weekly
