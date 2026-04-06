# Couple Schedule v1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter + Firebase app that helps couples find mutual free time across timezones, with server-side overlap computation and push notifications.

**Architecture:** Flutter frontend (Riverpod + go_router) backed by Firebase (Auth, Firestore, Cloud Functions v2, FCM). Cloud Functions compute overlap windows when blocks change. All times stored UTC. Google Calendar freebusy API for calendar sync.

**Tech Stack:** Flutter 3.41.4 / Dart 3.11.1, Firebase, Riverpod, go_router, Node.js 20+ (Cloud Functions), TypeScript, Luxon, rrule

**Spec:** `docs/superpowers/specs/2026-04-06-couple-schedule-v1-rebuild-design.md`

---

## File Map

### Infrastructure
- `pubspec.yaml` — Flutter dependencies
- `firebase.json` — Firebase project config (Firestore, Functions, Hosting)
- `firestore.rules` — Security rules
- `firestore.indexes.json` — Composite indexes
- `.firebaserc` — Project alias (nexion-ai-prod)

### Core Models (`lib/core/models/`)
- `user_model.dart` — UserModel with Firestore serialization
- `couple_model.dart` — CoupleModel
- `invite_model.dart` — InviteModel
- `time_block_model.dart` — TimeBlock + enums (BlockType, BlockSource, BlockCategory, BlockVisibility)
- `overlap_result_model.dart` — OverlapWindow + OverlapResult
- `models.dart` — Barrel export

### Core Theme (`lib/core/theme/`)
- `app_theme.dart` — Material 3 theme + AppColors

### Core Utils (`lib/core/utils/`)
- `tz_helper.dart` — Timezone conversion helpers

### Services (`lib/services/`)
- `auth_service.dart` — Firebase Auth wrapper (Google + Apple sign-in)
- `firestore_service.dart` — Firestore CRUD for all collections
- `calendar_service.dart` — Google Calendar freebusy sync
- `notification_service.dart` — FCM token registration + local notification setup

### Providers (`lib/services/providers/`)
- `auth_providers.dart` — authStateProvider, currentUserProvider
- `couple_providers.dart` — coupleProvider, partnerProvider
- `block_providers.dart` — blocksProvider, myBlocksProvider, partnerBlocksProvider
- `overlap_providers.dart` — overlapProvider
- `calendar_providers.dart` — calendarSyncProvider

### Router (`lib/core/router/`)
- `app_router.dart` — GoRouter with redirect guards

### App Entry (`lib/`)
- `main.dart` — Bootstrap (Firebase init, tz init, ProviderScope)
- `app.dart` — MaterialApp.router with theme

### Feature Screens (`lib/features/`)
- `auth/auth_screen.dart`
- `onboarding/timezone_setup_screen.dart`
- `onboarding/routine_wizard_screen.dart`
- `pairing/pairing_screen.dart`
- `home/home_screen.dart`
- `home/widgets/timezone_clocks.dart`
- `home/widgets/next_window_card.dart`
- `calendar/week_view_screen.dart`
- `overlap/overlap_screen.dart`
- `blocks/block_management_screen.dart`
- `blocks/block_form_screen.dart`
- `settings/settings_screen.dart`

### Cloud Functions (`functions/`)
- `package.json` — Node.js dependencies
- `tsconfig.json` — TypeScript config
- `src/index.ts` — Export all functions
- `src/onBlockWrite.ts` — Overlap computation on block change
- `src/onOverlapWrite.ts` — FCM push on new overlaps
- `src/onInviteCreate.ts` — Deep link generation
- `src/redeemInvite.ts` — Callable: atomic pairing
- `src/unpairCouple.ts` — Callable: atomic unpairing
- `src/cleanupInvites.ts` — Scheduled: expire stale invites
- `src/utils/overlap.ts` — Interval math (merge, invert, intersect, score)
- `src/utils/recurrence.ts` — RRULE expansion wrapper

### Tests
- `test/core/models/user_model_test.dart`
- `test/core/models/time_block_model_test.dart`
- `test/core/models/overlap_result_model_test.dart`
- `test/core/models/couple_model_test.dart`
- `test/core/models/invite_model_test.dart`
- `test/core/utils/tz_helper_test.dart`
- `functions/src/__tests__/overlap.test.ts`
- `functions/src/__tests__/recurrence.test.ts`
- `functions/src/__tests__/onBlockWrite.test.ts`

---

## Task Dependency Graph

```
Task 1 (Firebase setup) ──→ Task 2 (Flutter scaffold)
Task 2 ──→ Task 3 (Models + Tests)
Task 3 ──→ Task 4 (Firestore service)
Task 3 ──→ Task 5 (Security rules + indexes)
Task 4 ──→ Task 6 (Auth service + providers)
Task 6 ──→ Task 7 (Router + App shell)
Task 7 ──→ Task 8 (Auth screen)
Task 8 ──→ Task 9 (Timezone setup screen)
Task 9 ──→ Task 10 (Pairing service + screen)
Task 10 ──→ Task 11 (Block service + form)
Task 11 ──→ Task 12 (Block management screen)
Task 11 ──→ Task 13 (Routine wizard)
Task 4 ──→ Task 14 (Cloud Functions scaffold)
Task 14 ──→ Task 15 (Overlap engine — interval math)
Task 15 ──→ Task 16 (onBlockWrite function)
Task 16 ──→ Task 17 (onOverlapWrite — FCM push)
Task 14 ──→ Task 18 (redeemInvite + onInviteCreate + cleanup)
Task 11 ──→ Task 19 (Google Calendar sync)
Task 12 + Task 16 ──→ Task 20 (Home screen)
Task 20 ──→ Task 21 (Calendar week view)
Task 20 ──→ Task 22 (Overlap screen)
Task 22 ──→ Task 23 (Settings screen)
Task 23 ──→ Task 24 (Notification service + FCM)
Task 24 ──→ Task 25 (Deploy + smoke test)
```

---

## Phase 1: Infrastructure & Foundation

### Task 1: Firebase Project Setup

**Files:**
- Create: `firebase.json`
- Create: `.firebaserc`

**Prerequisites:** Firebase CLI and FlutterFire CLI must be installed. GCloud project `nexion-ai-prod` must be active.

- [ ] **Step 1: Install Firebase CLI**

Run:
```bash
npm install -g firebase-tools
```

- [ ] **Step 2: Login to Firebase**

Run:
```bash
firebase login
```

- [ ] **Step 3: Enable Firebase on the GCloud project**

Run:
```bash
firebase projects:addfirebase nexion-ai-prod
```

- [ ] **Step 4: Initialize Firebase in the repo**

Run interactively — select Firestore, Functions (TypeScript), Hosting, and Emulators:
```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/couple-sync
firebase init
```

Select these options:
- Firestore: yes (creates `firestore.rules`, `firestore.indexes.json`)
- Functions: yes, TypeScript, ESLint yes, install deps yes
- Hosting: yes (for deep link redirect page), public dir: `public`, SPA: no
- Emulators: Auth, Firestore, Functions, Pub/Sub

This creates `firebase.json`, `.firebaserc`, `functions/` directory, `firestore.rules`, `firestore.indexes.json`.

- [ ] **Step 5: Enable required Firebase services**

Run each command:
```bash
firebase firestore:databases:create --location=us-central1 --project=nexion-ai-prod
gcloud services enable identitytoolkit.googleapis.com --project=nexion-ai-prod
gcloud services enable fcm.googleapis.com --project=nexion-ai-prod
gcloud services enable cloudfunctions.googleapis.com --project=nexion-ai-prod
gcloud services enable cloudscheduler.googleapis.com --project=nexion-ai-prod
gcloud services enable calendar-json.googleapis.com --project=nexion-ai-prod
```

- [ ] **Step 6: Install FlutterFire CLI and configure**

Run:
```bash
dart pub global activate flutterfire_cli
```

- [ ] **Step 7: Verify firebase.json exists and .firebaserc points to nexion-ai-prod**

Run:
```bash
cat firebase.json
cat .firebaserc
```

Expected: `.firebaserc` contains `"default": "nexion-ai-prod"`

- [ ] **Step 8: Commit**

```bash
git add firebase.json .firebaserc firestore.rules firestore.indexes.json functions/ .gitignore
git commit -m "chore: initialize Firebase project with Firestore, Functions, and Hosting"
```

---

### Task 2: Flutter Project Scaffold

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/main.dart`
- Create: `lib/app.dart`
- Create: `lib/core/theme/app_theme.dart`
- Create: `lib/core/models/models.dart`
- Create: `analysis_options.yaml`

- [ ] **Step 1: Create Flutter project (if not already a Flutter project)**

Run:
```bash
flutter create --org com.nexiontech --project-name couple_schedule .
```

If this fails because the directory isn't empty, that's fine — we'll create files manually.

- [ ] **Step 2: Generate Firebase config**

Run:
```bash
flutterfire configure --project=nexion-ai-prod --platforms=ios,android
```

This creates `lib/firebase_options.dart` and updates platform-specific config files.

- [ ] **Step 3: Write pubspec.yaml**

```yaml
name: couple_schedule
description: Find mutual free time with your partner across timezones.
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.11.0

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  intl: ^0.20.2
  go_router: ^15.1.2

  # Firebase
  firebase_core: ^3.12.1
  firebase_auth: ^5.6.1
  firebase_messaging: ^15.2.4
  cloud_firestore: ^5.6.5
  cloud_functions: ^5.3.4

  # Google / Apple Sign-In
  google_sign_in: ^6.2.2
  sign_in_with_apple: ^6.1.4
  googleapis: ^14.0.0
  http: ^1.3.0

  # State management
  flutter_riverpod: ^2.6.1

  # Persistence
  shared_preferences: ^2.5.3
  uuid: ^4.5.1
  timezone: ^0.10.0

  # Fonts
  google_fonts: ^6.2.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

- [ ] **Step 4: Write lib/main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'firebase_options.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  tz.initializeTimeZones();
  runApp(const ProviderScope(child: CoupleScheduleApp()));
}
```

- [ ] **Step 5: Write lib/app.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';

class CoupleScheduleApp extends ConsumerWidget {
  const CoupleScheduleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Couple Schedule',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const Scaffold(
        body: Center(child: Text('Couple Schedule')),
      ),
    );
  }
}
```

- [ ] **Step 6: Write lib/core/theme/app_theme.dart**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF6C5CE7);
  static const secondary = Color(0xFFA29BFE);
  static const surface = Color(0xFFF8F9FA);
  static const error = Color(0xFFE17055);
  static const success = Color(0xFF00B894);
  static const textPrimary = Color(0xFF2D3436);
  static const textSecondary = Color(0xFF636E72);
  static const cardBg = Colors.white;
  static const yourBlock = Color(0xFF74B9FF);
  static const partnerBlock = Color(0xFFFF7675);
  static const overlapHighlight = Color(0xFF55EFC4);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: AppColors.primary,
      brightness: Brightness.light,
      textTheme: GoogleFonts.interTextTheme(),
      cardTheme: const CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: AppColors.primary,
      brightness: Brightness.dark,
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
      ),
    );
  }
}
```

- [ ] **Step 7: Create empty barrel file lib/core/models/models.dart**

```dart
// Barrel export for all models — populated in Task 3
```

- [ ] **Step 8: Run flutter analyze and verify build**

Run:
```bash
flutter pub get && flutter analyze
```

Expected: No analysis errors. Warnings about unused imports are OK for now.

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml lib/ analysis_options.yaml android/ ios/ pubspec.lock .gitignore
git commit -m "feat: Flutter project scaffold with Firebase config and theme"
```

---

## Phase 2: Data Models & Tests

### Task 3: Core Data Models

**Files:**
- Create: `lib/core/models/user_model.dart`
- Create: `lib/core/models/couple_model.dart`
- Create: `lib/core/models/invite_model.dart`
- Create: `lib/core/models/time_block_model.dart`
- Create: `lib/core/models/overlap_result_model.dart`
- Modify: `lib/core/models/models.dart`
- Create: `test/core/models/user_model_test.dart`
- Create: `test/core/models/couple_model_test.dart`
- Create: `test/core/models/invite_model_test.dart`
- Create: `test/core/models/time_block_model_test.dart`
- Create: `test/core/models/overlap_result_model_test.dart`

- [ ] **Step 1: Write UserModel tests**

```dart
// test/core/models/user_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/core/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('fromMap creates model with all fields', () {
      final map = {
        'email': 'test@example.com',
        'displayName': 'Test User',
        'photoUrl': 'https://example.com/photo.jpg',
        'timezone': 'America/New_York',
        'coupleId': 'couple123',
        'fcmTokens': ['token1', 'token2'],
        'createdAt': 1700000000000,
      };
      final user = UserModel.fromMap('uid123', map);

      expect(user.uid, 'uid123');
      expect(user.email, 'test@example.com');
      expect(user.displayName, 'Test User');
      expect(user.photoUrl, 'https://example.com/photo.jpg');
      expect(user.timezone, 'America/New_York');
      expect(user.coupleId, 'couple123');
      expect(user.fcmTokens, ['token1', 'token2']);
    });

    test('fromMap handles missing optional fields', () {
      final map = {
        'email': 'a@b.com',
        'displayName': 'A',
        'createdAt': 1700000000000,
      };
      final user = UserModel.fromMap('uid1', map);

      expect(user.photoUrl, isNull);
      expect(user.coupleId, isNull);
      expect(user.timezone, 'UTC');
      expect(user.fcmTokens, isEmpty);
    });

    test('toMap serializes correctly without uid', () {
      final user = UserModel(
        uid: 'uid123',
        email: 'test@example.com',
        displayName: 'Test User',
        timezone: 'America/New_York',
        fcmTokens: ['token1'],
        createdAt: DateTime.utc(2024, 1, 1),
      );
      final map = user.toMap();

      expect(map['email'], 'test@example.com');
      expect(map['timezone'], 'America/New_York');
      expect(map['fcmTokens'], ['token1']);
      expect(map.containsKey('uid'), false);
    });

    test('copyWith creates modified copy', () {
      final user = UserModel(
        uid: 'uid1',
        email: 'a@b.com',
        displayName: 'A',
        timezone: 'UTC',
        fcmTokens: [],
        createdAt: DateTime.utc(2024),
      );
      final updated = user.copyWith(timezone: 'Asia/Tokyo', coupleId: 'c1');

      expect(updated.timezone, 'Asia/Tokyo');
      expect(updated.coupleId, 'c1');
      expect(updated.email, 'a@b.com');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/models/user_model_test.dart`
Expected: FAIL — `user_model.dart` doesn't exist yet

- [ ] **Step 3: Write UserModel**

```dart
// lib/core/models/user_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String timezone;
  final String? coupleId;
  final List<String> fcmTokens;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.timezone,
    this.coupleId,
    this.fcmTokens = const [],
    required this.createdAt,
  });

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) {
    return UserModel(
      uid: uid,
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      timezone: map['timezone'] as String? ?? 'UTC',
      coupleId: map['coupleId'] as String?,
      fcmTokens: List<String>.from(map['fcmTokens'] ?? []),
      createdAt: _parseTimestamp(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'timezone': timezone,
      'coupleId': coupleId,
      'fcmTokens': fcmTokens,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  UserModel copyWith({
    String? email,
    String? displayName,
    String? photoUrl,
    String? timezone,
    String? coupleId,
    List<String>? fcmTokens,
  }) {
    return UserModel(
      uid: uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      timezone: timezone ?? this.timezone,
      coupleId: coupleId ?? this.coupleId,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      createdAt: createdAt,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now().toUtc();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/models/user_model_test.dart`
