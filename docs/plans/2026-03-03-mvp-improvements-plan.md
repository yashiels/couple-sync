# Couple Schedule MVP Improvements — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Evolve the existing Couple Schedule app into a polished MVP with Microsoft Calendar integration, Google Meet links, AI suggestions, pattern detection, and a warm modern UI — all on Google Cloud services.

**Architecture:** Feature-first Flutter + Riverpod + Firebase. Consolidate the dual prototype/production layers into one production app. Add Microsoft Graph API calendar sync, Google Calendar write-back for Meet events, Gemini Flash for activity suggestions, and a pattern detection Cloud Function. Auth simplified to Google/Apple sign-in only.

**Tech Stack:** Flutter (Dart 3.11+), Riverpod, go_router, Firebase (Auth/Firestore/FCM/Functions), Google Calendar API v3, Microsoft Graph API, Vertex AI Gemini Flash, luxon (Cloud Functions)

---

## Task 1: Unify TimeBlock Model

**Files:**
- Modify: `lib/shared/models/time_block_model.dart`
- Delete: `lib/core/models/time_block.dart`
- Modify: `lib/features/calendar/services/google_calendar_service.dart`
- Modify: `lib/features/calendar/services/calendar_sync_service.dart`
- Modify: `lib/features/calendar/services/apple_calendar_service.dart`
- Modify: `lib/core/utils/mock_data.dart`
- Modify: `lib/features/home/screens/home_screen.dart`
- Modify: `lib/features/calendar/screens/calendar_screen.dart`
- Modify: `lib/features/calendar/widgets/week_view.dart`
- Modify: `lib/features/calendar/widgets/block_overlay.dart`
- Modify: `lib/features/overlap/screens/free_windows_screen.dart`
- Test: `test/models/time_block_model_test.dart`

**Context:** Two conflicting `TimeBlock` models exist. `lib/core/models/time_block.dart` uses `BlockType.calendarEvent/customBlock/recurring` and `BlockOwner.me/partner`. `lib/shared/models/time_block_model.dart` uses `BlockType.busy/free` and has `BlockCategory`. We need one model.

**Step 1: Write tests for the unified TimeBlock model**

```dart
// test/models/time_block_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/shared/models/time_block_model.dart';

void main() {
  group('BlockType', () {
    test('has busy, free, tentative values', () {
      expect(BlockType.values, containsAll([BlockType.busy, BlockType.free, BlockType.tentative]));
    });
  });

  group('BlockSource', () {
    test('has google, microsoft, manual values', () {
      expect(BlockSource.values, containsAll([
        BlockSource.google,
        BlockSource.microsoft,
        BlockSource.manual,
      ]));
    });
  });

  group('BlockCategory', () {
    test('has study and social categories', () {
      expect(BlockCategory.values, contains(BlockCategory.study));
      expect(BlockCategory.values, contains(BlockCategory.social));
    });
  });

  group('TimeBlock', () {
    test('toFirestore and fromFirestore round-trip', () {
      final block = TimeBlock(
        id: 'test-id',
        userId: 'user1',
        coupleId: 'couple1',
        type: BlockType.busy,
        title: 'Work meeting',
        startUtc: DateTime.utc(2026, 3, 10, 9, 0),
        endUtc: DateTime.utc(2026, 3, 10, 10, 0),
        timezone: 'Africa/Johannesburg',
        source: BlockSource.google,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.work,
        createdAt: DateTime.utc(2026, 3, 1),
      );

      final map = block.toFirestore();
      expect(map['source'], 'google');
      expect(map['category'], 'work');
      expect(map['type'], 'busy');
    });

    test('duration calculates correctly', () {
      final block = TimeBlock(
        id: 'test',
        userId: 'u1',
        type: BlockType.busy,
        title: 'Test',
        startUtc: DateTime.utc(2026, 3, 10, 9, 0),
        endUtc: DateTime.utc(2026, 3, 10, 11, 30),
        timezone: 'UTC',
        source: BlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.other,
        createdAt: DateTime.utc(2026, 3, 1),
      );
      expect(block.duration.inMinutes, 150);
    });

    test('copyWith preserves unchanged fields', () {
      final block = TimeBlock(
        id: 'test',
        userId: 'u1',
        type: BlockType.busy,
        title: 'Original',
        startUtc: DateTime.utc(2026, 3, 10, 9, 0),
        endUtc: DateTime.utc(2026, 3, 10, 10, 0),
        timezone: 'UTC',
        source: BlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.work,
        createdAt: DateTime.utc(2026, 3, 1),
      );

      final updated = block.copyWith(title: 'Updated', category: BlockCategory.study);
      expect(updated.title, 'Updated');
      expect(updated.category, BlockCategory.study);
      expect(updated.userId, 'u1');
      expect(updated.source, BlockSource.manual);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule && flutter test test/models/time_block_model_test.dart`
Expected: FAIL — test file doesn't exist yet, and model needs updates

**Step 3: Update the unified TimeBlock model**

Update `lib/shared/models/time_block_model.dart`:
- Rename `CalendarSource` to `BlockSource`
- Add `microsoft` to `BlockSource` enum (values: `google`, `microsoft`, `manual`)
- Remove `apple` and `outlook` from enum
- Add `study` and `social` to `BlockCategory` enum
- Add `tentative` to `BlockType` enum
- Keep all existing serialization logic

```dart
// Updated enums in lib/shared/models/time_block_model.dart
enum BlockType { busy, free, tentative }

enum BlockCategory {
  work,
  study,
  commute,
  exercise,
  social,
  meals,
  sleep,
  personal,
  other,
}

enum BlockSource { google, microsoft, manual }

enum TimeBlockVisibility { bothPartners, onlyMe }
```

**Step 4: Delete `lib/core/models/time_block.dart`**

Remove the file entirely.

**Step 5: Update all imports that referenced `core/models/time_block.dart`**

Change every import of `../../../core/models/time_block.dart` or similar to use `../../../shared/models/time_block_model.dart`. Files to update:
- `lib/features/calendar/services/google_calendar_service.dart` — change import, update `TimeBlock` constructor calls to use `BlockSource.google` instead of `CalendarSource.google`, use `BlockType.busy` instead of `BlockType.calendarEvent`, remove `owner` field references, add required `category`, `createdAt` fields
- `lib/features/calendar/services/apple_calendar_service.dart` — same pattern
- `lib/features/calendar/services/calendar_sync_service.dart` — change import, update `CalendarSource` → `BlockSource`, update `BlockType.calendarEvent` → filter by `source` instead of `type` for stale block detection
- `lib/core/utils/mock_data.dart` — update mock blocks to use new model
- `lib/features/home/screens/home_screen.dart` — update import
- `lib/features/calendar/screens/calendar_screen.dart` — update import
- `lib/features/calendar/widgets/week_view.dart` — update import
- `lib/features/calendar/widgets/block_overlay.dart` — update import
- `lib/features/overlap/screens/free_windows_screen.dart` — update import

