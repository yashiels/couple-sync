# AGENTS.md

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