Expected: All 4 tests PASS

- [ ] **Step 5: Write TimeBlock enums + model tests**

```dart
// test/core/models/time_block_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/core/models/time_block_model.dart';

void main() {
  group('TimeBlock', () {
    final now = DateTime.utc(2026, 4, 6, 10, 0);
    final later = DateTime.utc(2026, 4, 6, 11, 0);

    test('fromMap creates model with all fields', () {
      final map = {
        'userId': 'uid1',
        'title': 'Work',
        'type': 'busy',
        'category': 'work',
        'startUtc': now.millisecondsSinceEpoch,
        'endUtc': later.millisecondsSinceEpoch,
        'timezone': 'America/New_York',
        'recurrenceRule': 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
        'source': 'manual',
        'visibility': 'bothPartners',
        'createdAt': now.millisecondsSinceEpoch,
      };
      final block = TimeBlock.fromMap('block1', map);

      expect(block.id, 'block1');
      expect(block.userId, 'uid1');
      expect(block.title, 'Work');
      expect(block.type, BlockType.busy);
      expect(block.category, BlockCategory.work);
      expect(block.startUtc, now);
      expect(block.endUtc, later);
      expect(block.recurrenceRule, 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR');
      expect(block.source, BlockSource.manual);
      expect(block.visibility, BlockVisibility.bothPartners);
    });

    test('toMap serializes enums as strings without id', () {
      final block = TimeBlock(
        id: 'b1',
        userId: 'u1',
        title: 'Gym',
        type: BlockType.busy,
        category: BlockCategory.exercise,
        startUtc: now,
        endUtc: later,
        timezone: 'UTC',
        source: BlockSource.manual,
        visibility: BlockVisibility.bothPartners,
        createdAt: now,
      );
      final map = block.toMap();

      expect(map['type'], 'busy');
      expect(map['category'], 'exercise');
      expect(map['source'], 'manual');
      expect(map['visibility'], 'bothPartners');
      expect(map['startUtc'], now.millisecondsSinceEpoch);
      expect(map.containsKey('id'), false);
    });

    test('duration returns correct difference', () {
      final block = TimeBlock(
        id: 'b1',
        userId: 'u1',
        title: 'Test',
        type: BlockType.busy,
        category: BlockCategory.other,
        startUtc: now,
        endUtc: later,
        timezone: 'UTC',
        source: BlockSource.manual,
        visibility: BlockVisibility.bothPartners,
        createdAt: now,
      );
      expect(block.duration, const Duration(hours: 1));
    });

    test('fromMap defaults to safe enum values for unknown strings', () {
      final map = {
        'userId': 'u1',
        'title': 'X',
        'type': 'unknown_type',
        'category': 'unknown_cat',
        'startUtc': now.millisecondsSinceEpoch,
        'endUtc': later.millisecondsSinceEpoch,
        'timezone': 'UTC',
        'source': 'unknown_src',
        'visibility': 'unknown_vis',
        'createdAt': now.millisecondsSinceEpoch,
      };
      final block = TimeBlock.fromMap('b1', map);

      expect(block.type, BlockType.busy);
      expect(block.category, BlockCategory.other);
      expect(block.source, BlockSource.manual);
      expect(block.visibility, BlockVisibility.bothPartners);
    });

    test('copyWith creates modified copy', () {
      final block = TimeBlock(
        id: 'b1',
        userId: 'u1',
        title: 'Old',
        type: BlockType.busy,
        category: BlockCategory.work,
        startUtc: now,
        endUtc: later,
        timezone: 'UTC',
        source: BlockSource.manual,
        visibility: BlockVisibility.bothPartners,
        createdAt: now,
      );
      final updated = block.copyWith(title: 'New', category: BlockCategory.exercise);

      expect(updated.title, 'New');
      expect(updated.category, BlockCategory.exercise);
      expect(updated.userId, 'u1');
    });
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/core/models/time_block_model_test.dart`
Expected: FAIL

- [ ] **Step 7: Write TimeBlock model**

```dart
// lib/core/models/time_block_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum BlockType { busy, free, tentative }

enum BlockSource { google, manual }

enum BlockCategory { work, study, commute, exercise, social, meals, sleep, personal, other }

enum BlockVisibility { bothPartners, onlyMe }

class TimeBlock {
  final String id;
  final String userId;
  final String title;
  final BlockType type;
  final BlockCategory category;
  final DateTime startUtc;
  final DateTime endUtc;
  final String timezone;
  final String? recurrenceRule;
  final BlockSource source;
  final BlockVisibility visibility;
  final DateTime createdAt;

  TimeBlock({
    required this.id,
    required this.userId,
    required this.title,
    required this.type,
    required this.category,
    required this.startUtc,
    required this.endUtc,
    required this.timezone,
    this.recurrenceRule,
    required this.source,
    required this.visibility,
    required this.createdAt,
  });

  Duration get duration => endUtc.difference(startUtc);

  factory TimeBlock.fromMap(String id, Map<String, dynamic> map) {
    return TimeBlock(
      id: id,
      userId: map['userId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      type: _parseEnum(BlockType.values, map['type'], BlockType.busy),
      category: _parseEnum(BlockCategory.values, map['category'], BlockCategory.other),
      startUtc: DateTime.fromMillisecondsSinceEpoch(map['startUtc'] as int),
      endUtc: DateTime.fromMillisecondsSinceEpoch(map['endUtc'] as int),
      timezone: map['timezone'] as String? ?? 'UTC',
      recurrenceRule: map['recurrenceRule'] as String?,
      source: _parseEnum(BlockSource.values, map['source'], BlockSource.manual),
      visibility: _parseEnum(BlockVisibility.values, map['visibility'], BlockVisibility.bothPartners),
      createdAt: _parseTimestamp(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'type': type.name,
      'category': category.name,
      'startUtc': startUtc.millisecondsSinceEpoch,
      'endUtc': endUtc.millisecondsSinceEpoch,
      'timezone': timezone,
      'recurrenceRule': recurrenceRule,
      'source': source.name,
      'visibility': visibility.name,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  TimeBlock copyWith({
    String? title,
    BlockType? type,
    BlockCategory? category,
    DateTime? startUtc,
    DateTime? endUtc,
    String? recurrenceRule,
    BlockVisibility? visibility,
  }) {
    return TimeBlock(
      id: id,
      userId: userId,
      title: title ?? this.title,
      type: type ?? this.type,
      category: category ?? this.category,
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      timezone: timezone,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      source: source,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt,
    );
  }

  static T _parseEnum<T extends Enum>(List<T> values, dynamic value, T fallback) {
    if (value is String) {
      return values.where((e) => e.name == value).firstOrNull ?? fallback;
    }
    return fallback;
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now().toUtc();
  }
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/core/models/time_block_model_test.dart`
Expected: All 5 tests PASS

- [ ] **Step 9: Write OverlapResult model tests**

```dart
// test/core/models/overlap_result_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/core/models/overlap_result_model.dart';

void main() {
  group('OverlapWindow', () {
    test('fromMap creates window with all fields', () {
      final map = {
        'startUtc': 1700000000000,
        'endUtc': 1700003600000,
        'durationMinutes': 60,
        'score': 45.5,
        'reasonableBoth': true,
      };
      final window = OverlapWindow.fromMap(map);

      expect(window.startUtc.millisecondsSinceEpoch, 1700000000000);
      expect(window.endUtc.millisecondsSinceEpoch, 1700003600000);
      expect(window.durationMinutes, 60);
      expect(window.score, 45.5);
      expect(window.reasonableBoth, true);
    });

    test('toMap serializes correctly', () {
      final window = OverlapWindow(
        startUtc: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        endUtc: DateTime.fromMillisecondsSinceEpoch(1700003600000),
        durationMinutes: 60,
        score: 45.5,
        reasonableBoth: true,
      );
      final map = window.toMap();

      expect(map['startUtc'], 1700000000000);
      expect(map['durationMinutes'], 60);
      expect(map['score'], 45.5);
    });
  });

  group('OverlapResult', () {
    test('fromMap creates result with windows list', () {
      final map = {
        'windows': [
          {
            'startUtc': 1700000000000,
            'endUtc': 1700003600000,
            'durationMinutes': 60,
            'score': 45.5,
            'reasonableBoth': true,
          },
        ],
        'computedAt': 1700000000000,
        'blockHashA': 'hashA',
        'blockHashB': 'hashB',
      };
      final result = OverlapResult.fromMap(map);

      expect(result.windows.length, 1);
      expect(result.windows.first.score, 45.5);
      expect(result.blockHashA, 'hashA');
    });

    test('fromMap handles empty windows', () {
      final map = {
        'windows': [],
        'computedAt': 1700000000000,
        'blockHashA': '',
        'blockHashB': '',
      };
      final result = OverlapResult.fromMap(map);
      expect(result.windows, isEmpty);
    });
  });
}
```

- [ ] **Step 10: Run test to verify it fails**

Run: `flutter test test/core/models/overlap_result_model_test.dart`
Expected: FAIL

- [ ] **Step 11: Write OverlapResult model**

```dart
// lib/core/models/overlap_result_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class OverlapWindow {
  final DateTime startUtc;
  final DateTime endUtc;
  final int durationMinutes;
  final double score;
  final bool reasonableBoth;

  OverlapWindow({
    required this.startUtc,
    required this.endUtc,
    required this.durationMinutes,
    required this.score,
    required this.reasonableBoth,
  });

  factory OverlapWindow.fromMap(Map<String, dynamic> map) {
    return OverlapWindow(
      startUtc: DateTime.fromMillisecondsSinceEpoch(map['startUtc'] as int),
      endUtc: DateTime.fromMillisecondsSinceEpoch(map['endUtc'] as int),
      durationMinutes: map['durationMinutes'] as int? ?? 0,
      score: (map['score'] as num?)?.toDouble() ?? 0.0,
      reasonableBoth: map['reasonableBoth'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'startUtc': startUtc.millisecondsSinceEpoch,
      'endUtc': endUtc.millisecondsSinceEpoch,
      'durationMinutes': durationMinutes,
      'score': score,
      'reasonableBoth': reasonableBoth,
    };
  }
}

class OverlapResult {
  final List<OverlapWindow> windows;
  final DateTime computedAt;
  final String blockHashA;
  final String blockHashB;

  OverlapResult({
    required this.windows,
    required this.computedAt,
    required this.blockHashA,
    required this.blockHashB,
  });

  factory OverlapResult.fromMap(Map<String, dynamic> map) {
    final windowsList = (map['windows'] as List<dynamic>?) ?? [];
    return OverlapResult(
      windows: windowsList
          .map((w) => OverlapWindow.fromMap(Map<String, dynamic>.from(w)))
          .toList(),
      computedAt: _parseTimestamp(map['computedAt']),
      blockHashA: map['blockHashA'] as String? ?? '',
      blockHashB: map['blockHashB'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'windows': windows.map((w) => w.toMap()).toList(),
      'computedAt': Timestamp.fromDate(computedAt),
      'blockHashA': blockHashA,
      'blockHashB': blockHashB,
    };
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now().toUtc();
  }
}
```

- [ ] **Step 12: Run test to verify it passes**

Run: `flutter test test/core/models/overlap_result_model_test.dart`
Expected: All 4 tests PASS

- [ ] **Step 13: Write CoupleModel tests**

```dart
// test/core/models/couple_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/core/models/couple_model.dart';

void main() {
  group('CoupleModel', () {
    test('fromMap creates model', () {
      final map = {
        'userAUid': 'uid1',
        'userBUid': 'uid2',
        'status': 'active',
        'pairedAt': 1700000000000,
        'unpairHistory': [],
        'createdAt': 1700000000000,
      };
      final couple = CoupleModel.fromMap('c1', map);

      expect(couple.id, 'c1');
      expect(couple.userAUid, 'uid1');
      expect(couple.userBUid, 'uid2');
      expect(couple.status, 'active');
      expect(couple.unpairHistory, isEmpty);
    });

    test('partnerUid returns the other user', () {
      final couple = CoupleModel(
        id: 'c1',
        userAUid: 'uid1',
        userBUid: 'uid2',
        status: 'active',
        pairedAt: DateTime.utc(2024),
        unpairHistory: [],
        createdAt: DateTime.utc(2024),
      );
      expect(couple.partnerUid('uid1'), 'uid2');
      expect(couple.partnerUid('uid2'), 'uid1');
    });

    test('toMap serializes without id', () {
      final couple = CoupleModel(
        id: 'c1',
        userAUid: 'uid1',
        userBUid: 'uid2',
        status: 'active',
        pairedAt: DateTime.utc(2024),
        unpairHistory: [],
        createdAt: DateTime.utc(2024),
      );
      final map = couple.toMap();

      expect(map['userAUid'], 'uid1');
      expect(map.containsKey('id'), false);
    });
  });
}
```

- [ ] **Step 14: Run test to verify it fails**

Run: `flutter test test/core/models/couple_model_test.dart`
Expected: FAIL

- [ ] **Step 15: Write CoupleModel**

```dart
// lib/core/models/couple_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class CoupleModel {
  final String id;
  final String userAUid;
  final String userBUid;
  final String status;
  final DateTime pairedAt;
  final List<Map<String, dynamic>> unpairHistory;
  final DateTime createdAt;

  CoupleModel({
    required this.id,
    required this.userAUid,
    required this.userBUid,
    required this.status,
    required this.pairedAt,
    required this.unpairHistory,
    required this.createdAt,
  });

  String partnerUid(String myUid) => myUid == userAUid ? userBUid : userAUid;

  bool isMember(String uid) => uid == userAUid || uid == userBUid;

  factory CoupleModel.fromMap(String id, Map<String, dynamic> map) {
    return CoupleModel(
      id: id,
      userAUid: map['userAUid'] as String? ?? '',
      userBUid: map['userBUid'] as String? ?? '',
      status: map['status'] as String? ?? 'active',
      pairedAt: _parseTimestamp(map['pairedAt']),
      unpairHistory: List<Map<String, dynamic>>.from(map['unpairHistory'] ?? []),
      createdAt: _parseTimestamp(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userAUid': userAUid,
      'userBUid': userBUid,
      'status': status,
      'pairedAt': Timestamp.fromDate(pairedAt),
      'unpairHistory': unpairHistory,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now().toUtc();
  }
}
```

- [ ] **Step 16: Run test to verify it passes**

Run: `flutter test test/core/models/couple_model_test.dart`
Expected: All 3 tests PASS

- [ ] **Step 17: Write InviteModel tests**