**Step 6: Update `CalendarSyncService._writeToFirestore` stale block detection**

The current code filters stale blocks by `BlockType.calendarEvent.name`. Since we're removing that enum value, filter by `source` field instead:

```dart
// In _writeToFirestore, change:
// .where('type', isEqualTo: BlockType.calendarEvent.name)
// To:
.where('source', whereIn: [BlockSource.google.name, BlockSource.microsoft.name])
```

**Step 7: Move `FreeWindow` class to its own file**

Create `lib/shared/models/free_window.dart` with the `FreeWindow` class from the deleted `core/models/time_block.dart`. Update imports in mock_data and any screen that used it.

**Step 8: Run tests to verify they pass**

Run: `flutter test test/models/time_block_model_test.dart`
Expected: PASS

**Step 9: Run flutter analyze to check for errors**

Run: `flutter analyze`
Expected: No errors (warnings OK for now)

**Step 10: Commit**

```bash
git add -A
git commit -m "refactor: unify TimeBlock model, remove duplicate core model

Consolidate two conflicting TimeBlock models into one in shared/models/.
Add BlockSource.microsoft, BlockCategory.study/social, BlockType.tentative.
Update all calendar services to use unified model.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Fix Firestore Overlap Path & Add Missing AppColors

**Files:**
- Modify: `lib/shared/providers/overlap_providers.dart`
- Modify: `lib/core/theme/app_theme.dart`
- Test: `test/providers/overlap_providers_test.dart`

**Context:** `shared/providers/overlap_providers.dart:9` reads from `collection('overlapWindows')` but the Cloud Function writes to `collection('overlaps').doc(coupleId).collection('windows').doc('latest')`. Also `AppColors.success` is referenced but not defined.

**Step 1: Fix the Firestore path in overlap_providers.dart**

Change line 9 from:
```dart
.collection('overlapWindows')
.doc(coupleId)
```
To:
```dart
.collection('overlaps')
.doc(coupleId)
.collection('windows')
.doc('latest')
```

**Step 2: Add missing colors to AppColors**

Add to `lib/core/theme/app_theme.dart` in the `AppColors` class:

```dart
// Semantic colors
static const Color success = Color(0xFF7BC47F);
static const Color warning = Color(0xFFF5C842);

// Updated palette for warm modern design
static const Color background = Color(0xFFFFF8F5);
static const Color partnerBlueLight = Color(0xFFEBF3FC);
static const Color roseLightBg = Color(0xFFFCEEF1);
```

**Step 3: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors related to `AppColors.success`

**Step 4: Commit**

```bash
git add lib/shared/providers/overlap_providers.dart lib/core/theme/app_theme.dart
git commit -m "fix: correct Firestore overlap path and add missing AppColors

Align overlap_providers.dart to read from overlaps/{coupleId}/windows/latest
(matching Cloud Function write path). Add success, warning colors.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Remove Prototype Layer & Consolidate Screens

**Files:**
- Modify: `lib/main.dart` — rewrite to production entry point
- Delete: `lib/features/home/screens/home_screen.dart` (prototype version)
- Delete: `lib/features/calendar/screens/calendar_screen.dart` (prototype version)
- Delete: `lib/features/overlap/screens/free_windows_screen.dart` (prototype version)
- Delete: `lib/features/settings/screens/settings_screen.dart` (prototype version)
- Delete: `lib/features/calendar/screens/calendar_connect_screen.dart` (will rebuild in Task 9)
- Modify: `lib/core/router/router.dart` — add ShellRoute with bottom nav
- Modify: `lib/features/home/home_screen.dart` — upgrade from placeholder to rich home
- Modify: `lib/features/calendar/calendar_screen.dart` — upgrade from placeholder
- Modify: `lib/features/settings/settings_screen.dart` — upgrade from placeholder

**Context:** The app has two parallel screen sets — prototype (`features/*/screens/`) and production (`features/*/`). We need one production set with the rich UI features from the prototype screens merged into the production screens, all backed by Firestore providers.

**Step 1: Rewrite `lib/main.dart` as production entry point**

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const ProviderScope(child: CoupleScheduleApp()));
}