```dart
// test/core/models/invite_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/core/models/invite_model.dart';

void main() {
  group('InviteModel', () {
    test('fromMap creates model', () {
      final map = {
        'code': 'ABC123',
        'createdByUid': 'uid1',
        'coupleId': null,
        'expiresAt': 1700100000000,
        'status': 'pending',
        'deepLinkUrl': null,
      };
      final invite = InviteModel.fromMap(map);

      expect(invite.code, 'ABC123');
      expect(invite.createdByUid, 'uid1');
      expect(invite.status, 'pending');
      expect(invite.coupleId, isNull);
    });

    test('isExpired returns true for past dates', () {
      final invite = InviteModel(
        code: 'ABC123',
        createdByUid: 'uid1',
        expiresAt: DateTime.utc(2020, 1, 1),
        status: 'pending',
      );
      expect(invite.isExpired, true);
    });

    test('isExpired returns false for future dates', () {
      final invite = InviteModel(
        code: 'ABC123',
        createdByUid: 'uid1',
        expiresAt: DateTime.utc(2030, 1, 1),
        status: 'pending',
      );
      expect(invite.isExpired, false);
    });

    test('toMap serializes correctly', () {
      final invite = InviteModel(
        code: 'ABC123',
        createdByUid: 'uid1',
        expiresAt: DateTime.utc(2024, 6, 1),
        status: 'pending',
      );
      final map = invite.toMap();

      expect(map['code'], 'ABC123');
      expect(map['status'], 'pending');
    });
  });
}
```

- [ ] **Step 18: Run test to verify it fails**

Run: `flutter test test/core/models/invite_model_test.dart`
Expected: FAIL

- [ ] **Step 19: Write InviteModel**

```dart
// lib/core/models/invite_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class InviteModel {
  final String code;
  final String createdByUid;
  final String? coupleId;
  final DateTime expiresAt;
  final String status;
  final String? deepLinkUrl;

  InviteModel({
    required this.code,
    required this.createdByUid,
    this.coupleId,
    required this.expiresAt,
    required this.status,
    this.deepLinkUrl,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
  bool get isPending => status == 'pending' && !isExpired;

  factory InviteModel.fromMap(Map<String, dynamic> map) {
    return InviteModel(
      code: map['code'] as String? ?? '',
      createdByUid: map['createdByUid'] as String? ?? '',
      coupleId: map['coupleId'] as String?,
      expiresAt: _parseTimestamp(map['expiresAt']),
      status: map['status'] as String? ?? 'pending',
      deepLinkUrl: map['deepLinkUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'createdByUid': createdByUid,
      'coupleId': coupleId,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'status': status,
      'deepLinkUrl': deepLinkUrl,
    };
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now().toUtc();
  }
}
```

- [ ] **Step 20: Run test to verify it passes**

Run: `flutter test test/core/models/invite_model_test.dart`
Expected: All 4 tests PASS

- [ ] **Step 21: Update barrel export**

```dart
// lib/core/models/models.dart
export 'user_model.dart';
export 'couple_model.dart';
export 'invite_model.dart';
export 'time_block_model.dart';
export 'overlap_result_model.dart';
```

- [ ] **Step 22: Run all model tests**

Run: `flutter test test/core/models/`
Expected: All 16 tests PASS

- [ ] **Step 23: Commit**

```bash
git add lib/core/models/ test/core/models/
git commit -m "feat: add core data models with Firestore serialization and tests"
```

---

## Phase 3: Services Layer

### Task 4: Firestore Service

**Files:**
- Create: `lib/services/firestore_service.dart`

- [ ] **Step 1: Write FirestoreService**

```dart
// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/models.dart';

class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // --- Users ---

  Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.id, doc.data()!);
  }

  Future<void> createUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<void> updateUser(String uid, Map<String, dynamic> fields) async {
    await _db.collection('users').doc(uid).update(fields);
  }

  Stream<UserModel?> watchUser(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromMap(doc.id, doc.data()!);
    });
  }

  // --- Couples ---

  Future<CoupleModel?> getCouple(String coupleId) async {
    final doc = await _db.collection('couples').doc(coupleId).get();
    if (!doc.exists) return null;
    return CoupleModel.fromMap(doc.id, doc.data()!);
  }

  Stream<CoupleModel?> watchCouple(String coupleId) {
    return _db.collection('couples').doc(coupleId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return CoupleModel.fromMap(doc.id, doc.data()!);
    });
  }

  // --- Invites ---

  Future<void> createInvite(InviteModel invite) async {
    await _db.collection('invites').doc(invite.code).set(invite.toMap());
  }

  Future<InviteModel?> getInvite(String code) async {
    final doc = await _db.collection('invites').doc(code).get();
    if (!doc.exists) return null;
    return InviteModel.fromMap(doc.data()!);
  }

  // --- TimeBlocks ---

  CollectionReference<Map<String, dynamic>> _blocksRef(String coupleId) {
    return _db.collection('timeblocks').doc(coupleId).collection('blocks');
  }

  Future<void> createBlock(String coupleId, TimeBlock block) async {
    await _blocksRef(coupleId).doc(block.id).set(block.toMap());
  }

  Future<void> updateBlock(String coupleId, String blockId, Map<String, dynamic> fields) async {
    await _blocksRef(coupleId).doc(blockId).update(fields);
  }

  Future<void> deleteBlock(String coupleId, String blockId) async {
    await _blocksRef(coupleId).doc(blockId).delete();
  }

  Stream<List<TimeBlock>> watchBlocks(String coupleId) {
    return _blocksRef(coupleId).snapshots().map((snap) {
      return snap.docs.map((doc) => TimeBlock.fromMap(doc.id, doc.data())).toList();
    });
  }

  Future<List<TimeBlock>> getBlocksByUser(String coupleId, String userId) async {
    final snap = await _blocksRef(coupleId)
        .where('userId', isEqualTo: userId)
        .get();
    return snap.docs.map((doc) => TimeBlock.fromMap(doc.id, doc.data())).toList();
  }

  Future<void> deleteGoogleBlocks(String coupleId, String userId) async {
    final snap = await _blocksRef(coupleId)
        .where('userId', isEqualTo: userId)
        .where('source', isEqualTo: 'google')
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // --- Overlaps ---

  Stream<OverlapResult?> watchOverlaps(String coupleId) {
    return _db
        .collection('overlaps')
        .doc(coupleId)
        .collection('windows')
        .doc('latest')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return OverlapResult.fromMap(doc.data()!);
    });
  }
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/services/firestore_service.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/services/firestore_service.dart
git commit -m "feat: add FirestoreService with CRUD for all collections"
```

---

### Task 5: Firestore Security Rules & Indexes

**Files:**
- Modify: `firestore.rules`
- Modify: `firestore.indexes.json`

- [ ] **Step 1: Write security rules**

```
// firestore.rules
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    // Users: read own doc + partner's doc. Write own doc only.
    match /users/{uid} {
      allow read: if request.auth != null && (
        request.auth.uid == uid ||
        (resource.data.coupleId != null &&
         get(/databases/$(database)/documents/couples/$(resource.data.coupleId)).data.userAUid == request.auth.uid ||
         get(/databases/$(database)/documents/couples/$(resource.data.coupleId)).data.userBUid == request.auth.uid)
      );
      allow write: if request.auth != null && request.auth.uid == uid;
    }

    // Couples: only members can read. Write via admin SDK only.
    match /couples/{coupleId} {
      allow read: if request.auth != null && (
        resource.data.userAUid == request.auth.uid ||
        resource.data.userBUid == request.auth.uid
      );
      allow write: if false;
    }

    // Invites: any auth user can read/create. Update restricted.
    match /invites/{code} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null && (
        resource.data.createdByUid == request.auth.uid ||
        request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status', 'coupleId'])
      );
    }

    // TimeBlocks: only couple members can read/write.
    match /timeblocks/{coupleId}/blocks/{blockId} {
      allow read, write: if request.auth != null && (
        get(/databases/$(database)/documents/couples/$(coupleId)).data.userAUid == request.auth.uid ||
        get(/databases/$(database)/documents/couples/$(coupleId)).data.userBUid == request.auth.uid
      );
    }

    // Overlaps: couple members can read. Write via admin SDK only.
    match /overlaps/{coupleId}/windows/{docId} {
      allow read: if request.auth != null && (
        get(/databases/$(database)/documents/couples/$(coupleId)).data.userAUid == request.auth.uid ||
        get(/databases/$(database)/documents/couples/$(coupleId)).data.userBUid == request.auth.uid
      );
      allow write: if false;
    }
  }
}
```

- [ ] **Step 2: Write composite indexes**

```json
{
  "indexes": [
    {
      "collectionGroup": "blocks",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "startUtc", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "blocks",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "source", "order": "ASCENDING" },
        { "fieldPath": "userId", "order": "ASCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

- [ ] **Step 3: Commit**

```bash
git add firestore.rules firestore.indexes.json
git commit -m "feat: add Firestore security rules and composite indexes"
```

---

### Task 6: Auth Service & Providers

**Files:**
- Create: `lib/services/auth_service.dart`
- Create: `lib/services/providers/auth_providers.dart`

- [ ] **Step 1: Write AuthService**

```dart
// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  AuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ??
            GoogleSignIn(scopes: ['email', 'https://www.googleapis.com/auth/calendar.readonly']);

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential> signInWithApple() async {
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    );
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );
    return _auth.signInWithCredential(oauthCredential);
  }

  Future<String?> getGoogleAccessToken() async {
    final googleUser = await _googleSignIn.signInSilently();
    if (googleUser == null) return null;
    final auth = await googleUser.authentication;
    return auth.accessToken;
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }
}
```

- [ ] **Step 2: Write auth providers**

```dart
// lib/services/providers/auth_providers.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/models.dart';
import '../auth_service.dart';
import '../firestore_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.valueOrNull;
  if (user == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchUser(user.uid);
});
```

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze lib/services/`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/services/auth_service.dart lib/services/providers/auth_providers.dart
git commit -m "feat: add AuthService with Google/Apple sign-in and auth providers"
```

---

### Task 7: Router & App Shell

**Files:**
- Create: `lib/core/router/app_router.dart`
- Modify: `lib/app.dart`

- [ ] **Step 1: Write router with redirect guards**

```dart
// lib/core/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/providers/auth_providers.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/onboarding/timezone_setup_screen.dart';
import '../../features/onboarding/routine_wizard_screen.dart';
import '../../features/pairing/pairing_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/calendar/week_view_screen.dart';
import '../../features/overlap/overlap_screen.dart';
import '../../features/blocks/block_management_screen.dart';
import '../../features/blocks/block_form_screen.dart';
import '../../features/settings/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final currentUser = ref.watch(currentUserProvider);

  return GoRouter(
    refreshListenable: GoRouterRefreshStream(
      ref.read(authServiceProvider).authStateChanges,
    ),
    initialLocation: '/',
    redirect: (context, state) {
      final isAuthenticated = authState.valueOrNull != null;
      final user = currentUser.valueOrNull;
      final isOnAuth = state.matchedLocation == '/auth';
      final isOnTimezone = state.matchedLocation == '/timezone-setup';
      final isOnRoutine = state.matchedLocation == '/routine-setup';
      final isOnPairing = state.matchedLocation == '/pairing';

      if (!isAuthenticated) return isOnAuth ? null : '/auth';
      if (isOnAuth) {
        if (user == null) return null; // Still loading
        if (user.timezone == 'UTC') return '/timezone-setup';
        if (user.coupleId == null) return '/pairing';
        return '/';
      }
      if (user == null) return null; // Still loading user doc
      if (user.timezone == 'UTC' && !isOnTimezone) return '/timezone-setup';
      if (isOnTimezone) return null;
      if (isOnRoutine) return null;
      if (user.coupleId == null && !isOnPairing) return '/pairing';
      if (isOnPairing && user.coupleId != null) return '/';

      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
      GoRoute(path: '/timezone-setup', builder: (_, __) => const TimezoneSetupScreen()),
      GoRoute(path: '/routine-setup', builder: (_, __) => const RoutineWizardScreen()),
      GoRoute(path: '/pairing', builder: (_, __) => const PairingScreen()),
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/calendar', builder: (_, __) => const WeekViewScreen()),
      GoRoute(path: '/overlaps', builder: (_, __) => const OverlapScreen()),
      GoRoute(path: '/blocks', builder: (_, __) => const BlockManagementScreen()),
      GoRoute(
        path: '/blocks/new',
        builder: (_, __) => const BlockFormScreen(),
      ),
      GoRoute(
        path: '/blocks/edit/:blockId',
        builder: (_, state) => BlockFormScreen(blockId: state.pathParameters['blockId']),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    stream.listen((_) => notifyListeners());
  }
}
```

- [ ] **Step 2: Create placeholder screens**

Create each of these files with a minimal placeholder widget. Every screen file follows this pattern — only the class name and title text differ:

```dart
// lib/features/auth/auth_screen.dart
import 'package:flutter/material.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Auth Screen')),
    );
  }
}
```

Create with the same pattern for all 10 screens:
- `lib/features/auth/auth_screen.dart` — `AuthScreen`, "Auth Screen"
- `lib/features/onboarding/timezone_setup_screen.dart` — `TimezoneSetupScreen`, "Timezone Setup"
- `lib/features/onboarding/routine_wizard_screen.dart` — `RoutineWizardScreen`, "Routine Setup"
- `lib/features/pairing/pairing_screen.dart` — `PairingScreen`, "Pairing"
- `lib/features/home/home_screen.dart` — `HomeScreen`, "Home"
- `lib/features/calendar/week_view_screen.dart` — `WeekViewScreen`, "Calendar"
- `lib/features/overlap/overlap_screen.dart` — `OverlapScreen`, "Overlaps"
- `lib/features/blocks/block_management_screen.dart` — `BlockManagementScreen`, "Blocks"
- `lib/features/blocks/block_form_screen.dart` — `BlockFormScreen` (with optional `blockId` parameter), "Block Form"
- `lib/features/settings/settings_screen.dart` — `SettingsScreen`, "Settings"

For `BlockFormScreen`, use this pattern instead:
```dart
// lib/features/blocks/block_form_screen.dart
import 'package:flutter/material.dart';

class BlockFormScreen extends StatelessWidget {
  final String? blockId;
  const BlockFormScreen({super.key, this.blockId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(blockId == null ? 'New Block' : 'Edit Block')),
      body: const Center(child: Text('Block Form')),
    );
  }
}
```

- [ ] **Step 3: Update app.dart to use router**

```dart
// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

class CoupleScheduleApp extends ConsumerWidget {
  const CoupleScheduleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Couple Schedule',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 4: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add lib/core/router/ lib/features/ lib/app.dart
git commit -m "feat: add go_router with redirect guards and placeholder screens"
```

---

## Phase 4: Feature Screens

### Task 8: Auth Screen

**Files:**
- Modify: `lib/features/auth/auth_screen.dart`

- [ ] **Step 1: Implement auth screen**

```dart
// lib/features/auth/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/providers/auth_providers.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await ref.read(authServiceProvider).signInWithGoogle();
      await _ensureUserDoc(cred);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await ref.read(authServiceProvider).signInWithApple();
      await _ensureUserDoc(cred);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureUserDoc(dynamic cred) async {
    final user = cred.user;
    if (user == null) return;
    final fs = ref.read(firestoreServiceProvider);
    final existing = await fs.getUser(user.uid);
    if (existing == null) {
      await fs.createUser(UserModel(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? '',
        photoUrl: user.photoURL,
        timezone: 'UTC',
        fcmTokens: [],
        createdAt: DateTime.now().toUtc(),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite, size: 80, color: AppColors.primary),
              const SizedBox(height: 16),
              Text('Couple Schedule',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Find your time together',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 48),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_error!, style: TextStyle(color: AppColors.error)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 24),
                  label: const Text('Continue with Google'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithApple,
                  icon: const Icon(Icons.apple, size: 24),
                  label: const Text('Continue with Apple'),
                ),
              ),
              if (_loading) const Padding(
                padding: EdgeInsets.only(top: 24),
                child: CircularProgressIndicator(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/features/auth/`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/features/auth/auth_screen.dart
git commit -m "feat: implement auth screen with Google and Apple sign-in"
```

---

### Task 9: Timezone Setup Screen

**Files:**
- Modify: `lib/features/onboarding/timezone_setup_screen.dart`
- Create: `lib/core/utils/tz_helper.dart`
- Create: `test/core/utils/tz_helper_test.dart`

- [ ] **Step 1: Write tz_helper tests**

```dart
// test/core/utils/tz_helper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:couple_schedule/core/utils/tz_helper.dart';

void main() {
  setUpAll(() => tz.initializeTimeZones());

  group('TzHelper', () {
    test('allTimezoneIds returns a non-empty sorted list', () {
      final ids = TzHelper.allTimezoneIds;
      expect(ids, isNotEmpty);
      expect(ids, contains('America/New_York'));
      expect(ids, contains('Asia/Tokyo'));
    });

    test('utcToLocal converts correctly', () {
      final utc = DateTime.utc(2026, 6, 15, 12, 0);
      final local = TzHelper.utcToLocal(utc, 'America/New_York');
      // EDT is UTC-4 in June
      expect(local.hour, 8);
    });

    test('localToUtc converts correctly', () {
      final utc = TzHelper.localToUtc(2026, 6, 15, 8, 0, 'America/New_York');
      expect(utc.hour, 12);
    });

    test('formatTimezoneOffset returns readable offset', () {
      final display = TzHelper.formatTimezoneOffset('America/New_York');
      expect(display, contains('UTC'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/utils/tz_helper_test.dart`
Expected: FAIL

- [ ] **Step 3: Write TzHelper**

```dart
// lib/core/utils/tz_helper.dart
import 'package:timezone/timezone.dart' as tz;

class TzHelper {
  static List<String> get allTimezoneIds {
    final ids = tz.timeZoneDatabase.locations.keys.toList();
    ids.sort();
    return ids;
  }

  static DateTime utcToLocal(DateTime utcTime, String timezoneId) {
    final location = tz.getLocation(timezoneId);
    final tzDateTime = tz.TZDateTime.from(utcTime.toUtc(), location);
    return DateTime(
      tzDateTime.year, tzDateTime.month, tzDateTime.day,
      tzDateTime.hour, tzDateTime.minute, tzDateTime.second,
    );
  }

  static DateTime localToUtc(int year, int month, int day, int hour, int minute, String timezoneId) {
    final location = tz.getLocation(timezoneId);
    final local = tz.TZDateTime(location, year, month, day, hour, minute);
    return local.toUtc();
  }

  static String formatTimezoneOffset(String timezoneId) {
    final location = tz.getLocation(timezoneId);
    final now = tz.TZDateTime.now(location);
    final offset = now.timeZoneOffset;
    final hours = offset.inHours;
    final minutes = offset.inMinutes.remainder(60).abs();
    final sign = hours >= 0 ? '+' : '';
    if (minutes == 0) return 'UTC$sign$hours';
    return 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }

  static String currentTimeIn(String timezoneId) {
    final location = tz.getLocation(timezoneId);
    final now = tz.TZDateTime.now(location);
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/utils/tz_helper_test.dart`
Expected: All 4 tests PASS

- [ ] **Step 5: Implement timezone setup screen**

```dart
// lib/features/onboarding/timezone_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/tz_helper.dart';
import '../../services/providers/auth_providers.dart';
import '../../core/theme/app_theme.dart';

class TimezoneSetupScreen extends ConsumerStatefulWidget {
  const TimezoneSetupScreen({super.key});

  @override
  ConsumerState<TimezoneSetupScreen> createState() => _TimezoneSetupScreenState();
}

class _TimezoneSetupScreenState extends ConsumerState<TimezoneSetupScreen> {
  late String _selectedTz;
  final _searchController = TextEditingController();
  List<String> _filtered = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedTz = DateTime.now().timeZoneName;
    // Try to detect device timezone
    final deviceTz = _detectDeviceTimezone();
    _selectedTz = deviceTz;
    _filtered = TzHelper.allTimezoneIds;
  }

  String _detectDeviceTimezone() {
    final offset = DateTime.now().timeZoneOffset;
    // Find a timezone matching the device offset as a reasonable default
    for (final id in TzHelper.allTimezoneIds) {
      if (TzHelper.formatTimezoneOffset(id).contains('UTC${offset.inHours >= 0 ? '+' : ''}${offset.inHours}')) {
        return id;
      }
    }
    return 'UTC';
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = TzHelper.allTimezoneIds;
      } else {
        _filtered = TzHelper.allTimezoneIds
            .where((id) => id.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user != null) {
      await ref.read(firestoreServiceProvider).updateUser(user.uid, {'timezone': _selectedTz});
    }
    if (mounted) context.go('/routine-setup');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set Your Timezone')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Selected: $_selectedTz (${TzHelper.formatTimezoneOffset(_selectedTz)})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search timezones...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _filter,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final tz = _filtered[index];
                final isSelected = tz == _selectedTz;
                return ListTile(
                  title: Text(tz),
                  subtitle: Text(TzHelper.formatTimezoneOffset(tz)),
                  trailing: isSelected ? Icon(Icons.check, color: AppColors.primary) : null,
                  selected: isSelected,
                  onTap: () => setState(() => _selectedTz = tz),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 6: Run flutter analyze**

Run: `flutter analyze lib/features/onboarding/ lib/core/utils/`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add lib/core/utils/tz_helper.dart test/core/utils/tz_helper_test.dart lib/features/onboarding/timezone_setup_screen.dart
git commit -m "feat: add timezone helper with tests and timezone setup screen"
```

---

### Task 10: Pairing Service & Screen

**Files:**
- Create: `lib/services/providers/couple_providers.dart`
- Modify: `lib/features/pairing/pairing_screen.dart`

- [ ] **Step 1: Write couple providers**

```dart
// lib/services/providers/couple_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/models.dart';
import 'auth_providers.dart';

final coupleProvider = StreamProvider<CoupleModel?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user?.coupleId == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchCouple(user!.coupleId!);
});

final partnerProvider = StreamProvider<UserModel?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final couple = ref.watch(coupleProvider).valueOrNull;
  if (user == null || couple == null) return Stream.value(null);
  final partnerUid = couple.partnerUid(user.uid);
  return ref.watch(firestoreServiceProvider).watchUser(partnerUid);
});

final inviteServiceProvider = Provider<InviteService>((ref) {
  return InviteService(ref);
});

class InviteService {
  final Ref _ref;
  const InviteService(this._ref);

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final uuid = const Uuid().v4().replaceAll('-', '');
    return List.generate(6, (i) => chars[uuid.codeUnitAt(i) % chars.length]).join();
  }

  Future<InviteModel> createInvite() async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user == null) throw Exception('Not signed in');

    final code = _generateCode();
    final invite = InviteModel(
      code: code,
      createdByUid: user.uid,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 48)),
      status: 'pending',
    );
    await _ref.read(firestoreServiceProvider).createInvite(invite);
    return invite;
  }

  Future<String> redeemInvite(String code) async {
    final callable = FirebaseFunctions.instance.httpsCallable('redeemInvite');
    final result = await callable.call<Map<String, dynamic>>({'code': code.toUpperCase().trim()});
    return result.data['coupleId'] as String;
  }
}
```

- [ ] **Step 2: Implement pairing screen**

```dart
// lib/features/pairing/pairing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/providers/auth_providers.dart';
import '../../services/providers/couple_providers.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  InviteModel? _invite;
  bool _generating = false;
  bool _redeeming = false;
  String? _error;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _generateInvite() async {
    setState(() { _generating = true; _error = null; });
    try {
      final invite = await ref.read(inviteServiceProvider).createInvite();
      setState(() => _invite = invite);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _generating = false);
    }
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Code must be 6 characters');
      return;
    }
    setState(() { _redeeming = true; _error = null; });
    try {
      await ref.read(inviteServiceProvider).redeemInvite(code);
      // Router will auto-redirect to home when coupleId is set
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair with Partner'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Share Code'), Tab(text: 'Enter Code')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Share tab
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Share this code with your partner',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 24),
                if (_invite != null)
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _invite!.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied!')),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _invite!.code,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold, letterSpacing: 8,
                        ),
                      ),
                    ),
                  ),
                if (_invite != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Tap to copy', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                const SizedBox(height: 24),
                if (_invite == null)
                  FilledButton(
                    onPressed: _generating ? null : _generateInvite,
                    child: _generating
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Generate Invite Code'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!, style: TextStyle(color: AppColors.error)),
                  ),
              ],
            ),
          ),
          // Enter tab
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Enter your partner\'s code',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 4),
                  decoration: const InputDecoration(
                    hintText: 'ABC123',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _redeeming ? null : _redeem,
                  child: _redeeming
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Pair'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!, style: TextStyle(color: AppColors.error)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze lib/features/pairing/ lib/services/providers/couple_providers.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/services/providers/couple_providers.dart lib/features/pairing/pairing_screen.dart
git commit -m "feat: add pairing service with invite code generation and pairing screen"
```

---

### Task 11: Block Service, Providers & Block Form

**Files:**
- Create: `lib/services/providers/block_providers.dart`
- Modify: `lib/features/blocks/block_form_screen.dart`

- [ ] **Step 1: Write block providers**

```dart
// lib/services/providers/block_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/models.dart';
import 'auth_providers.dart';
import 'couple_providers.dart';

final blocksProvider = StreamProvider<List<TimeBlock>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user?.coupleId == null) return Stream.value([]);
  return ref.watch(firestoreServiceProvider).watchBlocks(user!.coupleId!);
});

final myBlocksProvider = Provider<List<TimeBlock>>((ref) {
  final blocks = ref.watch(blocksProvider).valueOrNull ?? [];
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return [];
  return blocks.where((b) => b.userId == user.uid).toList();
});

final partnerBlocksProvider = Provider<List<TimeBlock>>((ref) {
  final blocks = ref.watch(blocksProvider).valueOrNull ?? [];
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return [];
  return blocks.where((b) => b.userId != user.uid && b.visibility == BlockVisibility.bothPartners).toList();
});

final blockServiceProvider = Provider<BlockService>((ref) => BlockService(ref));

class BlockService {
  final Ref _ref;
  const BlockService(this._ref);

  Future<void> createBlock({
    required String title,
    required BlockType type,
    required BlockCategory category,
    required DateTime startUtc,
    required DateTime endUtc,
    required String timezone,
    String? recurrenceRule,
    required BlockVisibility visibility,
  }) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user?.coupleId == null) throw Exception('Not paired');

    final block = TimeBlock(
      id: const Uuid().v4(),
      userId: user!.uid,
      title: title,
      type: type,
      category: category,
      startUtc: startUtc,
      endUtc: endUtc,
      timezone: timezone,
      recurrenceRule: recurrenceRule,
      source: BlockSource.manual,
      visibility: visibility,
      createdAt: DateTime.now().toUtc(),
    );
    await _ref.read(firestoreServiceProvider).createBlock(user.coupleId!, block);
  }

  Future<void> updateBlock(String blockId, Map<String, dynamic> fields) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user?.coupleId == null) return;
    await _ref.read(firestoreServiceProvider).updateBlock(user!.coupleId!, blockId, fields);
  }

  Future<void> deleteBlock(String blockId) async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user?.coupleId == null) return;
    await _ref.read(firestoreServiceProvider).deleteBlock(user!.coupleId!, blockId);
  }
}
```

- [ ] **Step 2: Implement block form screen**

```dart
// lib/features/blocks/block_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../core/utils/tz_helper.dart';
import '../../services/providers/auth_providers.dart';
import '../../services/providers/block_providers.dart';

class BlockFormScreen extends ConsumerStatefulWidget {
  final String? blockId;
  const BlockFormScreen({super.key, this.blockId});

  @override
  ConsumerState<BlockFormScreen> createState() => _BlockFormScreenState();
}

class _BlockFormScreenState extends ConsumerState<BlockFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  BlockType _type = BlockType.busy;
  BlockCategory _category = BlockCategory.other;
  BlockVisibility _visibility = BlockVisibility.bothPartners;
  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime _endDate = DateTime.now();
  TimeOfDay _endTime = TimeOfDay(hour: TimeOfDay.now().hour + 1, minute: TimeOfDay.now().minute);
  String _recurrence = 'none';
  List<int> _weekDays = [];
  bool _saving = false;

  bool get _isEditing => widget.blockId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadBlock());
    }
  }

  void _loadBlock() {
    final blocks = ref.read(blocksProvider).valueOrNull ?? [];
    final block = blocks.where((b) => b.id == widget.blockId).firstOrNull;
    if (block == null) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    final tz = user?.timezone ?? 'UTC';
    final localStart = TzHelper.utcToLocal(block.startUtc, tz);
    final localEnd = TzHelper.utcToLocal(block.endUtc, tz);

    setState(() {
      _titleController.text = block.title;
      _type = block.type;
      _category = block.category;
      _visibility = block.visibility;
      _startDate = localStart;
      _startTime = TimeOfDay(hour: localStart.hour, minute: localStart.minute);
      _endDate = localEnd;
      _endTime = TimeOfDay(hour: localEnd.hour, minute: localEnd.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final user = ref.read(currentUserProvider).valueOrNull;
    final tz = user?.timezone ?? 'UTC';

    final startUtc = TzHelper.localToUtc(
      _startDate.year, _startDate.month, _startDate.day,
      _startTime.hour, _startTime.minute, tz,
    );
    final endUtc = TzHelper.localToUtc(
      _endDate.year, _endDate.month, _endDate.day,
      _endTime.hour, _endTime.minute, tz,
    );

    if (endUtc.isBefore(startUtc) || endUtc.isAtSameMomentAs(startUtc)) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be after start time')),
        );
      }
      return;
    }

    String? rrule;
    if (_recurrence == 'daily') {
      rrule = 'FREQ=DAILY';
    } else if (_recurrence == 'weekly' && _weekDays.isNotEmpty) {
      final days = _weekDays.map((d) => ['', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'][d]).join(',');
      rrule = 'FREQ=WEEKLY;BYDAY=$days';
    } else if (_recurrence == 'monthly') {
      rrule = 'FREQ=MONTHLY';
    }

    try {
      if (_isEditing) {
        await ref.read(blockServiceProvider).updateBlock(widget.blockId!, {
          'title': _titleController.text,
          'type': _type.name,
          'category': _category.name,
          'startUtc': startUtc.millisecondsSinceEpoch,
          'endUtc': endUtc.millisecondsSinceEpoch,
          'recurrenceRule': rrule,
          'visibility': _visibility.name,
        });
      } else {
        await ref.read(blockServiceProvider).createBlock(
          title: _titleController.text,
          type: _type,
          category: _category,
          startUtc: startUtc,
          endUtc: endUtc,
          timezone: tz,
          recurrenceRule: rrule,
          visibility: _visibility,
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Block' : 'New Block')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<BlockType>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: BlockType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<BlockCategory>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: BlockCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 16),
            // Start date+time
            ListTile(
              title: const Text('Start'),
              subtitle: Text('${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')} ${_startTime.format(context)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  final time = await showTimePicker(context: context, initialTime: _startTime);
                  if (time != null) setState(() { _startDate = date; _startTime = time; });
                }
              },
            ),
            // End date+time
            ListTile(
              title: const Text('End'),
              subtitle: Text('${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')} ${_endTime.format(context)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _endDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  final time = await showTimePicker(context: context, initialTime: _endTime);
                  if (time != null) setState(() { _endDate = date; _endTime = time; });
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _recurrence,
              decoration: const InputDecoration(labelText: 'Recurrence'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('None')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              ],
              onChanged: (v) => setState(() => _recurrence = v!),
            ),
            if (_recurrence == 'weekly')
              Wrap(
                spacing: 8,
                children: List.generate(7, (i) {
                  final day = i + 1;
                  final label = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i];
                  return FilterChip(
                    label: Text(label),
                    selected: _weekDays.contains(day),
                    onSelected: (sel) {
                      setState(() {
                        if (sel) { _weekDays.add(day); } else { _weekDays.remove(day); }
                      });
                    },
                  );
                }),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<BlockVisibility>(
              value: _visibility,
              decoration: const InputDecoration(labelText: 'Visibility'),
              items: const [
                DropdownMenuItem(value: BlockVisibility.bothPartners, child: Text('Both partners')),
                DropdownMenuItem(value: BlockVisibility.onlyMe, child: Text('Only me')),
              ],
              onChanged: (v) => setState(() => _visibility = v!),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEditing ? 'Save' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze lib/services/providers/block_providers.dart lib/features/blocks/block_form_screen.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/services/providers/block_providers.dart lib/features/blocks/block_form_screen.dart
git commit -m "feat: add block service, providers, and block form screen"
```

---

### Task 12: Block Management Screen

**Files:**
- Modify: `lib/features/blocks/block_management_screen.dart`

- [ ] **Step 1: Implement block management screen**

```dart
// lib/features/blocks/block_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../services/providers/block_providers.dart';
import '../../core/theme/app_theme.dart';

class BlockManagementScreen extends ConsumerStatefulWidget {
  const BlockManagementScreen({super.key});

  @override
  ConsumerState<BlockManagementScreen> createState() => _BlockManagementScreenState();
}

class _BlockManagementScreenState extends ConsumerState<BlockManagementScreen> {
  BlockSource? _sourceFilter;
  BlockCategory? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    var blocks = ref.watch(myBlocksProvider);

    if (_sourceFilter != null) {
      blocks = blocks.where((b) => b.source == _sourceFilter).toList();
    }
    if (_categoryFilter != null) {
      blocks = blocks.where((b) => b.category == _categoryFilter).toList();
    }

    blocks.sort((a, b) => a.startUtc.compareTo(b.startUtc));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Blocks'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                if (value == 'all') { _sourceFilter = null; _categoryFilter = null; }
                else if (value == 'google') _sourceFilter = BlockSource.google;
                else if (value == 'manual') _sourceFilter = BlockSource.manual;
              });
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'all', child: Text('All')),
              const PopupMenuItem(value: 'google', child: Text('Google Calendar')),
              const PopupMenuItem(value: 'manual', child: Text('Manual')),
            ],
          ),
        ],
      ),
      body: blocks.isEmpty
          ? const Center(child: Text('No blocks yet'))
          : ListView.builder(
              itemCount: blocks.length,
              itemBuilder: (context, index) {
                final block = blocks[index];
                final isManual = block.source == BlockSource.manual;
                return Dismissible(
                  key: Key(block.id),
                  direction: isManual ? DismissDirection.endToStart : DismissDirection.none,
                  background: Container(
                    color: AppColors.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete block?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => ref.read(blockServiceProvider).deleteBlock(block.id),
                  child: ListTile(
                    leading: Icon(_categoryIcon(block.category)),
                    title: Text(block.title),
                    subtitle: Text('${block.category.name} · ${block.source.name}'),
                    trailing: isManual ? const Icon(Icons.chevron_right) : const Icon(Icons.lock_outline, size: 16),
                    onTap: isManual ? () => context.push('/blocks/edit/${block.id}') : null,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/blocks/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  IconData _categoryIcon(BlockCategory cat) {
    return switch (cat) {
      BlockCategory.work => Icons.work,
      BlockCategory.study => Icons.school,
      BlockCategory.commute => Icons.directions_car,
      BlockCategory.exercise => Icons.fitness_center,
      BlockCategory.social => Icons.people,
      BlockCategory.meals => Icons.restaurant,
      BlockCategory.sleep => Icons.bedtime,
      BlockCategory.personal => Icons.person,
      BlockCategory.other => Icons.event,
    };
  }
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/features/blocks/`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/features/blocks/block_management_screen.dart
git commit -m "feat: add block management screen with filtering and swipe-to-delete"
```

---

### Task 13: Routine Setup Wizard

**Files:**
- Modify: `lib/features/onboarding/routine_wizard_screen.dart`

- [ ] **Step 1: Implement routine wizard**

```dart
// lib/features/onboarding/routine_wizard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/models.dart';
import '../../core/utils/tz_helper.dart';
import '../../services/providers/auth_providers.dart';
import '../../services/providers/block_providers.dart';

class RoutineWizardScreen extends ConsumerStatefulWidget {
  const RoutineWizardScreen({super.key});

  @override
  ConsumerState<RoutineWizardScreen> createState() => _RoutineWizardScreenState();
}

class _RoutineWizardScreenState extends ConsumerState<RoutineWizardScreen> {
  int _step = 0;
  bool _saving = false;

  // Sleep
  TimeOfDay _bedtime = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay _wakeTime = const TimeOfDay(hour: 7, minute: 0);

  // Work
  TimeOfDay _workStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _workEnd = const TimeOfDay(hour: 17, minute: 0);
  List<int> _workDays = [1, 2, 3, 4, 5]; // Mon-Fri

  // Commute
  TimeOfDay _commuteAmStart = const TimeOfDay(hour: 7, minute: 30);
  TimeOfDay _commuteAmEnd = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _commutePmStart = const TimeOfDay(hour: 17, minute: 30);
  TimeOfDay _commutePmEnd = const TimeOfDay(hour: 18, minute: 30);
  List<int> _commuteDays = [1, 2, 3, 4, 5];

  final _steps = const ['Sleep', 'Work / Study', 'Commute'];

  Future<void> _pickTime(TimeOfDay current, ValueChanged<TimeOfDay> onPicked) async {
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked != null) setState(() => onPicked(picked));
  }

  String _dayLabel(int d) => ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d];

  String _rrule(List<int> days) {
    final dayNames = days.map((d) => ['', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'][d]).join(',');
    return 'FREQ=WEEKLY;BYDAY=$dayNames';
  }

  Future<void> _saveStep() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user?.coupleId == null && _step < 2) {
      // Not paired yet — just move to next step, blocks will be created later
      // Actually, we might not be paired yet during onboarding. Let's skip block creation
      // if not paired and just advance.
      setState(() => _step++);
      return;
    }

    final tz = user?.timezone ?? 'UTC';
    final service = ref.read(blockServiceProvider);

    setState(() => _saving = true);
    try {
      if (_step == 0) {
        // Sleep block: every day
        await service.createBlock(
          title: 'Sleep',
          type: BlockType.busy,
          category: BlockCategory.sleep,
          startUtc: TzHelper.localToUtc(2026, 1, 1, _bedtime.hour, _bedtime.minute, tz),
          endUtc: TzHelper.localToUtc(2026, 1, 2, _wakeTime.hour, _wakeTime.minute, tz),
          timezone: tz,
          recurrenceRule: 'FREQ=DAILY',
          visibility: BlockVisibility.bothPartners,
        );
      } else if (_step == 1) {
        // Work block
        await service.createBlock(
          title: 'Work',
          type: BlockType.busy,
          category: BlockCategory.work,
          startUtc: TzHelper.localToUtc(2026, 1, 1, _workStart.hour, _workStart.minute, tz),
          endUtc: TzHelper.localToUtc(2026, 1, 1, _workEnd.hour, _workEnd.minute, tz),
          timezone: tz,
          recurrenceRule: _rrule(_workDays),
          visibility: BlockVisibility.bothPartners,
        );
      } else if (_step == 2) {
        // Morning commute
        await service.createBlock(
          title: 'Morning Commute',
          type: BlockType.busy,
          category: BlockCategory.commute,
          startUtc: TzHelper.localToUtc(2026, 1, 1, _commuteAmStart.hour, _commuteAmStart.minute, tz),
          endUtc: TzHelper.localToUtc(2026, 1, 1, _commuteAmEnd.hour, _commuteAmEnd.minute, tz),
          timezone: tz,
          recurrenceRule: _rrule(_commuteDays),
          visibility: BlockVisibility.bothPartners,
        );
        // Evening commute
        await service.createBlock(
          title: 'Evening Commute',
          type: BlockType.busy,
          category: BlockCategory.commute,
          startUtc: TzHelper.localToUtc(2026, 1, 1, _commutePmStart.hour, _commutePmStart.minute, tz),
          endUtc: TzHelper.localToUtc(2026, 1, 1, _commutePmEnd.hour, _commutePmEnd.minute, tz),
          timezone: tz,
          recurrenceRule: _rrule(_commuteDays),
          visibility: BlockVisibility.bothPartners,
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }

    setState(() => _saving = false);
    if (_step < 2) {
      setState(() => _step++);
    } else {
      if (mounted) context.go('/pairing');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Routine: ${_steps[_step]}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: (_step + 1) / 3),
            const SizedBox(height: 24),
            Text('When do you typically ${_steps[_step].toLowerCase()}?',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            if (_step == 0) ..._buildSleepStep(),
            if (_step == 1) ..._buildWorkStep(),
            if (_step == 2) ..._buildCommuteStep(),
            const Spacer(),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : () {
                    if (_step < 2) {
                      setState(() => _step++);
                    } else {
                      context.go('/pairing');
                    }
                  },
                  child: const Text('Skip'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _saveStep,
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_step < 2 ? 'Next' : 'Finish'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSleepStep() => [
    ListTile(
      title: const Text('Bedtime'),
      trailing: Text(_bedtime.format(context), style: Theme.of(context).textTheme.titleMedium),
      onTap: () => _pickTime(_bedtime, (t) => _bedtime = t),
    ),
    ListTile(
      title: const Text('Wake time'),
      trailing: Text(_wakeTime.format(context), style: Theme.of(context).textTheme.titleMedium),
      onTap: () => _pickTime(_wakeTime, (t) => _wakeTime = t),
    ),
  ];

  List<Widget> _buildWorkStep() => [
    ListTile(
      title: const Text('Start'),
      trailing: Text(_workStart.format(context), style: Theme.of(context).textTheme.titleMedium),
      onTap: () => _pickTime(_workStart, (t) => _workStart = t),
    ),
    ListTile(
      title: const Text('End'),
      trailing: Text(_workEnd.format(context), style: Theme.of(context).textTheme.titleMedium),
      onTap: () => _pickTime(_workEnd, (t) => _workEnd = t),
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      children: List.generate(7, (i) {
        final day = i + 1;
        return FilterChip(
          label: Text(_dayLabel(day)),
          selected: _workDays.contains(day),
          onSelected: (sel) => setState(() {
            if (sel) _workDays.add(day); else _workDays.remove(day);
          }),
        );
      }),
    ),
  ];

  List<Widget> _buildCommuteStep() => [
    Text('Morning', style: Theme.of(context).textTheme.titleMedium),
    ListTile(
      title: const Text('Depart'),
      trailing: Text(_commuteAmStart.format(context)),
      onTap: () => _pickTime(_commuteAmStart, (t) => _commuteAmStart = t),
    ),
    ListTile(
      title: const Text('Arrive'),
      trailing: Text(_commuteAmEnd.format(context)),
      onTap: () => _pickTime(_commuteAmEnd, (t) => _commuteAmEnd = t),
    ),
    const SizedBox(height: 8),
    Text('Evening', style: Theme.of(context).textTheme.titleMedium),
    ListTile(
      title: const Text('Depart'),
      trailing: Text(_commutePmStart.format(context)),
      onTap: () => _pickTime(_commutePmStart, (t) => _commutePmStart = t),
    ),
    ListTile(
      title: const Text('Arrive'),
      trailing: Text(_commutePmEnd.format(context)),
      onTap: () => _pickTime(_commutePmEnd, (t) => _commutePmEnd = t),
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      children: List.generate(7, (i) {
        final day = i + 1;
        return FilterChip(
          label: Text(_dayLabel(day)),
          selected: _commuteDays.contains(day),
          onSelected: (sel) => setState(() {
            if (sel) _commuteDays.add(day); else _commuteDays.remove(day);
          }),
        );
      }),
    ),
  ];
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/features/onboarding/routine_wizard_screen.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/features/onboarding/routine_wizard_screen.dart
git commit -m "feat: add routine setup wizard with sleep, work, and commute steps"
```

---

## Phase 5: Cloud Functions

### Task 14: Cloud Functions Scaffold

**Files:**
- Modify: `functions/package.json`
- Modify: `functions/tsconfig.json`
- Create: `functions/src/index.ts`

- [ ] **Step 1: Update functions/package.json**

```json
{
  "name": "couple-schedule-functions",
  "scripts": {
    "build": "tsc",
    "build:watch": "tsc --watch",
    "serve": "npm run build && firebase emulators:start --only functions",
    "shell": "npm run build && firebase functions:shell",
    "deploy": "firebase deploy --only functions",
    "test": "jest --detectOpenHandles"
  },
  "engines": {
    "node": "20"
  },
  "main": "lib/index.js",
  "dependencies": {
    "firebase-admin": "^13.0.0",
    "firebase-functions": "^6.3.0",
    "luxon": "^3.5.0",
    "rrule": "^2.8.1"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "@types/node": "^20.0.0",
    "@types/luxon": "^3.4.0",
    "jest": "^29.7.0",
    "ts-jest": "^29.2.0",
    "@types/jest": "^29.5.0"
  }
}
```

- [ ] **Step 2: Update functions/tsconfig.json**

```json
{
  "compilerOptions": {
    "module": "commonjs",
    "noImplicitReturns": true,
    "noUnusedLocals": true,
    "outDir": "lib",
    "sourceMap": true,
    "strict": true,
    "target": "es2022",
    "esModuleInterop": true,
    "resolveJsonModule": true
  },
  "compileOnSave": true,
  "include": ["src"]
}
```

- [ ] **Step 3: Write index.ts with exports**

```typescript
// functions/src/index.ts
export { onBlockWrite } from "./onBlockWrite";
export { onOverlapWrite } from "./onOverlapWrite";
export { onInviteCreate } from "./onInviteCreate";
export { redeemInvite } from "./redeemInvite";
export { unpairCouple } from "./unpairCouple";
export { cleanupExpiredInvites } from "./cleanupInvites";
```

- [ ] **Step 4: Install dependencies**

Run:
```bash
cd functions && npm install && cd ..
```

- [ ] **Step 5: Commit**

```bash
git add functions/package.json functions/tsconfig.json functions/src/index.ts functions/package-lock.json
git commit -m "chore: set up Cloud Functions scaffold with dependencies"
```

---

### Task 15: Overlap Engine — Interval Math

**Files:**
- Create: `functions/src/utils/overlap.ts`
- Create: `functions/src/utils/recurrence.ts`
- Create: `functions/src/__tests__/overlap.test.ts`
- Create: `functions/src/__tests__/recurrence.test.ts`

- [ ] **Step 1: Write overlap math tests**

```typescript
// functions/src/__tests__/overlap.test.ts
import { mergeIntervals, invertIntervals, intersectIntervals, scoreWindow } from "../utils/overlap";

describe("mergeIntervals", () => {
  it("merges overlapping intervals", () => {
    const intervals = [
      { start: 0, end: 10 },
      { start: 5, end: 15 },
      { start: 20, end: 25 },
    ];
    const merged = mergeIntervals(intervals);
    expect(merged).toEqual([
      { start: 0, end: 15 },
      { start: 20, end: 25 },
    ]);
  });

  it("returns empty for empty input", () => {
    expect(mergeIntervals([])).toEqual([]);
  });

  it("handles adjacent intervals", () => {
    const intervals = [
      { start: 0, end: 10 },
      { start: 10, end: 20 },
    ];
    const merged = mergeIntervals(intervals);
    expect(merged).toEqual([{ start: 0, end: 20 }]);
  });
});

describe("invertIntervals", () => {
  it("inverts busy to free within a range", () => {
    const busy = [{ start: 100, end: 200 }, { start: 300, end: 400 }];
    const free = invertIntervals(busy, 0, 500);
    expect(free).toEqual([
      { start: 0, end: 100 },
      { start: 200, end: 300 },
      { start: 400, end: 500 },
    ]);
  });

  it("returns full range if no busy intervals", () => {
    const free = invertIntervals([], 0, 1000);
    expect(free).toEqual([{ start: 0, end: 1000 }]);
  });
});

describe("intersectIntervals", () => {
  it("finds overlap between two sets", () => {
    const a = [{ start: 0, end: 100 }, { start: 200, end: 400 }];
    const b = [{ start: 50, end: 250 }];
    const result = intersectIntervals(a, b);
    expect(result).toEqual([
      { start: 50, end: 100 },
      { start: 200, end: 250 },
    ]);
  });

  it("returns empty when no overlap", () => {
    const a = [{ start: 0, end: 10 }];
    const b = [{ start: 20, end: 30 }];
    expect(intersectIntervals(a, b)).toEqual([]);
  });
});

describe("scoreWindow", () => {
  it("gives higher score to longer windows", () => {
    const short = scoreWindow(30, false, false, false, false, 0);
    const long = scoreWindow(120, false, false, false, false, 0);
    expect(long).toBeGreaterThan(short);
  });

  it("gives evening bonus", () => {
    const noEvening = scoreWindow(60, false, false, false, false, 0);
    const bothEvening = scoreWindow(60, true, false, false, false, 0);
    expect(bothEvening).toBeGreaterThan(noEvening);
  });

  it("applies time decay", () => {
    const today = scoreWindow(60, false, false, false, false, 0);
    const nextWeek = scoreWindow(60, false, false, false, false, 7);
    expect(today).toBeGreaterThan(nextWeek);
  });
});
```

- [ ] **Step 2: Configure jest**

Create `functions/jest.config.js`:
```javascript
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["**/src/__tests__/**/*.test.ts"],
};
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd functions && npx jest --detectOpenHandles 2>&1; cd ..`
Expected: FAIL — utils/overlap doesn't exist

- [ ] **Step 4: Write overlap utility**

```typescript
// functions/src/utils/overlap.ts
export interface Interval {
  start: number;
  end: number;
}

export function mergeIntervals(intervals: Interval[]): Interval[] {
  if (intervals.length === 0) return [];
  const sorted = [...intervals].sort((a, b) => a.start - b.start);
  const merged: Interval[] = [sorted[0]];

  for (let i = 1; i < sorted.length; i++) {
    const last = merged[merged.length - 1];
    if (sorted[i].start <= last.end) {
      last.end = Math.max(last.end, sorted[i].end);
    } else {
      merged.push({ ...sorted[i] });
    }
  }
  return merged;
}

export function invertIntervals(
  busy: Interval[],
  rangeStart: number,
  rangeEnd: number
): Interval[] {
  const merged = mergeIntervals(busy);
  const free: Interval[] = [];
  let cursor = rangeStart;

  for (const b of merged) {
    if (cursor < b.start) {
      free.push({ start: cursor, end: b.start });
    }
    cursor = Math.max(cursor, b.end);
  }
  if (cursor < rangeEnd) {
    free.push({ start: cursor, end: rangeEnd });
  }
  return free;
}

export function intersectIntervals(
  a: Interval[],
  b: Interval[]
): Interval[] {
  const result: Interval[] = [];
  let i = 0;
  let j = 0;

  while (i < a.length && j < b.length) {
    const start = Math.max(a[i].start, b[j].start);
    const end = Math.min(a[i].end, b[j].end);
    if (start < end) {
      result.push({ start, end });
    }
    if (a[i].end < b[j].end) {
      i++;
    } else {
      j++;
    }
  }
  return result;
}

export function scoreWindow(
  durationMinutes: number,
  bothInEvening: boolean,
  oneInEvening: boolean,
  isWeekend: boolean,
  _reasonableBoth: boolean,
  daysFromNow: number
): number {
  const base = Math.log2(durationMinutes + 1) * 10;
  const eveningBonus = bothInEvening ? 30 : oneInEvening ? 10 : 0;
  const weekendBonus = isWeekend ? 15 : 0;
  const timeDecay = -daysFromNow * 0.5;
  return Math.round((base + eveningBonus + weekendBonus + timeDecay) * 10) / 10;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd functions && npx jest --detectOpenHandles 2>&1; cd ..`
Expected: All tests PASS

- [ ] **Step 6: Write recurrence tests**

```typescript
// functions/src/__tests__/recurrence.test.ts
import { expandRecurrence } from "../utils/recurrence";

describe("expandRecurrence", () => {
  it("expands daily recurrence", () => {
    const start = new Date("2026-04-06T09:00:00Z").getTime();
    const end = new Date("2026-04-06T10:00:00Z").getTime();
    const rangeStart = new Date("2026-04-06T00:00:00Z").getTime();
    const rangeEnd = new Date("2026-04-09T00:00:00Z").getTime();

    const instances = expandRecurrence("FREQ=DAILY", start, end, rangeStart, rangeEnd);
    expect(instances.length).toBe(3);
    // Apr 6, 7, 8
  });

  it("expands weekly recurrence with BYDAY", () => {
    // Monday April 6, 2026 is a Monday
    const start = new Date("2026-04-06T09:00:00Z").getTime();
    const end = new Date("2026-04-06T10:00:00Z").getTime();
    const rangeStart = new Date("2026-04-06T00:00:00Z").getTime();
    const rangeEnd = new Date("2026-04-20T00:00:00Z").getTime();

    const instances = expandRecurrence("FREQ=WEEKLY;BYDAY=MO,WE,FR", start, end, rangeStart, rangeEnd);
    // 2 weeks * 3 days = 6 instances
    expect(instances.length).toBe(6);
  });

  it("returns single instance if no rrule", () => {
    const start = new Date("2026-04-06T09:00:00Z").getTime();
    const end = new Date("2026-04-06T10:00:00Z").getTime();
    const rangeStart = new Date("2026-04-01T00:00:00Z").getTime();
    const rangeEnd = new Date("2026-04-30T00:00:00Z").getTime();

    const instances = expandRecurrence(undefined, start, end, rangeStart, rangeEnd);
    expect(instances.length).toBe(1);
    expect(instances[0].start).toBe(start);
  });
});
```

- [ ] **Step 7: Run test to verify it fails**

Run: `cd functions && npx jest recurrence --detectOpenHandles 2>&1; cd ..`
Expected: FAIL

- [ ] **Step 8: Write recurrence utility**

```typescript
// functions/src/utils/recurrence.ts
import { RRule } from "rrule";
import { Interval } from "./overlap";

export function expandRecurrence(
  rruleStr: string | undefined | null,
  startMs: number,
  endMs: number,
  rangeStartMs: number,
  rangeEndMs: number
): Interval[] {
  const duration = endMs - startMs;

  if (!rruleStr) {
    if (startMs >= rangeStartMs && startMs < rangeEndMs) {
      return [{ start: startMs, end: endMs }];
    }
    return [];
  }

  const dtstart = new Date(startMs);
  const rule = RRule.fromString(`DTSTART:${formatRRuleDate(dtstart)}\n${rruleStr}`);

  const occurrences = rule.between(
    new Date(rangeStartMs),
    new Date(rangeEndMs),
    true
  );

  return occurrences.map((date) => ({
    start: date.getTime(),
    end: date.getTime() + duration,
  }));
}

function formatRRuleDate(d: Date): string {
  const pad = (n: number) => n.toString().padStart(2, "0");
  return (
    `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}` +
    `T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`
  );
}
```

- [ ] **Step 9: Run test to verify it passes**

Run: `cd functions && npx jest recurrence --detectOpenHandles 2>&1; cd ..`
Expected: All 3 tests PASS

- [ ] **Step 10: Commit**

```bash
git add functions/src/utils/ functions/src/__tests__/ functions/jest.config.js
git commit -m "feat: add overlap interval math and recurrence expansion with tests"
```

---

### Task 16: onBlockWrite Cloud Function

**Files:**
- Create: `functions/src/onBlockWrite.ts`
- Create: `functions/src/__tests__/onBlockWrite.test.ts`

- [ ] **Step 1: Write onBlockWrite**

```typescript
// functions/src/onBlockWrite.ts
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { DateTime } from "luxon";
import { mergeIntervals, invertIntervals, intersectIntervals, scoreWindow, Interval } from "./utils/overlap";
import { expandRecurrence } from "./utils/recurrence";
import * as crypto from "crypto";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export const onBlockWrite = onDocumentWritten(
  "timeblocks/{coupleId}/blocks/{blockId}",
  async (event) => {
    const coupleId = event.params.coupleId;

    // Debounce: wait 2 seconds for batch writes to settle
    await new Promise((resolve) => setTimeout(resolve, 2000));

    // Get couple doc
    const coupleDoc = await db.collection("couples").doc(coupleId).get();
    if (!coupleDoc.exists) return;
    const couple = coupleDoc.data()!;
    if (couple.status !== "active") return;

    // Get both users for timezones
    const [userADoc, userBDoc] = await Promise.all([
      db.collection("users").doc(couple.userAUid).get(),
      db.collection("users").doc(couple.userBUid).get(),
    ]);
    if (!userADoc.exists || !userBDoc.exists) return;

    const tzA = userADoc.data()!.timezone || "UTC";
    const tzB = userBDoc.data()!.timezone || "UTC";

    // 14-day horizon
    const now = Date.now();
    const horizonEnd = now + 14 * 24 * 60 * 60 * 1000;

    // Fetch all blocks for this couple
    const blocksSnap = await db
      .collection("timeblocks")
      .doc(coupleId)
      .collection("blocks")
      .get();

    const blocksA: Interval[] = [];
    const blocksB: Interval[] = [];

    for (const doc of blocksSnap.docs) {
      const data = doc.data();
      if (data.type === "free") continue; // Only merge busy/tentative

      const instances = expandRecurrence(
        data.recurrenceRule,
        data.startUtc,
        data.endUtc,
        now,
        horizonEnd
      );

      if (data.userId === couple.userAUid) {
        blocksA.push(...instances);
      } else {
        blocksB.push(...instances);
      }
    }

    // Compute hashes for change detection
    const hashA = crypto.createHash("md5").update(JSON.stringify(blocksA)).digest("hex");
    const hashB = crypto.createHash("md5").update(JSON.stringify(blocksB)).digest("hex");

    // Check existing overlap doc for hash match
    const overlapRef = db
      .collection("overlaps")
      .doc(coupleId)
      .collection("windows")
      .doc("latest");
    const existingOverlap = await overlapRef.get();
    if (existingOverlap.exists) {
      const existing = existingOverlap.data()!;
      if (existing.blockHashA === hashA && existing.blockHashB === hashB) {
        return; // No change
      }
    }

    // Merge busy intervals per partner
    const mergedA = mergeIntervals(blocksA);
    const mergedB = mergeIntervals(blocksB);

    // Invert to get free time
    const freeA = invertIntervals(mergedA, now, horizonEnd);
    const freeB = invertIntervals(mergedB, now, horizonEnd);

    // Intersect free intervals
    let mutual = intersectIntervals(freeA, freeB);

    // Clip to waking hours (7am-11pm in each partner's local time)
    mutual = clipToWakingHours(mutual, tzA, tzB);

    // Filter minimum 30 minutes
    mutual = mutual.filter((w) => (w.end - w.start) >= 30 * 60 * 1000);

    // Score and rank
    const scored = mutual.map((w) => {
      const durationMinutes = Math.round((w.end - w.start) / 60000);
      const midpoint = new Date((w.start + w.end) / 2);
      const localA = DateTime.fromJSDate(midpoint, { zone: tzA });
      const localB = DateTime.fromJSDate(midpoint, { zone: tzB });

      const inEvening = (dt: DateTime) => dt.hour >= 17 && dt.hour < 22;
      const bothEvening = inEvening(localA) && inEvening(localB);
      const oneEvening = inEvening(localA) || inEvening(localB);
      const isWeekend = localA.weekday >= 6 && localB.weekday >= 6;
      const reasonableBoth =
        localA.hour >= 7 && localA.hour < 23 &&
        localB.hour >= 7 && localB.hour < 23;
      const daysFromNow = Math.floor((w.start - now) / (24 * 60 * 60 * 1000));

      return {
        startUtc: w.start,
        endUtc: w.end,
        durationMinutes,
        score: scoreWindow(durationMinutes, bothEvening, oneEvening, isWeekend, reasonableBoth, daysFromNow),
        reasonableBoth,
      };
    });

    // Sort by score, take top 20
    scored.sort((a, b) => b.score - a.score);
    const top20 = scored.slice(0, 20);

    // Write result
    await overlapRef.set({
      windows: top20,
      computedAt: admin.firestore.FieldValue.serverTimestamp(),
      blockHashA: hashA,
      blockHashB: hashB,
    });
  }
);

function clipToWakingHours(
  intervals: Interval[],
  tzA: string,
  tzB: string
): Interval[] {
  const result: Interval[] = [];

  for (const interval of intervals) {
    // Walk through the interval in 30-minute chunks
    let cursor = interval.start;
    let segStart: number | null = null;

    while (cursor < interval.end) {
      const localA = DateTime.fromMillis(cursor, { zone: tzA });
      const localB = DateTime.fromMillis(cursor, { zone: tzB });

      const awakeA = localA.hour >= 7 && localA.hour < 23;
      const awakeB = localB.hour >= 7 && localB.hour < 23;

      if (awakeA && awakeB) {
        if (segStart === null) segStart = cursor;
      } else {
        if (segStart !== null) {
          result.push({ start: segStart, end: cursor });
          segStart = null;
        }
      }

      cursor += 15 * 60 * 1000; // 15-minute granularity
    }

    if (segStart !== null) {
      result.push({ start: segStart, end: interval.end });
    }
  }

  return result;
}
```

- [ ] **Step 2: Build and verify**

Run: `cd functions && npm run build 2>&1; cd ..`
Expected: Compiles without errors

- [ ] **Step 3: Commit**

```bash
git add functions/src/onBlockWrite.ts
git commit -m "feat: add onBlockWrite Cloud Function with overlap computation"
```

---

### Task 17: onOverlapWrite — FCM Push

**Files:**
- Create: `functions/src/onOverlapWrite.ts`

- [ ] **Step 1: Write onOverlapWrite**

```typescript
// functions/src/onOverlapWrite.ts
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import { DateTime } from "luxon";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export const onOverlapWrite = onDocumentWritten(
  "overlaps/{coupleId}/windows/latest",
  async (event) => {
    const coupleId = event.params.coupleId;
    const afterData = event.data?.after.data();
    const beforeData = event.data?.before.data();

    if (!afterData?.windows?.length) return;

    // Skip if hashes unchanged
    if (
      beforeData &&
      afterData.blockHashA === beforeData.blockHashA &&
      afterData.blockHashB === beforeData.blockHashB
    ) {
      return;
    }

    // Get couple doc
    const coupleDoc = await db.collection("couples").doc(coupleId).get();
    if (!coupleDoc.exists) return;
    const couple = coupleDoc.data()!;

    // Get both users
    const [userADoc, userBDoc] = await Promise.all([
      db.collection("users").doc(couple.userAUid).get(),
      db.collection("users").doc(couple.userBUid).get(),
    ]);

    const topWindow = afterData.windows[0];

    // Send notification to each partner in their timezone
    for (const userDoc of [userADoc, userBDoc]) {
      if (!userDoc.exists) continue;
      const userData = userDoc.data()!;
      const tokens: string[] = userData.fcmTokens || [];
      if (tokens.length === 0) continue;

      const tz = userData.timezone || "UTC";
      const windowStart = DateTime.fromMillis(topWindow.startUtc, { zone: tz });
      const dateStr = windowStart.toFormat("EEE, MMM d");
      const timeStr = windowStart.toFormat("h:mm a");
      const durationStr = `${topWindow.durationMinutes} min`;

      const message: admin.messaging.MulticastMessage = {
        tokens,
        notification: {
          title: "New free time found!",
          body: `${dateStr} at ${timeStr} for ${durationStr}`,
        },
        data: {
          coupleId,
          type: "new_overlap",
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);

      // Prune stale tokens
      const staleTokens: string[] = [];
      response.responses.forEach((resp, idx) => {
        if (resp.error?.code === "messaging/registration-token-not-registered") {
          staleTokens.push(tokens[idx]);
        }
      });

      if (staleTokens.length > 0) {
        await db.collection("users").doc(userDoc.id).update({
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...staleTokens),
        });
      }
    }
  }
);
```

- [ ] **Step 2: Build and verify**

Run: `cd functions && npm run build 2>&1; cd ..`
Expected: Compiles without errors

- [ ] **Step 3: Commit**

```bash
git add functions/src/onOverlapWrite.ts
git commit -m "feat: add onOverlapWrite Cloud Function for FCM push notifications"
```

---

### Task 18: redeemInvite, unpairCouple, onInviteCreate & cleanupInvites

**Files:**
- Create: `functions/src/redeemInvite.ts`
- Create: `functions/src/unpairCouple.ts`
- Create: `functions/src/onInviteCreate.ts`
- Create: `functions/src/cleanupInvites.ts`

- [ ] **Step 1: Write redeemInvite callable**

```typescript
// functions/src/redeemInvite.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export const redeemInvite = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const code = (request.data.code as string)?.toUpperCase().trim();
  if (!code || code.length !== 6) {
    throw new HttpsError("invalid-argument", "Invalid invite code");
  }

  const callerUid = request.auth.uid;

  // Get invite
  const inviteRef = db.collection("invites").doc(code);
  const inviteDoc = await inviteRef.get();
  if (!inviteDoc.exists) {
    throw new HttpsError("not-found", "Invite code not found");
  }

  const invite = inviteDoc.data()!;
  if (invite.status !== "pending") {
    throw new HttpsError("failed-precondition", "Invite already used or expired");
  }

  const expiresAt = invite.expiresAt.toDate ? invite.expiresAt.toDate() : new Date(invite.expiresAt);
  if (expiresAt < new Date()) {
    throw new HttpsError("failed-precondition", "Invite has expired");
  }

  if (invite.createdByUid === callerUid) {
    throw new HttpsError("failed-precondition", "Cannot pair with yourself");
  }

  // Verify neither user is already paired
  const [callerDoc, creatorDoc] = await Promise.all([
    db.collection("users").doc(callerUid).get(),
    db.collection("users").doc(invite.createdByUid).get(),
  ]);

  if (!callerDoc.exists || !creatorDoc.exists) {
    throw new HttpsError("not-found", "User not found");
  }

  if (callerDoc.data()!.coupleId) {
    throw new HttpsError("failed-precondition", "You are already paired");
  }
  if (creatorDoc.data()!.coupleId) {
    throw new HttpsError("failed-precondition", "Your partner is already paired");
  }

  // Create couple and update both users in a batch
  const coupleRef = db.collection("couples").doc();
  const coupleId = coupleRef.id;

  const batch = db.batch();

  batch.set(coupleRef, {
    userAUid: invite.createdByUid,
    userBUid: callerUid,
    status: "active",
    pairedAt: admin.firestore.FieldValue.serverTimestamp(),
    unpairHistory: [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  batch.update(db.collection("users").doc(invite.createdByUid), {
    coupleId,
  });

  batch.update(db.collection("users").doc(callerUid), {
    coupleId,
  });

  batch.update(inviteRef, {
    status: "accepted",
    coupleId,
  });

  await batch.commit();

  return { coupleId };
});
```

- [ ] **Step 2: Write unpairCouple callable**

```typescript
// functions/src/unpairCouple.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export const unpairCouple = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const callerUid = request.auth.uid;

  // Get user doc
  const userDoc = await db.collection("users").doc(callerUid).get();
  if (!userDoc.exists) throw new HttpsError("not-found", "User not found");

  const coupleId = userDoc.data()!.coupleId;
  if (!coupleId) throw new HttpsError("failed-precondition", "Not paired");

  // Get couple doc
  const coupleDoc = await db.collection("couples").doc(coupleId).get();
  if (!coupleDoc.exists) throw new HttpsError("not-found", "Couple not found");

  const couple = coupleDoc.data()!;
  const partnerUid = couple.userAUid === callerUid ? couple.userBUid : couple.userAUid;

  const batch = db.batch();

  // Set couple status to inactive, record in unpairHistory
  batch.update(coupleDoc.ref, {
    status: "inactive",
    unpairHistory: admin.firestore.FieldValue.arrayUnion([
      { at: admin.firestore.FieldValue.serverTimestamp(), reason: "user_initiated" },
    ]),
  });

  // Clear coupleId on both users
  batch.update(db.collection("users").doc(callerUid), { coupleId: null });
  batch.update(db.collection("users").doc(partnerUid), { coupleId: null });

  await batch.commit();

  return { success: true };
});
```

- [ ] **Step 4: Write onInviteCreate**

```typescript
// functions/src/onInviteCreate.ts
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export const onInviteCreate = onDocumentCreated(
  "invites/{code}",
  async (event) => {
    const code = event.params.code;
    const data = event.data?.data();
    if (!data) return;

    // Generate deep link URLs
    const customScheme = `coupleschedule://invite/${code}`;
    const httpsLink = `https://coupleschedule.app/invite/${code}`;

    await db.collection("invites").doc(code).update({
      deepLinkUrl: httpsLink,
    });
  }
);
```

- [ ] **Step 3: Write cleanupExpiredInvites**

```typescript
// functions/src/cleanupInvites.ts
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export const cleanupExpiredInvites = onSchedule(
  {
    schedule: "0 3 * * *", // Daily at 03:00 UTC
    timeZone: "UTC",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const expiredSnap = await db
      .collection("invites")
      .where("status", "==", "pending")
      .where("expiresAt", "<", now)
      .get();

    if (expiredSnap.empty) return;

    const batch = db.batch();
    for (const doc of expiredSnap.docs) {
      batch.update(doc.ref, { status: "expired" });
    }
    await batch.commit();
  }
);
```

- [ ] **Step 5: Build and verify**

Run: `cd functions && npm run build 2>&1; cd ..`
Expected: Compiles without errors

- [ ] **Step 6: Commit**

```bash
git add functions/src/redeemInvite.ts functions/src/unpairCouple.ts functions/src/onInviteCreate.ts functions/src/cleanupInvites.ts
git commit -m "feat: add redeemInvite, unpairCouple, onInviteCreate, and cleanup functions"
```

---

## Phase 6: Calendar Sync & Remaining Screens

### Task 19: Google Calendar Sync

**Files:**
- Create: `lib/services/calendar_service.dart`
- Create: `lib/services/providers/calendar_providers.dart`

- [ ] **Step 1: Write calendar service**

```dart
// lib/services/calendar_service.dart
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../core/models/models.dart';

class CalendarService {
  Future<List<TimeBlock>> fetchFreeBusy({
    required String accessToken,
    required String userId,
    required String timezone,
  }) async {
    final client = _AuthClient(accessToken);
    final calendarApi = gcal.CalendarApi(client);

    final now = DateTime.now().toUtc();
    final twoWeeksLater = now.add(const Duration(days: 14));

    final request = gcal.FreeBusyRequest(
      timeMin: now,
      timeMax: twoWeeksLater,
      items: [gcal.FreeBusyRequestItem(id: 'primary')],
    );

    final response = await calendarApi.freebusy.query(request);
    final busy = response.calendars?['primary']?.busy ?? [];

    return busy.map((period) {
      return TimeBlock(
        id: const Uuid().v4(),
        userId: userId,
        title: 'Calendar Event',
        type: BlockType.busy,
        category: BlockCategory.other,
        startUtc: period.start!.toUtc(),
        endUtc: period.end!.toUtc(),
        timezone: timezone,
        source: BlockSource.google,
        visibility: BlockVisibility.bothPartners,
        createdAt: DateTime.now().toUtc(),
      );
    }).toList();
  }
}

class _AuthClient extends http.BaseClient {
  final String _accessToken;
  final http.Client _inner = http.Client();

  _AuthClient(this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }
}
```

- [ ] **Step 2: Write calendar providers**

```dart
// lib/services/providers/calendar_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../calendar_service.dart';
import '../firestore_service.dart';
import '../auth_service.dart';
import 'auth_providers.dart';

final calendarServiceProvider = Provider<CalendarService>((ref) => CalendarService());

final calendarSyncProvider = Provider<CalendarSyncHelper>((ref) => CalendarSyncHelper(ref));

class CalendarSyncHelper {
  final Ref _ref;
  const CalendarSyncHelper(this._ref);

  Future<bool> syncGoogleCalendar() async {
    final user = _ref.read(currentUserProvider).valueOrNull;
    if (user?.coupleId == null) return false;

    final accessToken = await _ref.read(authServiceProvider).getGoogleAccessToken();
    if (accessToken == null) return false;

    final blocks = await _ref.read(calendarServiceProvider).fetchFreeBusy(
      accessToken: accessToken,
      userId: user!.uid,
      timezone: user.timezone,
    );

    final fs = _ref.read(firestoreServiceProvider);

    // Delete old google blocks, then write fresh ones
    await fs.deleteGoogleBlocks(user.coupleId!, user.uid);
    for (final block in blocks) {
      await fs.createBlock(user.coupleId!, block);
    }

    // Save last sync time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastCalendarSync', DateTime.now().millisecondsSinceEpoch);

    return true;
  }

  Future<bool> shouldAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt('lastCalendarSync') ?? 0;
    final oneHourAgo = DateTime.now().millisecondsSinceEpoch - (60 * 60 * 1000);
    return lastSync < oneHourAgo;
  }
}
```

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze lib/services/calendar_service.dart lib/services/providers/calendar_providers.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/services/calendar_service.dart lib/services/providers/calendar_providers.dart
git commit -m "feat: add Google Calendar freebusy sync service and providers"
```

---

### Task 20: Home Screen

**Files:**
- Modify: `lib/features/home/home_screen.dart`
- Create: `lib/features/home/widgets/timezone_clocks.dart`
- Create: `lib/features/home/widgets/next_window_card.dart`
- Create: `lib/services/providers/overlap_providers.dart`

- [ ] **Step 1: Write overlap providers**

```dart
// lib/services/providers/overlap_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/models.dart';
import 'auth_providers.dart';

final overlapProvider = StreamProvider<OverlapResult?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user?.coupleId == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchOverlaps(user!.coupleId!);
});
```

- [ ] **Step 2: Write timezone clocks widget**

```dart
// lib/features/home/widgets/timezone_clocks.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/utils/tz_helper.dart';
import '../../../core/theme/app_theme.dart';

class TimezoneClocks extends StatefulWidget {
  final String myTimezone;
  final String? partnerTimezone;
  final String? partnerName;

  const TimezoneClocks({
    super.key,
    required this.myTimezone,
    this.partnerTimezone,
    this.partnerName,
  });

  @override
  State<TimezoneClocks> createState() => _TimezoneClocksState();
}

class _TimezoneClocksState extends State<TimezoneClocks> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _ClockCard(
          label: 'Your time',
          timezone: widget.myTimezone,
          color: AppColors.yourBlock,
        )),
        const SizedBox(width: 12),
        if (widget.partnerTimezone != null)
          Expanded(child: _ClockCard(
            label: widget.partnerName ?? 'Partner',
            timezone: widget.partnerTimezone!,
            color: AppColors.partnerBlock,
          )),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _ClockCard extends StatelessWidget {
  final String label;
  final String timezone;
  final Color color;

  const _ClockCard({required this.label, required this.timezone, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              TzHelper.currentTimeIn(timezone),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold, color: color,
              ),
            ),
            Text(
              TzHelper.formatTimezoneOffset(timezone),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Write next window card widget**

```dart
// lib/features/home/widgets/next_window_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/tz_helper.dart';
import '../../../core/theme/app_theme.dart';

class NextWindowCard extends StatelessWidget {
  final OverlapWindow? window;
  final String myTimezone;
  final String? partnerTimezone;

  const NextWindowCard({
    super.key,
    required this.window,
    required this.myTimezone,
    this.partnerTimezone,
  });

  @override
  Widget build(BuildContext context) {
    if (window == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No free windows found yet')),
        ),
      );
    }

    final myStart = TzHelper.utcToLocal(window!.startUtc, myTimezone);
    final myEnd = TzHelper.utcToLocal(window!.endUtc, myTimezone);
    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat('h:mm a');

    final now = DateTime.now().toUtc();
    final diff = window!.startUtc.difference(now);
    String countdown;
    if (diff.inDays > 0) {
      countdown = 'in ${diff.inDays}d ${diff.inHours.remainder(24)}h';
    } else if (diff.inHours > 0) {
      countdown = 'in ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    } else if (diff.inMinutes > 0) {
      countdown = 'in ${diff.inMinutes}m';
    } else {
      countdown = 'now!';
    }

    return Card(
      color: AppColors.overlapHighlight.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Next Free Window', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(countdown, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(dateFmt.format(myStart), style: Theme.of(context).textTheme.bodyLarge),
            Text('${timeFmt.format(myStart)} — ${timeFmt.format(myEnd)} (${window!.durationMinutes} min)',
                style: Theme.of(context).textTheme.bodyMedium),
            if (partnerTimezone != null) ...[
              const SizedBox(height: 4),
              Text(
                '${timeFmt.format(TzHelper.utcToLocal(window!.startUtc, partnerTimezone!))} — ${timeFmt.format(TzHelper.utcToLocal(window!.endUtc, partnerTimezone!))} partner time',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement home screen**

```dart
// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/providers/auth_providers.dart';
import '../../services/providers/couple_providers.dart';
import '../../services/providers/overlap_providers.dart';
import '../../services/providers/calendar_providers.dart';
import 'widgets/timezone_clocks.dart';
import 'widgets/next_window_card.dart';
import '../../core/utils/tz_helper.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    _autoSync();
  }

  Future<void> _autoSync() async {
    final sync = ref.read(calendarSyncProvider);
    if (await sync.shouldAutoSync()) {
      await sync.syncGoogleCalendar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final partner = ref.watch(partnerProvider).valueOrNull;
    final overlap = ref.watch(overlapProvider).valueOrNull;
    final windows = overlap?.windows ?? [];
    final timeFmt = DateFormat('h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Couple Schedule'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () => context.push('/settings')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(calendarSyncProvider).syncGoogleCalendar(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (user != null)
              TimezoneClocks(
                myTimezone: user.timezone,
                partnerTimezone: partner?.timezone,
                partnerName: partner?.displayName,
              ),
            const SizedBox(height: 16),
            NextWindowCard(
              window: windows.isNotEmpty ? windows.first : null,
              myTimezone: user?.timezone ?? 'UTC',
              partnerTimezone: partner?.timezone,
            ),
            const SizedBox(height: 16),
            if (windows.length > 1) ...[
              Text('Upcoming', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...windows.skip(1).take(4).map((w) {
                final myStart = TzHelper.utcToLocal(w.startUtc, user?.timezone ?? 'UTC');
                return ListTile(
                  leading: Icon(Icons.schedule, color: AppColors.success),
                  title: Text(DateFormat('EEE, MMM d').format(myStart)),
                  subtitle: Text('${timeFmt.format(myStart)} · ${w.durationMinutes} min'),
                  trailing: Text('${w.score}', style: TextStyle(color: AppColors.textSecondary)),
                );
              }),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/blocks/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Block'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final synced = await ref.read(calendarSyncProvider).syncGoogleCalendar();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(synced ? 'Calendar synced' : 'Sync failed')),
                        );
                      }
                    },
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/overlaps'),
                    icon: const Icon(Icons.view_list),
                    label: const Text('All'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (i) {
          if (i == 1) context.push('/calendar');
          if (i == 2) context.push('/blocks');
          if (i == 3) context.push('/overlaps');
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Calendar'),
          NavigationDestination(icon: Icon(Icons.view_agenda), label: 'Blocks'),
          NavigationDestination(icon: Icon(Icons.schedule), label: 'Free Time'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run flutter analyze**

Run: `flutter analyze lib/features/home/ lib/services/providers/overlap_providers.dart`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/ lib/services/providers/overlap_providers.dart
git commit -m "feat: implement home screen with timezone clocks, overlap windows, and nav"
```

---

### Task 21: Calendar Week View

**Files:**
- Modify: `lib/features/calendar/week_view_screen.dart`

- [ ] **Step 1: Implement week view**

```dart
// lib/features/calendar/week_view_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/models/models.dart';
import '../../core/utils/tz_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../services/providers/auth_providers.dart';
import '../../services/providers/block_providers.dart';
import '../../services/providers/overlap_providers.dart';

class WeekViewScreen extends ConsumerStatefulWidget {
  const WeekViewScreen({super.key});

  @override
  ConsumerState<WeekViewScreen> createState() => _WeekViewScreenState();
}

class _WeekViewScreenState extends ConsumerState<WeekViewScreen> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
  }

  void _prevWeek() => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
  void _nextWeek() => setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final myBlocks = ref.watch(myBlocksProvider);
    final partnerBlocks = ref.watch(partnerBlocksProvider);
    final overlap = ref.watch(overlapProvider).valueOrNull;
    final tz = user?.timezone ?? 'UTC';
    final weekEnd = _weekStart.add(const Duration(days: 7));

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('MMM d').format(_weekStart)),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prevWeek),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextWeek),
        ],
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 7 * 120.0,
          child: Column(
            children: [
              // Day headers
              Row(
                children: List.generate(7, (i) {
                  final day = _weekStart.add(Duration(days: i));
                  final isToday = DateUtils.isSameDay(day, DateTime.now());
                  return SizedBox(
                    width: 120,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: isToday ? AppColors.primary.withValues(alpha: 0.1) : null,
                      child: Column(
                        children: [
                          Text(DateFormat('EEE').format(day),
                              style: TextStyle(fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                          Text(DateFormat('d').format(day)),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              const Divider(height: 1),
              // Blocks
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(7, (dayIdx) {
                    final day = _weekStart.add(Duration(days: dayIdx));
                    final dayBlocks = _blocksForDay(myBlocks, day, tz);
                    final dayPartner = _blocksForDay(partnerBlocks, day, tz);
                    final dayWindows = _windowsForDay(overlap?.windows ?? [], day, tz);

                    return SizedBox(
                      width: 120,
                      child: ListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          ...dayBlocks.map((b) => _BlockChip(block: b, color: AppColors.yourBlock, tz: tz)),
                          ...dayPartner.map((b) => _BlockChip(block: b, color: AppColors.partnerBlock, tz: tz)),
                          ...dayWindows.map((w) => _WindowChip(window: w, tz: tz)),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/blocks/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<TimeBlock> _blocksForDay(List<TimeBlock> blocks, DateTime day, String tz) {
    return blocks.where((b) {
      final local = TzHelper.utcToLocal(b.startUtc, tz);
      return local.year == day.year && local.month == day.month && local.day == day.day;
    }).toList()
      ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  }

  List<OverlapWindow> _windowsForDay(List<OverlapWindow> windows, DateTime day, String tz) {
    return windows.where((w) {
      final local = TzHelper.utcToLocal(w.startUtc, tz);
      return local.year == day.year && local.month == day.month && local.day == day.day;
    }).toList();
  }
}

class _BlockChip extends StatelessWidget {
  final TimeBlock block;
  final Color color;
  final String tz;

  const _BlockChip({required this.block, required this.color, required this.tz});

  @override
  Widget build(BuildContext context) {
    final start = TzHelper.utcToLocal(block.startUtc, tz);
    final timeFmt = DateFormat('h:mm a');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${timeFmt.format(start)}\n${block.title}',
        style: const TextStyle(fontSize: 10),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _WindowChip extends StatelessWidget {
  final OverlapWindow window;
  final String tz;

  const _WindowChip({required this.window, required this.tz});

  @override
  Widget build(BuildContext context) {
    final start = TzHelper.utcToLocal(window.startUtc, tz);
    final timeFmt = DateFormat('h:mm a');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.overlapHighlight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.success, width: 1),
      ),
      child: Text(
        '${timeFmt.format(start)}\n${window.durationMinutes}m free',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        maxLines: 2,
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/features/calendar/`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/features/calendar/week_view_screen.dart
git commit -m "feat: implement calendar week view with blocks and overlap highlights"
```

---

### Task 22: Overlap Screen

**Files:**
- Modify: `lib/features/overlap/overlap_screen.dart`

- [ ] **Step 1: Implement overlap screen**

```dart
// lib/features/overlap/overlap_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/models.dart';
import '../../core/utils/tz_helper.dart';
import '../../core/theme/app_theme.dart';
import '../../services/providers/auth_providers.dart';
import '../../services/providers/couple_providers.dart';
import '../../services/providers/overlap_providers.dart';

class OverlapScreen extends ConsumerStatefulWidget {
  const OverlapScreen({super.key});

  @override
  ConsumerState<OverlapScreen> createState() => _OverlapScreenState();
}

class _OverlapScreenState extends ConsumerState<OverlapScreen> {
  int? _minMinutes;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final partner = ref.watch(partnerProvider).valueOrNull;
    final overlap = ref.watch(overlapProvider).valueOrNull;
    var windows = overlap?.windows ?? [];
    final tz = user?.timezone ?? 'UTC';
    final partnerTz = partner?.timezone;

    if (_minMinutes != null) {
      windows = windows.where((w) => w.durationMinutes >= _minMinutes!).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Free Windows'),
        actions: [
          PopupMenuButton<int?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() => _minMinutes = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Any duration')),
              const PopupMenuItem(value: 30, child: Text('30+ min')),
              const PopupMenuItem(value: 60, child: Text('1+ hour')),
              const PopupMenuItem(value: 120, child: Text('2+ hours')),
            ],
          ),
        ],
      ),
      body: windows.isEmpty
          ? const Center(child: Text('No free windows found'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: windows.length,
              itemBuilder: (context, index) {
                final w = windows[index];
                final myStart = TzHelper.utcToLocal(w.startUtc, tz);
                final myEnd = TzHelper.utcToLocal(w.endUtc, tz);
                final dateFmt = DateFormat('EEE, MMM d');
                final timeFmt = DateFormat('h:mm a');

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(dateFmt.format(myStart),
                                style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Score: ${w.score}',
                                  style: TextStyle(color: AppColors.primary, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.schedule, size: 16, color: AppColors.yourBlock),
                            const SizedBox(width: 4),
                            Text('${timeFmt.format(myStart)} — ${timeFmt.format(myEnd)}'),
                            const SizedBox(width: 8),
                            Text('${w.durationMinutes} min',
                                style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                        if (partnerTz != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 16, color: AppColors.partnerBlock),
                              const SizedBox(width: 4),
                              Text(
                                '${timeFmt.format(TzHelper.utcToLocal(w.startUtc, partnerTz))} — ${timeFmt.format(TzHelper.utcToLocal(w.endUtc, partnerTz))} partner',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                        if (w.reasonableBoth)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, size: 14, color: AppColors.success),
                                const SizedBox(width: 4),
                                Text('Both in waking hours',
                                    style: TextStyle(color: AppColors.success, fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/features/overlap/`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/features/overlap/overlap_screen.dart
git commit -m "feat: implement overlap screen with duration filter and dual timezone display"
```

---

### Task 23: Settings Screen

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`

- [ ] **Step 1: Implement settings screen**

```dart
// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../services/providers/auth_providers.dart';
import '../../services/providers/couple_providers.dart';
import '../../services/providers/calendar_providers.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final partner = ref.watch(partnerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Calendar
          const _SectionHeader('Calendar'),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync Google Calendar'),
            subtitle: const Text('Tap to sync now'),
            onTap: () async {
              final synced = await ref.read(calendarSyncProvider).syncGoogleCalendar();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(synced ? 'Synced successfully' : 'Sync failed — sign in with Google first')),
                );
              }
            },
          ),

          // Timezone
          const _SectionHeader('Timezone'),
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(user?.timezone ?? 'Not set'),
            subtitle: const Text('Tap to change'),
            onTap: () => context.push('/timezone-setup'),
          ),

          // Routine
          const _SectionHeader('Routine'),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Re-run Routine Setup'),
            onTap: () => context.push('/routine-setup'),
          ),

          // Couple
          const _SectionHeader('Partner'),
          if (partner != null) ...[
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(partner.displayName),
              subtitle: Text(partner.timezone),
            ),
            ListTile(
              leading: Icon(Icons.link_off, color: AppColors.error),
              title: Text('Unpair', style: TextStyle(color: AppColors.error)),
              onTap: () => _showUnpairDialog(context, ref),
            ),
          ],

          // Account
          const _SectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign Out'),
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
            },
          ),
        ],
      ),
    );
  }

  void _showUnpairDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair?'),
        content: const Text('This will disconnect you from your partner. You can re-pair later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final callable = FirebaseFunctions.instance.httpsCallable('unpairCouple');
                await callable.call();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: Text('Unpair', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.textSecondary)),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

Run: `flutter analyze lib/features/settings/`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/features/settings/settings_screen.dart
git commit -m "feat: implement settings screen with calendar sync, timezone, and unpair"
```

---

## Phase 7: Notifications & Deployment

### Task 24: Notification Service & FCM

**Files:**
- Create: `lib/services/notification_service.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Write notification service**

```dart
// lib/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    // Request permission
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get and save FCM token
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(token);

    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_saveToken);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      // For v1, we rely on system notification display
      // No custom handling needed
    });
  }

  Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }
}
```

- [ ] **Step 2: Update main.dart to initialize notifications**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'firebase_options.dart';
import 'app.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  tz.initializeTimeZones();
  await NotificationService().initialize();
  runApp(const ProviderScope(child: CoupleScheduleApp()));
}
```

- [ ] **Step 3: Run flutter analyze**

Run: `flutter analyze lib/services/notification_service.dart lib/main.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/services/notification_service.dart lib/main.dart
git commit -m "feat: add FCM notification service with token registration"
```

---

### Task 25: Deploy & Smoke Test

**Files:**
- No new files

- [ ] **Step 1: Build Cloud Functions**

Run: `cd functions && npm run build 2>&1; cd ..`
Expected: No TypeScript errors

- [ ] **Step 2: Run Cloud Functions tests**

Run: `cd functions && npx jest --detectOpenHandles 2>&1; cd ..`
Expected: All tests pass

- [ ] **Step 3: Run Flutter tests**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 4: Run Flutter analyze**

Run: `flutter analyze`
Expected: No errors

- [ ] **Step 5: Deploy Firestore rules and indexes**

Run: `firebase deploy --only firestore:rules,firestore:indexes --project=nexion-ai-prod`

- [ ] **Step 6: Deploy Cloud Functions**

Run: `firebase deploy --only functions --project=nexion-ai-prod`

- [ ] **Step 7: Build Flutter debug APK**

Run: `flutter build apk --debug`
Expected: Build succeeds

- [ ] **Step 8: Commit any final adjustments**

```bash
git add -A
git commit -m "chore: final polish and deployment verification"
```

---

## Summary

| Phase | Tasks | What it delivers |
|-------|-------|-----------------|
| 1. Infrastructure | 1–2 | Firebase project + Flutter scaffold |
| 2. Data Models | 3 | 5 models with tests (16 tests) |
| 3. Services | 4–7 | Firestore service, auth, security rules, router |
| 4. Feature Screens | 8–13 | Auth, timezone, pairing, blocks, routine wizard |
| 5. Cloud Functions | 14–18 | Overlap engine, FCM push, invite system |
| 6. Remaining Screens | 19–22 | Calendar sync, home, week view, overlap list |
| 7. Settings & Deploy | 23–25 | Settings, notifications, deployment |

**Total:** 25 tasks, ~100 steps