class CoupleScheduleApp extends ConsumerWidget {
  const CoupleScheduleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Couple Schedule',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

**Step 2: Add ShellRoute with bottom nav to `lib/core/router/router.dart`**

Update the router to wrap the main screens (home, calendar, overlap) in a ShellRoute with bottom navigation. Keep auth redirect logic. Use the same bottom nav design from the old `main.dart` `_BottomNav`.

**Step 3: Delete prototype screen files**

Delete these files:
- `lib/features/home/screens/home_screen.dart`
- `lib/features/calendar/screens/calendar_screen.dart`
- `lib/features/calendar/screens/calendar_connect_screen.dart`
- `lib/features/overlap/screens/free_windows_screen.dart`
- `lib/features/settings/screens/settings_screen.dart`

Also delete `lib/features/settings/providers/settings_provider.dart` and `lib/features/settings/widgets/` if they reference prototype-only providers.

**Step 4: Upgrade production screens**

Merge the rich UI elements from the deleted prototype screens into the production screens at:
- `lib/features/home/home_screen.dart` — add timezone clocks, hero card, daily timeline from the prototype version. Wire to Firestore providers instead of MockData.
- `lib/features/calendar/calendar_screen.dart` — add week view from prototype. Wire to Firestore.
- `lib/features/settings/settings_screen.dart` — add full settings from prototype. Wire to Firestore.

**Step 5: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors — all imports resolved, no dead references

**Step 6: Commit**

```bash
git add -A
git commit -m "refactor: consolidate prototype and production layers into single app

Remove prototype main.dart and duplicate screen files. Merge rich UI
from prototype screens into production screens. All screens now use
Firestore-backed Riverpod providers with auth guards.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Simplify Auth to Google & Apple Only

**Files:**
- Modify: `lib/shared/services/auth_service.dart`
- Modify: `lib/shared/providers/auth_providers.dart`
- Modify: `lib/features/auth/auth_screen.dart`
- Modify: `pubspec.yaml` — add `sign_in_with_apple`
- Test: `test/services/auth_service_test.dart`

**Context:** Current auth has email/password + Google. Design says Google & Apple only. Need to add Apple Sign-In and remove email/password.

**Step 1: Add `sign_in_with_apple` to pubspec.yaml**

```yaml
# Under dependencies, after google_sign_in
sign_in_with_apple: ^6.1.0
```

Run: `flutter pub get`

**Step 2: Update AuthService — remove email methods, add Apple**

In `lib/shared/services/auth_service.dart`:
- Remove `signUpWithEmail` method
- Remove `signInWithEmail` method
- Remove `sendPasswordReset` method
- Add `signInWithApple` method:

```dart
Future<UserModel> signInWithApple() async {
  final appleProvider = AppleAuthProvider()
    ..addScope('email')
    ..addScope('name');
  final userCred = await _auth.signInWithProvider(appleProvider);
  return _fetchOrCreateUser(userCred.user!);
}
```

- Update `_createUserDocument` to auto-detect timezone:

```dart
Future<UserModel> _createUserDocument(User user, {String? displayName}) async {
  final detectedTimezone = DateTime.now().timeZoneName;
  final model = UserModel(
    uid: user.uid,
    email: user.email ?? '',
    displayName: displayName ?? user.displayName ?? user.email?.split('@').first ?? 'User',
    photoUrl: user.photoURL,
    timezone: detectedTimezone,
    createdAt: DateTime.now().toUtc(),
  );
  await _firestore.collection('users').doc(user.uid).set(model.toFirestore());
  return model;
}
```

**Step 3: Update AuthNotifier — remove email methods, add Apple**

In `lib/shared/providers/auth_providers.dart`:
- Remove `signUpWithEmail` method
- Remove `signInWithEmail` method
- Add `signInWithApple` method (same pattern as `signInWithGoogle`)

**Step 4: Rewrite AuthScreen — two buttons only**

Replace the entire `lib/features/auth/auth_screen.dart` with a clean screen:
- Logo + tagline at top
- "Continue with Google" button (full-width, Google-branded)
- "Continue with Apple" button (full-width, Apple-branded, only on iOS or always visible)
- Remove `_FormToggle`, `_LoginForm`, `_SignupForm`
- Keep `_Logo`

```dart
class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authNotifierProvider);
    final isLoading = status == AuthStatus.loading;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Couple Schedule', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 8),
              Text(
                'Sync your lives, find your moments.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(flex: 3),
              // Google Sign In
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : () async {
                    try {
                      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
                      if (context.mounted) context.go('/home');
                    } catch (_) {}
                  },
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: const BorderSide(color: AppColors.divider),
                  ),
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                  label: const Text('Continue with Google', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              // Apple Sign In
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: isLoading ? null : () async {
                    try {
                      await ref.read(authNotifierProvider.notifier).signInWithApple();
                      if (context.mounted) context.go('/home');
                    } catch (_) {}
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.apple_rounded, size: 28),
                  label: const Text('Continue with Apple', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 32),
              if (isLoading)
                const CircularProgressIndicator(),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Step 5: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: simplify auth to Google and Apple sign-in only

Remove email/password auth flow. Add Apple Sign-In via Firebase.
Redesign auth screen with two clean sign-in buttons.
Auto-detect timezone on account creation.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Remove device_calendar & Apple Calendar Service

**Files:**
- Modify: `pubspec.yaml` — remove `device_calendar: ^4.3.1`
- Delete: `lib/features/calendar/services/apple_calendar_service.dart`
- Delete: `lib/features/calendar/providers/apple_calendar_provider.dart`
- Modify: `lib/features/calendar/services/calendar_sync_service.dart` — remove Apple references
- Modify: `lib/features/calendar/providers/google_calendar_provider.dart` — if it references Apple

**Step 1: Remove `device_calendar` from pubspec.yaml**

Remove line: `device_calendar: ^4.3.1`

Run: `flutter pub get`

**Step 2: Delete Apple calendar files**

Delete:
- `lib/features/calendar/services/apple_calendar_service.dart`
- `lib/features/calendar/providers/apple_calendar_provider.dart`

**Step 3: Simplify CalendarSyncService**

In `lib/features/calendar/services/calendar_sync_service.dart`:
- Remove `AppleCalendarService` constructor parameter and field
- Remove all `syncApple` parameters and Apple-related code from `sync()` method
- Remove `CalendarSource.apple` references (now `BlockSource` — already gone from enum in Task 1)

**Step 4: Run flutter analyze and pub get**

Run: `flutter pub get && flutter analyze`
Expected: No errors

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove device_calendar and Apple Calendar service

Users will connect calendars via API only (Google Calendar API,
Microsoft Graph API). Simplifies codebase and removes iOS EventKit
permission requirements.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Add UserModel Fields for Calendar Connections

**Files:**
- Modify: `lib/shared/models/user_model.dart`
- Test: `test/models/user_model_test.dart`

**Context:** Need to track Microsoft connection status, default calendar for couple events, and FCM token in the model.

**Step 1: Write test**

```dart
// test/models/user_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/shared/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('new fields have defaults', () {
      final user = UserModel(
        uid: 'test',
        email: 'test@test.com',
        displayName: 'Test',
        timezone: 'Africa/Johannesburg',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(user.googleConnected, false);
      expect(user.microsoftConnected, false);
      expect(user.microsoftEmail, isNull);
      expect(user.defaultCoupleCalendarId, isNull);
    });

    test('toFirestore includes new fields', () {
      final user = UserModel(
        uid: 'test',
        email: 'test@test.com',
        displayName: 'Test',
        timezone: 'UTC',
        createdAt: DateTime.utc(2026, 1, 1),
        googleConnected: true,
        microsoftConnected: true,
        microsoftEmail: 'test@outlook.com',
      );
      final map = user.toFirestore();
      expect(map['googleConnected'], true);
      expect(map['microsoftConnected'], true);
      expect(map['microsoftEmail'], 'test@outlook.com');
    });
  });
}
```

**Step 2: Update UserModel**

Add fields to `lib/shared/models/user_model.dart`:

```dart
final bool googleConnected;
final bool microsoftConnected;
final String? microsoftEmail;
final String? defaultCoupleCalendarId;
```

Update constructor, `fromFirestore`, `toFirestore`, and `copyWith`.

**Step 3: Run tests**

Run: `flutter test test/models/user_model_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add calendar connection fields to UserModel

Add googleConnected, microsoftConnected, microsoftEmail, and
defaultCoupleCalendarId fields for tracking calendar integrations.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Microsoft Calendar Service

**Files:**
- Create: `lib/features/calendar/services/microsoft_calendar_service.dart`
- Create: `lib/features/calendar/providers/microsoft_calendar_provider.dart`
- Modify: `lib/features/calendar/services/calendar_sync_service.dart`
- Modify: `pubspec.yaml` — add `flutter_appauth`, `flutter_secure_storage`
- Test: `test/services/microsoft_calendar_service_test.dart`

**Context:** Need Microsoft Graph API integration for her school calendar. OAuth2 PKCE flow, fetch calendarView as busy blocks.

**Step 1: Add dependencies to pubspec.yaml**

```yaml
# Microsoft Calendar
flutter_appauth: ^7.0.1
flutter_secure_storage: ^9.2.4
```

Run: `flutter pub get`

**Step 2: Create MicrosoftCalendarService**

Create `lib/features/calendar/services/microsoft_calendar_service.dart`:

```dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../shared/models/time_block_model.dart';

class MicrosoftCalendarService {
  static const _clientId = 'YOUR_MS_CLIENT_ID'; // Set in env/config
  static const _redirectUri = 'com.coupleschedule.app://oauth2redirect';
  static const _authority = 'https://login.microsoftonline.com/common';
  static const _scopes = ['Calendars.Read', 'User.Read', 'offline_access'];

  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final FirebaseFirestore _firestore;

  bool _isConnected = false;
  String? _connectedEmail;

  MicrosoftCalendarService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  bool get isConnected => _isConnected;
  String? get connectedEmail => _connectedEmail;

  /// Initiates Microsoft OAuth2 PKCE flow.
  Future<bool> connect() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _clientId,
          _redirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: '$_authority/oauth2/v2.0/authorize',
            tokenEndpoint: '$_authority/oauth2/v2.0/token',
          ),
          scopes: _scopes,
        ),
      );

      if (result == null) return false;

      await _secureStorage.write(key: 'ms_access_token', value: result.accessToken);
      await _secureStorage.write(key: 'ms_refresh_token', value: result.refreshToken);

      _connectedEmail = await _fetchUserEmail(result.accessToken!);
      _isConnected = true;
      return true;
    } catch (e) {
      debugPrint('MicrosoftCalendarService.connect error: $e');
      return false;
    }
  }

  /// Disconnects by clearing stored tokens.
  Future<void> disconnect() async {
    await _secureStorage.delete(key: 'ms_access_token');
    await _secureStorage.delete(key: 'ms_refresh_token');
    _isConnected = false;
    _connectedEmail = null;
  }

  /// Tries to restore session from stored tokens.
  Future<bool> tryRestoreSession() async {
    final refreshToken = await _secureStorage.read(key: 'ms_refresh_token');
    if (refreshToken == null) return false;

    try {
      final result = await _appAuth.token(
        TokenRequest(
          _clientId,
          _redirectUri,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: '$_authority/oauth2/v2.0/authorize',
            tokenEndpoint: '$_authority/oauth2/v2.0/token',
          ),
          refreshToken: refreshToken,
          scopes: _scopes,
        ),
      );

      if (result == null) return false;

      await _secureStorage.write(key: 'ms_access_token', value: result.accessToken);
      if (result.refreshToken != null) {
        await _secureStorage.write(key: 'ms_refresh_token', value: result.refreshToken);
      }

      _connectedEmail = await _fetchUserEmail(result.accessToken!);
      _isConnected = true;
      return true;
    } catch (e) {
      debugPrint('MicrosoftCalendarService.tryRestoreSession error: $e');
      return false;
    }
  }

  /// Fetches busy periods from Microsoft Calendar for the next [days] days.
  Future<List<TimeBlock>> fetchBusyPeriods({
    required String userId,
    required String coupleId,
    int days = 14,
  }) async {
    final accessToken = await _getValidAccessToken();
    if (accessToken == null) throw Exception('Not signed in to Microsoft');

    final now = DateTime.now().toUtc();
    final until = now.add(Duration(days: days));

    final uri = Uri.parse(
      'https://graph.microsoft.com/v1.0/me/calendarView'
      '?startDateTime=${now.toIso8601String()}'
      '&endDateTime=${until.toIso8601String()}'
      '&\$select=start,end,subject,showAs'
      '&\$top=250',
    );

    final response = await http.get(uri, headers: {
      'Authorization': 'Bearer $accessToken',
      'Prefer': 'outlook.timezone="UTC"',
    });

    if (response.statusCode != 200) {
      throw Exception('Microsoft Graph API error: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final events = (data['value'] as List<dynamic>?) ?? [];

    return events
        .where((e) => e['showAs'] != 'free') // Only busy/tentative events
        .map((e) {
      final start = DateTime.parse(e['start']['dateTime'] as String).toUtc();
      final end = DateTime.parse(e['end']['dateTime'] as String).toUtc();

      return TimeBlock(
        id: '',
        userId: userId,
        coupleId: coupleId,
        type: BlockType.busy,
        title: 'Busy', // Privacy: don't sync titles
        startUtc: start,
        endUtc: end,
        timezone: 'UTC',
        source: BlockSource.microsoft,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.other,
        createdAt: DateTime.now().toUtc(),
      );
    }).toList();
  }

  /// Syncs Microsoft calendar events to Firestore.
  Future<void> syncToFirestore({
    required String userId,
    required String coupleId,
  }) async {
    final blocks = await fetchBusyPeriods(userId: userId, coupleId: coupleId);

    final blocksRef = _firestore
        .collection('timeblocks')
        .doc(coupleId)
        .collection('blocks');

    final batch = _firestore.batch();

    // Remove stale Microsoft blocks for this user
    final stale = await blocksRef
        .where('userId', isEqualTo: userId)
        .where('source', isEqualTo: BlockSource.microsoft.name)
        .get();
    for (final doc in stale.docs) {
      batch.delete(doc.reference);
    }

    // Write fresh blocks
    for (final block in blocks) {
      batch.set(blocksRef.doc(), block.toFirestore());
    }

    await batch.commit();
  }

  // --- Private helpers ---

  Future<String?> _getValidAccessToken() async {
    var token = await _secureStorage.read(key: 'ms_access_token');
    if (token == null) {
      final restored = await tryRestoreSession();
      if (!restored) return null;
      token = await _secureStorage.read(key: 'ms_access_token');
    }
    return token;
  }

  Future<String?> _fetchUserEmail(String accessToken) async {
    final response = await http.get(
      Uri.parse('https://graph.microsoft.com/v1.0/me?\$select=mail,userPrincipalName'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return (data['mail'] as String?) ?? (data['userPrincipalName'] as String?);
    }
    return null;
  }
}
```

**Step 3: Create Microsoft calendar provider**

Create `lib/features/calendar/providers/microsoft_calendar_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/microsoft_calendar_service.dart';

final microsoftCalendarServiceProvider = Provider<MicrosoftCalendarService>((ref) {
  return MicrosoftCalendarService();
});

final microsoftCalendarConnectionProvider = StateProvider<bool>((ref) => false);

final microsoftCalendarLastSyncProvider = StateProvider<DateTime?>((ref) => null);
```

**Step 4: Update CalendarSyncService to support Microsoft**

Add Microsoft to `lib/features/calendar/services/calendar_sync_service.dart`:
- Add `MicrosoftCalendarService` constructor parameter
- Add `syncMicrosoft` parameter to `sync()` method
- Fetch Microsoft busy periods alongside Google

**Step 5: Run flutter analyze**

Run: `flutter pub get && flutter analyze`
Expected: No errors

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Microsoft Calendar integration via Graph API

OAuth2 PKCE flow with flutter_appauth for Microsoft accounts.
Fetch calendarView as busy blocks, sync to Firestore.
Secure token storage with flutter_secure_storage.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 8: Google Calendar Write-Back for Meet Events

**Files:**
- Modify: `lib/features/calendar/services/google_calendar_service.dart`
- Create: `lib/shared/models/scheduling_request.dart`
- Create: `lib/shared/providers/scheduling_providers.dart`
- Modify: `pubspec.yaml` — ensure `googleapis` includes Calendar write scope

**Context:** Need to create Google Calendar events with Meet links from confirmed free windows.

**Step 1: Update GoogleSignIn scopes**

In `lib/features/calendar/services/google_calendar_service.dart`, change scopes:

```dart
static const _scopes = [
  gcal.CalendarApi.calendarReadonlyScope,
  gcal.CalendarApi.calendarEventsScope, // Write access for creating Meet events
];
```

**Step 2: Add `createMeetEvent` method to GoogleCalendarService**

```dart
/// Creates a Google Calendar event with an auto-generated Google Meet link.
/// Returns the Meet link URL.
Future<String?> createMeetEvent({
  required String title,
  required DateTime startUtc,
  required DateTime endUtc,
  required String timezone,
  String? partnerEmail,
}) async {
  final account = _googleSignIn.currentUser ??
      await _googleSignIn.signInSilently();
  if (account == null) throw Exception('Not signed in to Google Calendar');

  final authHeaders = await account.authHeaders;
  final client = _AuthClient(authHeaders);

  try {
    final calendarApi = gcal.CalendarApi(client);

    final event = gcal.Event(
      summary: title,
      start: gcal.EventDateTime(dateTime: startUtc, timeZone: timezone),
      end: gcal.EventDateTime(dateTime: endUtc, timeZone: timezone),
      conferenceData: gcal.ConferenceData(
        createRequest: gcal.CreateConferenceRequest(
          requestId: DateTime.now().millisecondsSinceEpoch.toString(),
          conferenceSolutionKey: gcal.ConferenceSolutionKey(type: 'hangoutsMeet'),
        ),
      ),
      attendees: partnerEmail != null
          ? [gcal.EventAttendee(email: partnerEmail)]
          : null,
    );

    final created = await calendarApi.events.insert(
      event,
      'primary',
      conferenceDataVersion: 1,
    );

    return created.conferenceData?.entryPoints
        ?.firstWhere((e) => e.entryPointType == 'video', orElse: () => gcal.EntryPoint())
        .uri;
  } finally {
    client.close();
  }
}
```

**Step 3: Create SchedulingRequest model**

Create `lib/shared/models/scheduling_request.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class SchedulingRequest {
  final String id;
  final String coupleId;
  final String requestedByUid;
  final DateTime windowStartUtc;
  final DateTime windowEndUtc;
  final String title;
  final String status; // pending, created, failed
  final String? meetLink;
  final String? calendarEventId;
  final DateTime createdAt;

  const SchedulingRequest({
    required this.id,
    required this.coupleId,
    required this.requestedByUid,
    required this.windowStartUtc,
    required this.windowEndUtc,
    required this.title,
    required this.status,
    this.meetLink,
    this.calendarEventId,
    required this.createdAt,
  });

  factory SchedulingRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SchedulingRequest(
      id: doc.id,
      coupleId: d['coupleId'] as String,
      requestedByUid: d['requestedByUid'] as String,
      windowStartUtc: (d['windowStartUtc'] as Timestamp).toDate().toUtc(),
      windowEndUtc: (d['windowEndUtc'] as Timestamp).toDate().toUtc(),
      title: d['title'] as String,
      status: d['status'] as String? ?? 'pending',
      meetLink: d['meetLink'] as String?,
      calendarEventId: d['calendarEventId'] as String?,
      createdAt: (d['createdAt'] as Timestamp).toDate().toUtc(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'coupleId': coupleId,
    'requestedByUid': requestedByUid,
    'windowStartUtc': Timestamp.fromDate(windowStartUtc),
    'windowEndUtc': Timestamp.fromDate(windowEndUtc),
    'title': title,
    'status': status,
    'meetLink': meetLink,
    'calendarEventId': calendarEventId,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
```

**Step 4: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Google Calendar write-back for Meet event creation

Add createMeetEvent to GoogleCalendarService with conferenceData
for auto-generated Meet links. Add SchedulingRequest model for
tracking event creation requests.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Enhanced Manual Blocks with Categories & Presets

**Files:**
- Modify: `lib/features/blocks/block_form_screen.dart`
- Modify: `lib/features/blocks/blocks_screen.dart`
- Modify: `lib/shared/providers/block_providers.dart`

**Context:** Need quick-add presets (Study, Gym, Commute, Work), enhanced category picker, recurrence options. Remove hardcoded demo UIDs — use real auth.

**Step 1: Remove hardcoded demo UIDs**

In `lib/features/blocks/blocks_screen.dart` and `lib/features/blocks/block_form_screen.dart`:
- Remove `const _demoCoupleId = 'demo_couple'` and `const _demoUid = 'demo_uid'`
- Read from `currentUserProvider` and `currentCoupleProvider` instead

**Step 2: Add category icons and colors mapping**

Create a utility map in `lib/features/blocks/block_form_screen.dart`:

```dart
const _categoryMeta = {
  BlockCategory.work: (icon: Icons.work_rounded, color: Color(0xFF5B7FE8), label: 'Work'),
  BlockCategory.study: (icon: Icons.menu_book_rounded, color: Color(0xFF8B5CF6), label: 'Study'),
  BlockCategory.commute: (icon: Icons.directions_car_rounded, color: Color(0xFF6B7280), label: 'Commute'),
  BlockCategory.exercise: (icon: Icons.fitness_center_rounded, color: Color(0xFF10B981), label: 'Exercise'),
  BlockCategory.social: (icon: Icons.people_rounded, color: Color(0xFFF59E0B), label: 'Social'),
  BlockCategory.sleep: (icon: Icons.bedtime_rounded, color: Color(0xFF6366F1), label: 'Sleep'),
  BlockCategory.personal: (icon: Icons.person_rounded, color: Color(0xFFEC4899), label: 'Personal'),
  BlockCategory.meals: (icon: Icons.restaurant_rounded, color: Color(0xFFF97316), label: 'Meals'),
  BlockCategory.other: (icon: Icons.more_horiz_rounded, color: Color(0xFF9CA3AF), label: 'Other'),
};
```

**Step 3: Add quick-add presets**

Add preset chips at the top of the block form:
- "Study session" → 2hr, category: study
- "Gym" → 1hr, category: exercise
- "Commute" → 30min, category: commute
- "Work" → 8hr, category: work

**Step 4: Update recurrence options**

Replace current recurrence UI with toggle + options:
- None, Daily, Weekdays, Weekly, Custom

**Step 5: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: enhanced block form with categories, presets, and recurrence

Add quick-add presets (Study, Gym, Commute, Work), category chip
selector with icons/colors, improved recurrence options.
Remove hardcoded demo UIDs — use real auth providers.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 10: Update Cloud Functions — Gemini Suggestions

**Files:**
- Modify: `functions/src/overlap.ts`
- Modify: `functions/package.json`
- Create: `functions/src/gemini.ts`

**Context:** After computing overlap windows, call Gemini Flash to suggest activities for each window. Store suggestions in the windows document.

**Step 1: Add Gemini dependency**

In `functions/package.json`, add:
```json
"@google/generative-ai": "^0.21.0"
```

Run: `cd functions && npm install`

**Step 2: Create Gemini helper**

Create `functions/src/gemini.ts`:

```typescript
import { GoogleGenerativeAI } from "@google/generative-ai";

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || "");

export async function suggestActivities(
  windows: Array<{ startMs: number; endMs: number; durationMinutes: number }>
): Promise<Map<number, string>> {
  const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });
  const suggestions = new Map<number, string>();

  // Batch windows into a single prompt for efficiency
  const windowDescriptions = windows.slice(0, 10).map((w, i) => {
    const start = new Date(w.startMs);
    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    const day = days[start.getUTCDay()];
    const hour = start.getUTCHours();
    const isWeekend = start.getUTCDay() === 0 || start.getUTCDay() === 6;

    return `${i + 1}. ${day} ${hour}:00 UTC, ${w.durationMinutes} minutes${isWeekend ? " (weekend)" : ""}`;
  }).join("\n");

  const prompt = `Suggest one couple activity for each time window (max 8 words each). Be specific and fun.\n\n${windowDescriptions}\n\nFormat: one suggestion per line, numbered.`;

  try {
    const result = await model.generateContent(prompt);
    const text = result.response.text();
    const lines = text.split("\n").filter((l) => l.trim());

    for (let i = 0; i < Math.min(lines.length, windows.length); i++) {
      const suggestion = lines[i].replace(/^\d+\.\s*/, "").trim();
      if (suggestion) suggestions.set(i, suggestion);
    }
  } catch (err) {
    // Gemini failures are non-critical — windows still work without suggestions
    console.warn("Gemini suggestion failed:", err);
  }

  return suggestions;
}
```

**Step 3: Integrate into overlap engine**

In `functions/src/overlap.ts`, after computing ranked windows, call Gemini:

```typescript
import { suggestActivities } from "./gemini";

// After line 126 (ranked computation), before persisting:
const suggestions = await suggestActivities(
  ranked.map((w) => ({
    startMs: w.startMs,
    endMs: w.endMs,
    durationMinutes: Math.floor((w.endMs - w.startMs) / 60_000),
  }))
);

// Update output to include suggestions
const output: OverlapWindowDoc[] = ranked.map((w, i) => ({
  startUtc: w.startMs,
  endUtc: w.endMs,
  durationMinutes: Math.floor((w.endMs - w.startMs) / 60_000),
  score: w.score,
  reasonableBoth: w.reasonableBoth,
  suggestedActivity: suggestions.get(i) || null,
}));
```

**Step 4: Update OverlapWindowDoc interface**

Add `suggestedActivity: string | null` to the `OverlapWindowDoc` interface.

**Step 5: Build and verify**

Run: `cd functions && npm run build`
Expected: Compiles without errors

**Step 6: Commit**

```bash
cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule
git add -A
git commit -m "feat: add Gemini Flash AI suggestions to overlap windows

Call Gemini Flash after overlap computation to generate activity
suggestions for each free window. Suggestions stored in the
overlap windows document. Non-critical — gracefully handles failures.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 11: Pattern Detection Cloud Function

**Files:**
- Create: `functions/src/patterns.ts`
- Modify: `functions/src/index.ts`

**Context:** Weekly analysis of overlap windows to detect recurring mutual free time.

**Step 1: Create pattern detection function**

Create `functions/src/patterns.ts`:

```typescript
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { DateTime } from "luxon";
import { suggestActivities } from "./gemini";

const db = admin.firestore();

interface RecurringWindow {
  dayOfWeek: string;
  startTime: string; // HH:mm
  endTime: string;
  consistency: "strong" | "moderate";
  weeksDetected: number;
  suggestedActivity: string | null;
  confirmed: boolean;
}

// Scheduled to run weekly (Sunday midnight UTC)
export const detectPatterns = functions.pubsub
  .schedule("every sunday 00:00")
  .timeZone("UTC")
  .onRun(async () => {
    const couplesSnap = await db.collection("couples").get();
    for (const coupleDoc of couplesSnap.docs) {
      await analyzePatterns(coupleDoc.id);
    }
  });

// Can also be triggered manually via Firestore write
export const detectPatternsManual = functions.firestore
  .document("couples/{coupleId}/patternRequests/{requestId}")
  .onCreate(async (_snap, context) => {
    await analyzePatterns(context.params.coupleId);
  });

async function analyzePatterns(coupleId: string): Promise<void> {
  const weeksToAnalyze = 4;
  const days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];

  // Collect overlap windows from the last 4 weeks
  // We'll re-fetch the latest windows doc for each week by looking at historical data
  const windowsDoc = await db
    .collection("overlaps")
    .doc(coupleId)
    .collection("windows")
    .doc("latest")
    .get();

  if (!windowsDoc.exists) return;

  const data = windowsDoc.data();
  if (!data?.windows || data.windows.length === 0) return;

  // Group windows by day of week and approximate time
  const dayBuckets: Map<string, Array<{ startHour: number; startMin: number; endHour: number; endMin: number }>> = new Map();

  for (const w of data.windows) {
    const start = DateTime.fromMillis(w.startUtc, { zone: "UTC" });
    const end = DateTime.fromMillis(w.endUtc, { zone: "UTC" });
    if (!start.isValid || !end.isValid) continue;

    const dayName = days[start.weekday - 1]; // luxon: 1=Mon
    if (!dayBuckets.has(dayName)) dayBuckets.set(dayName, []);
    dayBuckets.get(dayName)!.push({
      startHour: start.hour,
      startMin: start.minute,
      endHour: end.hour,
      endMin: end.minute,
    });
  }

  // Find consistent patterns (same day, similar time ±30min)
  const patterns: RecurringWindow[] = [];

  for (const [day, windows] of dayBuckets) {
    // Group by approximate start hour
    const hourGroups: Map<number, typeof windows> = new Map();
    for (const w of windows) {
      const roundedHour = Math.round(w.startHour + w.startMin / 60);
      const key = roundedHour;
      if (!hourGroups.has(key)) hourGroups.set(key, []);
      hourGroups.get(key)!.push(w);
    }

    for (const [_, group] of hourGroups) {
      if (group.length >= 2) { // At least 2 occurrences to suggest a pattern
        const avgStartH = Math.round(group.reduce((sum, w) => sum + w.startHour, 0) / group.length);
        const avgStartM = Math.round(group.reduce((sum, w) => sum + w.startMin, 0) / group.length);
        const avgEndH = Math.round(group.reduce((sum, w) => sum + w.endHour, 0) / group.length);
        const avgEndM = Math.round(group.reduce((sum, w) => sum + w.endMin, 0) / group.length);

        patterns.push({
          dayOfWeek: day,
          startTime: `${String(avgStartH).padStart(2, "0")}:${String(avgStartM).padStart(2, "0")}`,
          endTime: `${String(avgEndH).padStart(2, "0")}:${String(avgEndM).padStart(2, "0")}`,
          consistency: group.length >= 3 ? "strong" : "moderate",
          weeksDetected: group.length,
          suggestedActivity: null,
          confirmed: false,
        });
      }
    }
  }

  if (patterns.length === 0) return;

  // Get Gemini suggestions for patterns
  const suggestions = await suggestActivities(
    patterns.map((p) => {
      const startH = parseInt(p.startTime.split(":")[0]);
      const endH = parseInt(p.endTime.split(":")[0]);
      const duration = (endH - startH) * 60;
      return {
        startMs: Date.now(), // Approximate — used for day detection
        endMs: Date.now() + duration * 60000,
        durationMinutes: duration > 0 ? duration : 60,
      };
    })
  );

  // Apply suggestions
  for (let i = 0; i < patterns.length; i++) {
    patterns[i].suggestedActivity = suggestions.get(i) || null;
  }

  // Write patterns to Firestore
  const batch = db.batch();
  const patternsRef = db.collection("couples").doc(coupleId).collection("recurringWindows");

  // Clear old unconfirmed patterns
  const oldPatterns = await patternsRef.where("confirmed", "==", false).get();
  for (const doc of oldPatterns.docs) {
    batch.delete(doc.ref);
  }

  // Write new patterns
  for (const pattern of patterns) {
    batch.set(patternsRef.doc(), {
      ...pattern,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();
  functions.logger.info(`Detected ${patterns.length} patterns for couple ${coupleId}`);
}
```

**Step 2: Export from index.ts**

In `functions/src/index.ts`, add:
```typescript
export { detectPatterns, detectPatternsManual } from "./patterns";
```

**Step 3: Build**

Run: `cd functions && npm run build`
Expected: Compiles without errors

**Step 4: Commit**

```bash
cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule
git add -A
git commit -m "feat: add pattern detection Cloud Function

Weekly scheduled function analyzes overlap windows to detect recurring
mutual free time. Writes patterns to couples/{id}/recurringWindows
with Gemini-suggested activities. Manual trigger also available.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 12: Pattern Detection Flutter Provider & UI

**Files:**
- Create: `lib/shared/providers/pattern_providers.dart`
- Create: `lib/shared/models/recurring_window.dart`
- Modify: `lib/features/home/home_screen.dart` — add patterns section

**Step 1: Create RecurringWindow model**

Create `lib/shared/models/recurring_window.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class RecurringWindow {
  final String id;
  final String dayOfWeek;
  final String startTime; // HH:mm
  final String endTime;
  final String consistency; // strong, moderate
  final int weeksDetected;
  final String? suggestedActivity;
  final bool confirmed;
  final String? meetLink;

  const RecurringWindow({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.consistency,
    required this.weeksDetected,
    this.suggestedActivity,
    required this.confirmed,
    this.meetLink,
  });

  factory RecurringWindow.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return RecurringWindow(
      id: doc.id,
      dayOfWeek: d['dayOfWeek'] as String,
      startTime: d['startTime'] as String,
      endTime: d['endTime'] as String,
      consistency: d['consistency'] as String? ?? 'moderate',
      weeksDetected: d['weeksDetected'] as int? ?? 0,
      suggestedActivity: d['suggestedActivity'] as String?,
      confirmed: d['confirmed'] as bool? ?? false,
      meetLink: d['meetLink'] as String?,
    );
  }
}
```

**Step 2: Create pattern providers**

Create `lib/shared/providers/pattern_providers.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recurring_window.dart';

final recurringWindowsProvider = StreamProvider.family<List<RecurringWindow>, String>((ref, coupleId) {
  return FirebaseFirestore.instance
      .collection('couples')
      .doc(coupleId)
      .collection('recurringWindows')
      .snapshots()
      .map((snap) => snap.docs.map(RecurringWindow.fromFirestore).toList());
});

final confirmedPatternsProvider = Provider.family<List<RecurringWindow>, String>((ref, coupleId) {
  return ref.watch(recurringWindowsProvider(coupleId)).valueOrNull
      ?.where((w) => w.confirmed).toList() ?? [];
});

final suggestedPatternsProvider = Provider.family<List<RecurringWindow>, String>((ref, coupleId) {
  return ref.watch(recurringWindowsProvider(coupleId)).valueOrNull
      ?.where((w) => !w.confirmed).toList() ?? [];
});
```

**Step 3: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add RecurringWindow model and pattern providers

Firestore-backed providers for streaming recurring window patterns.
Separate providers for confirmed vs suggested patterns.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 13: Update Overlap Model for Suggestions

**Files:**
- Modify: `lib/shared/models/overlap_window.dart`
- Modify: `lib/features/overlap/models/overlap_window_model.dart`

**Context:** Add `suggestedActivity` and `meetLink` fields to overlap window models to match updated Cloud Function output.

**Step 1: Update shared OverlapWindow**

In `lib/shared/models/overlap_window.dart`, add fields:

```dart
final String? suggestedActivity;
final String? meetLink;
```

Update `fromFirestore` to parse these fields. Update constructor.

**Step 2: Update feature OverlapWindow model**

In `lib/features/overlap/models/overlap_window_model.dart`, add same fields.

**Step 3: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add suggestedActivity and meetLink to overlap window models

Support Gemini AI suggestions and Meet link storage in overlap
window documents.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 14: Update Platform Configs

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Modify: `firebase.json`

**Step 1: Update Android manifest**

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

**Step 2: Update iOS Info.plist**

Add notification usage description to `ios/Runner/Info.plist`:
```xml
<key>NSFaceIDUsageDescription</key>
<string>Couple Schedule uses Face ID for secure authentication.</string>
```

**Step 3: Update firebase.json**

Add functions configuration:
```json
{
  "functions": {
    "source": "functions",
    "runtime": "nodejs20"
  }
}
```

Merge with existing flutter platform config.

**Step 4: Commit**

```bash
git add -A
git commit -m "fix: update platform configs for production

Add INTERNET permission to Android manifest.
Add usage descriptions to iOS Info.plist.
Add functions config to firebase.json.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 15: UI Redesign — Color Palette & Theme Update

**Files:**
- Modify: `lib/core/theme/app_theme.dart`

**Context:** Update to the warm modern palette from the design doc.

**Step 1: Update AppColors**

Replace `lib/core/theme/app_theme.dart` color values with the design spec:

```dart
class AppColors {
  AppColors._();

  // Identity
  static const Color rose = Color(0xFFE8849A);
  static const Color roseLight = Color(0xFFFCEEF1);
  static const Color roseDark = Color(0xFFD4627A);

  static const Color partnerBlue = Color(0xFF7AB4E8);
  static const Color partnerBlueLight = Color(0xFFEBF3FC);

  // Overlap
  static const Color overlapStart = Color(0xFFB794D6);
  static const Color overlapEnd = Color(0xFFE8849A);

  // Surfaces
  static const Color background = Color(0xFFFFF8F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFF0E8F5);

  // Semantic
  static const Color success = Color(0xFF7BC47F);
  static const Color warning = Color(0xFFF5C842);
  static const Color error = Color(0xFFE85D5D);

  // Text
  static const Color textPrimary = Color(0xFF2D2D3A);
  static const Color textSecondary = Color(0xFF6B6B80);
  static const Color textTertiary = Color(0xFFA0A0B0);
  static const Color textHint = Color(0xFFB0A3BF);

  // Aliases for backwards compat
  static const Color onSurface = textPrimary;
  static const Color onSurfaceMuted = textSecondary;
  static const Color partnerA = rose;
  static const Color partnerB = partnerBlue;
  static const Color skyBlue = partnerBlue;
  static const Color roseDeep = roseDark;
  static const Color inputFill = Color(0xFFF5F0FA);
  static const Color lavender = Color(0xFFCBA8EA);
  static const Color lavenderLight = Color(0xFFE8D5F5);
  static const Color lavenderDark = Color(0xFFAA7DD0);
  static const Color lavenderDeep = lavenderDark;

  // Gradients
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB794D6), Color(0xFFE8849A)],
  );

  static const LinearGradient overlapGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0x60B794D6), Color(0x60E8849A)],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF0EB), Color(0xFFFFF8F5)],
  );
}
```

**Step 2: Update AppTheme**

Update font family to null (use system fonts), card border radius to 16, scaffold background to `AppColors.background`.

**Step 3: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 4: Commit**

```bash
git add lib/core/theme/app_theme.dart
git commit -m "feat: update to warm modern color palette and theme

New rose (#E8849A), partner blue (#7AB4E8), warm cream background
(#FFF8F5). System fonts instead of SF Pro Display. Updated card
radius to 16px.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 16: UI Redesign — Home Screen

**Files:**
- Modify: `lib/features/home/home_screen.dart`
- Modify: `lib/features/home/widgets/timezone_clock.dart`
- Modify: `lib/features/home/widgets/next_window_card.dart`
- Modify: `lib/features/home/widgets/daily_timeline.dart`

**Context:** Redesign home screen with timezone awareness (same vs different TZ), hero card, patterns section, daily timeline. All backed by Firestore providers.

**Step 1: Update HomeScreen to use Riverpod providers**

Make `HomeScreen` a `ConsumerWidget`. Read from:
- `currentUserProvider` for user info
- `currentCoupleProvider` for couple data
- `topOverlapWindowProvider` for next free window
- `suggestedPatternsProvider` for pattern cards
- `coupleBlocksProvider` for daily timeline

**Step 2: Add same-timezone detection**

Read both users' timezones. If they match, show single clock. If different, show dual clocks.

**Step 3: Add patterns section**

Below the hero card, show "Patterns" section with cards for detected recurring windows. Each card shows day, time, consistency badge, suggested activity, and "Lock In" button.

**Step 4: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: redesign home screen with patterns and timezone awareness

Firestore-backed home screen with timezone clock(s), hero window card,
patterns section, daily timeline. Same-timezone couples see single
clock. Different-timezone couples see dual clocks.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 17: UI Redesign — Free Windows / Overlap Screen

**Files:**
- Modify: `lib/features/overlap/overlap_screen.dart`
- Modify: `lib/features/overlap/widgets/window_card.dart`

**Context:** Add "Schedule Call" button, Gemini suggestion chips, duration filter. Wire to real providers, remove `AppColors.success` reference (now defined).

**Step 1: Update OverlapScreen**

- Read from `overlapWindowsProvider` (shared, now pointing to correct Firestore path)
- Add minimum duration filter slider
- Sort by score

**Step 2: Update WindowCard**

- Show time in both timezones (or single if same TZ)
- Duration badge
- Gemini suggestion chip
- "Schedule Call" button with Meet icon → opens confirmation bottom sheet

**Step 3: Create ScheduleCallSheet widget**

Bottom sheet showing:
- Time in both timezones
- Duration
- Suggested activity as editable title
- "Create Google Meet Event" button
- On tap → writes `SchedulingRequest` doc + calls `GoogleCalendarService.createMeetEvent`

**Step 4: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: redesign overlap screen with Meet scheduling and AI suggestions

Window cards show Gemini activity suggestions, dual timezone display,
and Schedule Call button. Confirmation sheet creates Google Calendar
events with Meet links.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 18: UI Redesign — Calendar Screen

**Files:**
- Modify: `lib/features/calendar/calendar_screen.dart`
- Modify: `lib/features/calendar/widgets/week_view.dart`

**Context:** Full week view with partner blocks, overlap highlights, calendar connection status.

**Step 1: Update CalendarScreen**

- `ConsumerWidget` reading from `coupleBlocksProvider`
- Week navigation with swipe
- Calendar connection banners (Google connected?, Microsoft connected?)
- "Sync Now" button

**Step 2: Update WeekView colors**

- User blocks in rose
- Partner blocks in partner blue
- Overlap zones with gradient glow
- Tap block for detail sheet

**Step 3: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: redesign calendar screen with week view and connection status

Color-coded blocks (rose = you, blue = partner), overlap gradient
highlights, swipe week navigation, calendar connection banners.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 19: UI Redesign — Settings Screen

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`

**Context:** Full settings with calendar connections (Google + Microsoft status), default calendar picker, notifications, privacy, timezone, account.

**Step 1: Rewrite SettingsScreen as ConsumerWidget**

Sections:
1. **Calendar Connections** — Google (connected/disconnect), Microsoft (connect/disconnect), with last sync timestamps
2. **Notifications** — new window alerts, daily digest, quiet hours
3. **Privacy** — show event titles toggle
4. **Scheduling** — minimum slot duration, default calendar for couple events
5. **Timezone** — current timezone with override option
6. **Account** — sign out, unpair

**Step 2: Wire to real providers**

Use `currentUserProvider`, `coupleSettingsProvider`, notification providers, calendar connection providers.

**Step 3: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: redesign settings screen with calendar connections and preferences

Full settings: Google/Microsoft connection management, notification
preferences, privacy controls, scheduling settings, timezone override.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 20: Pairing Screen — Remove Demo UIDs

**Files:**
- Modify: `lib/features/pairing/pairing_screen.dart`

**Step 1: Replace demo UIDs with real auth**

Read from `currentUserProvider` instead of hardcoded `_demoUid`.

**Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 3: Commit**

```bash
git add -A
git commit -m "fix: replace hardcoded demo UIDs in pairing screen

Read from currentUserProvider for real auth integration.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 21: Final Integration Verification

**Step 1: Run full analysis**

Run: `flutter analyze`
Expected: No errors

**Step 2: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 3: Build Cloud Functions**

Run: `cd functions && npm run build`
Expected: Compiles without errors

**Step 4: Verify app builds**

Run: `cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule && flutter build apk --debug`
Expected: Builds successfully

**Step 5: Final commit**

```bash
git add -A
git commit -m "chore: final integration verification — all checks pass

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```
