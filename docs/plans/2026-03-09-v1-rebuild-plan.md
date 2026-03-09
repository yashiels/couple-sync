# Couple Schedule v1 Rebuild — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the Couple Schedule app from scratch with working end-to-end functionality — auth, pairing, calendar sync, overlap computation, and notifications.

**Architecture:** Flutter + Firebase (Auth, Firestore, Cloud Functions v2, FCM). Riverpod for state. go_router for navigation. Server-side overlap computation via Cloud Functions triggered on block writes. All times stored in UTC.

**Tech Stack:** Flutter/Dart 3.11+, Firebase, Riverpod, go_router, Google Sign-In, googleapis, Luxon (Cloud Functions), timezone (Flutter)

---

## Phase 1: Foundation

### Task 1: Project Scaffold & Dependencies

**Files:**
- Modify: `pubspec.yaml`
- Delete: All files in `lib/` (replace with clean structure)
- Create: `lib/main.dart`

**Step 1: Clean the lib directory**

Delete everything in `lib/` except `firebase_options.dart`. Create the folder structure:

```
lib/
├── main.dart
├── firebase_options.dart  (keep existing)
├── app.dart
├── core/
│   ├── models/
│   ├── theme/
│   ├── router/
│   └── utils/
├── features/
│   ├── auth/
│   ├── onboarding/
│   ├── pairing/
│   ├── home/
│   ├── calendar/
│   ├── blocks/
│   ├── overlap/
│   └── settings/
└── services/
    └── providers/
```

**Step 2: Update pubspec.yaml**

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
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.0
  firebase_messaging: ^15.1.3
  cloud_firestore: ^5.4.4

  # Google / Apple Sign-In
  google_sign_in: ^6.2.1
  sign_in_with_apple: ^6.1.0
  googleapis: ^13.1.0
  http: ^1.2.2

  # Local notifications
  flutter_local_notifications: ^18.0.1

  # State management
  flutter_riverpod: ^2.6.1

  # Persistence
  shared_preferences: ^2.3.3
  uuid: ^4.5.3
  timezone: ^0.9.4

  # Fonts
  google_fonts: ^6.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

**Step 3: Write minimal main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  tz.initializeTimeZones();
  runApp(const ProviderScope(child: CoupleScheduleApp()));
}

class CoupleScheduleApp extends StatelessWidget {
  const CoupleScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Couple Schedule',
      home: Scaffold(body: Center(child: Text('Couple Schedule'))),
    );
  }
}
```

**Step 4: Verify it builds**

Run: `flutter analyze && flutter build apk --debug 2>&1 | tail -5`
Expected: No analysis errors, build succeeds

**Step 5: Commit**

```bash
git add lib/ pubspec.yaml
git commit -m "feat: clean project scaffold for v1 rebuild"
```

---

### Task 2: Data Models

**Files:**
- Create: `lib/core/models/user_model.dart`
- Create: `lib/core/models/couple_model.dart`
- Create: `lib/core/models/invite_model.dart`
- Create: `lib/core/models/time_block_model.dart`
- Create: `lib/core/models/overlap_result_model.dart`
- Create: `lib/core/models/models.dart` (barrel export)
- Test: `test/core/models/user_model_test.dart`
- Test: `test/core/models/time_block_model_test.dart`
- Test: `test/core/models/overlap_result_model_test.dart`

**Step 1: Write UserModel tests**

```dart
// test/core/models/user_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/core/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('fromFirestore creates model from map', () {
      final data = {
        'email': 'test@example.com',
        'displayName': 'Test User',
        'photoUrl': null,
        'timezone': 'America/New_York',
        'coupleId': null,
        'fcmTokens': <String>[],
        'createdAt': 1709000000000,
      };
      final user = UserModel.fromMap('uid123', data);
      expect(user.uid, 'uid123');
      expect(user.email, 'test@example.com');
      expect(user.timezone, 'America/New_York');
      expect(user.coupleId, isNull);
    });

    test('toMap serializes correctly', () {
      final user = UserModel(
        uid: 'uid123',
        email: 'test@example.com',
        displayName: 'Test User',
        timezone: 'America/New_York',
        createdAt: DateTime.utc(2024, 1, 1),
      );
      final map = user.toMap();
      expect(map['email'], 'test@example.com');
      expect(map['timezone'], 'America/New_York');
      expect(map.containsKey('uid'), false); // uid is the doc ID, not a field
    });

    test('defaults timezone to UTC if missing', () {
      final user = UserModel.fromMap('uid1', {'email': 'a@b.com', 'displayName': 'A'});
      expect(user.timezone, 'UTC');
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/core/models/user_model_test.dart`
Expected: FAIL — cannot find user_model.dart

**Step 3: Implement UserModel**

```dart
// lib/core/models/user_model.dart
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String timezone;
  final String? coupleId;
  final List<String> fcmTokens;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.timezone = 'UTC',
    this.coupleId,
    this.fcmTokens = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? const _DefaultNow();

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      timezone: data['timezone'] as String? ?? 'UTC',
      coupleId: data['coupleId'] as String?,
      fcmTokens: List<String>.from(data['fcmTokens'] ?? []),
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int)
          : DateTime.now(),
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
      'createdAt': createdAt.millisecondsSinceEpoch,
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
}

// Sentinel for const default
class _DefaultNow implements DateTime {
  const _DefaultNow();
  @override
  dynamic noSuchMethod(Invocation invocation) => DateTime.now().noSuchMethod(invocation);
}
```

Note: The `_DefaultNow` trick won't work cleanly. Simplify — just use a nullable with `??` in the constructor body:

```dart
// lib/core/models/user_model.dart
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
    this.timezone = 'UTC',
    this.coupleId,
    this.fcmTokens = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      timezone: data['timezone'] as String? ?? 'UTC',
      coupleId: data['coupleId'] as String?,
      fcmTokens: List<String>.from(data['fcmTokens'] ?? []),
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int)
          : DateTime.now(),
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
      'createdAt': createdAt.millisecondsSinceEpoch,
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
}
```

**Step 4: Implement CoupleModel**

```dart
// lib/core/models/couple_model.dart
class CoupleModel {
  final String coupleId;
  final String userAUid;
  final String userBUid;
  final String status; // 'active' or 'inactive'
  final DateTime pairedAt;
  final List<Map<String, dynamic>> unpairHistory;
  final DateTime createdAt;

  CoupleModel({
    required this.coupleId,
    required this.userAUid,
    required this.userBUid,
    this.status = 'active',
    DateTime? pairedAt,
    this.unpairHistory = const [],
    DateTime? createdAt,
  })  : pairedAt = pairedAt ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  factory CoupleModel.fromMap(String id, Map<String, dynamic> data) {
    return CoupleModel(
      coupleId: id,
      userAUid: data['userAUid'] as String,
      userBUid: data['userBUid'] as String,
      status: data['status'] as String? ?? 'active',
      pairedAt: data['pairedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['pairedAt'] as int)
          : DateTime.now(),
      unpairHistory: List<Map<String, dynamic>>.from(data['unpairHistory'] ?? []),
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userAUid': userAUid,
      'userBUid': userBUid,
      'status': status,
      'pairedAt': pairedAt.millisecondsSinceEpoch,
      'unpairHistory': unpairHistory,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  String partnerUid(String myUid) =>
      myUid == userAUid ? userBUid : userAUid;

  bool get isActive => status == 'active';
}
```

**Step 5: Implement InviteModel**

```dart
// lib/core/models/invite_model.dart
enum InviteStatus { pending, accepted, expired }

class InviteModel {
  final String code;
  final String createdByUid;
  final String? coupleId;
  final DateTime expiresAt;
  final InviteStatus status;
  final String? deepLinkUrl;

  InviteModel({
    required this.code,
    required this.createdByUid,
    this.coupleId,
    required this.expiresAt,
    this.status = InviteStatus.pending,
    this.deepLinkUrl,
  });

  factory InviteModel.fromMap(Map<String, dynamic> data) {
    return InviteModel(
      code: data['code'] as String,
      createdByUid: data['createdByUid'] as String,
      coupleId: data['coupleId'] as String?,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(data['expiresAt'] as int),
      status: InviteStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => InviteStatus.pending,
      ),
      deepLinkUrl: data['deepLinkUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'createdByUid': createdByUid,
      'coupleId': coupleId,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'status': status.name,
      'deepLinkUrl': deepLinkUrl,
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
```

**Step 6: Implement TimeBlockModel**

```dart
// lib/core/models/time_block_model.dart
enum BlockType { busy, free, tentative }
enum BlockCategory { work, study, commute, exercise, social, meals, sleep, personal, other }
enum BlockSource { google, manual }
enum BlockVisibility { bothPartners, onlyMe }

class TimeBlockModel {
  final String id;
  final String userId;
  final String title;
  final BlockType type;
  final BlockCategory category;
  final int startUtc; // milliseconds since epoch
  final int endUtc;
  final String timezone;
  final String? recurrenceRule;
  final BlockSource source;
  final BlockVisibility visibility;
  final DateTime createdAt;

  TimeBlockModel({
    required this.id,
    required this.userId,
    required this.title,
    this.type = BlockType.busy,
    this.category = BlockCategory.other,
    required this.startUtc,
    required this.endUtc,
    required this.timezone,
    this.recurrenceRule,
    this.source = BlockSource.manual,
    this.visibility = BlockVisibility.bothPartners,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TimeBlockModel.fromMap(String id, Map<String, dynamic> data) {
    return TimeBlockModel(
      id: id,
      userId: data['userId'] as String,
      title: data['title'] as String? ?? '',
      type: BlockType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => BlockType.busy,
      ),
      category: BlockCategory.values.firstWhere(
        (e) => e.name == data['category'],
        orElse: () => BlockCategory.other,
      ),
      startUtc: data['startUtc'] as int,
      endUtc: data['endUtc'] as int,
      timezone: data['timezone'] as String? ?? 'UTC',
      recurrenceRule: data['recurrenceRule'] as String?,
      source: BlockSource.values.firstWhere(
        (e) => e.name == data['source'],
        orElse: () => BlockSource.manual,
      ),
      visibility: BlockVisibility.values.firstWhere(
        (e) => e.name == data['visibility'],
        orElse: () => BlockVisibility.bothPartners,
      ),
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'type': type.name,
      'category': category.name,
      'startUtc': startUtc,
      'endUtc': endUtc,
      'timezone': timezone,
      'recurrenceRule': recurrenceRule,
      'source': source.name,
      'visibility': visibility.name,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  TimeBlockModel copyWith({
    String? title,
    BlockType? type,
    BlockCategory? category,
    int? startUtc,
    int? endUtc,
    String? timezone,
    String? recurrenceRule,
    BlockVisibility? visibility,
  }) {
    return TimeBlockModel(
      id: id,
      userId: userId,
      title: title ?? this.title,
      type: type ?? this.type,
      category: category ?? this.category,
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      timezone: timezone ?? this.timezone,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      source: source,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt,
    );
  }

  int get durationMinutes => (endUtc - startUtc) ~/ 60000;
}
```

**Step 7: Implement OverlapResultModel**

```dart
// lib/core/models/overlap_result_model.dart
class OverlapWindow {
  final int startUtc;
  final int endUtc;
  final int durationMinutes;
  final double score;
  final bool reasonableBoth;

  const OverlapWindow({
    required this.startUtc,
    required this.endUtc,
    required this.durationMinutes,
    required this.score,
    required this.reasonableBoth,
  });

  factory OverlapWindow.fromMap(Map<String, dynamic> data) {
    return OverlapWindow(
      startUtc: data['startUtc'] as int,
      endUtc: data['endUtc'] as int,
      durationMinutes: data['durationMinutes'] as int,
      score: (data['score'] as num).toDouble(),
      reasonableBoth: data['reasonableBoth'] as bool? ?? false,
    );
  }
}

class OverlapResult {
  final String coupleId;
  final List<OverlapWindow> windows;
  final DateTime computedAt;

  const OverlapResult({
    required this.coupleId,
    required this.windows,
    required this.computedAt,
  });

  factory OverlapResult.fromMap(String coupleId, Map<String, dynamic> data) {
    final windowsList = (data['windows'] as List<dynamic>?)
        ?.map((w) => OverlapWindow.fromMap(w as Map<String, dynamic>))
        .toList() ?? [];
    return OverlapResult(
      coupleId: coupleId,
      windows: windowsList,
      computedAt: data['computedAt'] != null
          ? (data['computedAt'] as dynamic).toDate()
          : DateTime.now(),
    );
  }

  OverlapWindow? get topWindow => windows.isNotEmpty ? windows.first : null;
}
```

**Step 8: Create barrel export**

```dart
// lib/core/models/models.dart
export 'user_model.dart';
export 'couple_model.dart';
export 'invite_model.dart';
export 'time_block_model.dart';
export 'overlap_result_model.dart';
```

**Step 9: Run tests**

Run: `flutter test test/core/models/`
Expected: All pass

**Step 10: Commit**

```bash
git add lib/core/models/ test/core/models/
git commit -m "feat: add clean data models for v1 rebuild"
```

---

### Task 3: Firestore Security Rules

**Files:**
- Modify: `firestore.rules`

**Step 1: Write updated security rules**

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isCoupleMemeber(coupleId) {
      let couple = get(/databases/$(database)/documents/couples/$(coupleId)).data;
      return request.auth.uid == couple.userAUid || request.auth.uid == couple.userBUid;
    }

    // Users
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;

      // Partner can read (shared coupleId)
      allow read: if request.auth != null
        && exists(/databases/$(database)/documents/users/$(request.auth.uid))
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.coupleId != null
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.coupleId ==
           get(/databases/$(database)/documents/users/$(userId)).data.coupleId;

      // Pairing batch: any auth user can set coupleId only
      allow update: if request.auth != null
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['coupleId']);
    }

    // Couples
    match /couples/{coupleId} {
      allow read: if request.auth != null && isCoupleMemeber(coupleId);
      allow create: if request.auth != null
        && (request.resource.data.userAUid == request.auth.uid
            || request.resource.data.userBUid == request.auth.uid);
      allow update, delete: if request.auth != null && isCoupleMemeber(coupleId);
    }

    // Time blocks
    match /timeblocks/{coupleId}/blocks/{blockId} {
      allow read, write: if request.auth != null && isCoupleMemeber(coupleId);
    }

    // Overlaps (Cloud Functions write only)
    match /overlaps/{coupleId}/{document=**} {
      allow read: if request.auth != null && isCoupleMemeber(coupleId);
      allow write: if false;
    }

    // Invites
    match /invites/{code} {
      allow read: if request.auth != null;
      allow create: if request.auth != null
        && request.resource.data.createdByUid == request.auth.uid;
      allow update: if request.auth != null;
    }
  }
}
```

**Step 2: Deploy rules**

Run: `firebase deploy --only firestore:rules`
Expected: Deploy succeeds

**Step 3: Commit**

```bash
git add firestore.rules
git commit -m "feat: clean Firestore security rules for v1"
```

---

## Phase 2: Services Layer

### Task 4: Auth Service

**Files:**
- Create: `lib/services/auth_service.dart`
- Create: `lib/services/providers/auth_providers.dart`
- Test: `test/services/auth_service_test.dart`

**Step 1: Write auth service**

```dart
// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:couple_schedule/core/models/models.dart';

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final GoogleSignIn? _googleSignIn;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel> signInWithGoogle() async {
    final googleUser = await _googleSignIn?.signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user!;
    return _getOrCreateUser(user);
  }

  Future<UserModel> signInWithApple() async {
    final appleProvider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final userCredential = await _auth.signInWithProvider(appleProvider);
    final user = userCredential.user!;
    return _getOrCreateUser(user);
  }

  Future<UserModel> _getOrCreateUser(User user) async {
    final doc = await _db.collection('users').doc(user.uid).get();
    if (doc.exists) {
      return UserModel.fromMap(user.uid, doc.data()!);
    }

    final newUser = UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? '',
      photoUrl: user.photoURL,
    );
    await _db.collection('users').doc(user.uid).set(newUser.toMap());
    return newUser;
  }

  Future<UserModel?> fetchUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(uid, doc.data()!);
  }

  Future<CoupleModel?> fetchCoupleForUser(String uid) async {
    var query = await _db.collection('couples')
        .where('userAUid', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      query = await _db.collection('couples')
          .where('userBUid', isEqualTo: uid)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
    }

    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    return CoupleModel.fromMap(doc.id, doc.data());
  }

  Future<void> updateTimezone(String uid, String timezone) async {
    await _db.collection('users').doc(uid).update({'timezone': timezone});
  }

  Future<void> signOut() async {
    await _googleSignIn?.signOut();
    await _auth.signOut();
  }
}
```

**Step 2: Write auth providers**

```dart
// lib/services/providers/auth_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:couple_schedule/core/models/models.dart';
import 'package:couple_schedule/services/auth_service.dart';

final googleSignInProvider = Provider<GoogleSignIn?>(
  (_) => GoogleSignIn(scopes: ['email']),
);

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(googleSignIn: ref.read(googleSignInProvider));
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.read(authServiceProvider).authStateChanges;
});

final currentUserProvider = StateProvider<UserModel?>((ref) => null);
final currentCoupleProvider = StateProvider<CoupleModel?>((ref) => null);
final hydrationCompleteProvider = StateProvider<bool>((ref) => false);
```

**Step 3: Run analyze**

Run: `flutter analyze`
Expected: No errors

**Step 4: Commit**

```bash
git add lib/services/ test/services/
git commit -m "feat: add auth service and providers"
```

---

### Task 5: Pairing Service

**Files:**
- Create: `lib/services/pairing_service.dart`
- Create: `lib/services/providers/pairing_providers.dart`
- Test: `test/services/pairing_service_test.dart`

**Step 1: Write pairing service**

```dart
// lib/services/pairing_service.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_schedule/core/models/models.dart';
import 'package:uuid/uuid.dart';

class PairingService {
  final FirebaseFirestore _db;
  static const _uuid = Uuid();

  PairingService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/1/O/0 confusion
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<InviteModel> generateInviteCode(String uid) async {
    // Check user not already in active couple
    final userDoc = await _db.collection('users').doc(uid).get();
    if (userDoc.exists && userDoc.data()?['coupleId'] != null) {
      throw Exception('Already in a couple');
    }

    final code = _generateCode();
    final invite = InviteModel(
      code: code,
      createdByUid: uid,
      expiresAt: DateTime.now().add(const Duration(hours: 48)),
    );
    await _db.collection('invites').doc(code).set(invite.toMap());
    return invite;
  }

  Future<InviteModel?> getActiveInviteForUser(String uid) async {
    final query = await _db.collection('invites')
        .where('createdByUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    final invite = InviteModel.fromMap(query.docs.first.data());
    if (invite.isExpired) return null;
    return invite;
  }

  Future<CoupleModel> redeemInviteCode(String code, String redeemerUid) async {
    final inviteDoc = await _db.collection('invites').doc(code).get();
    if (!inviteDoc.exists) throw Exception('Invalid code');

    final invite = InviteModel.fromMap(inviteDoc.data()!);
    if (invite.isExpired) throw Exception('Code expired');
    if (invite.status != InviteStatus.pending) throw Exception('Code already used');
    if (invite.createdByUid == redeemerUid) throw Exception('Cannot use your own code');

    // Check for existing inactive couple between these two users (re-pairing)
    final existingCouple = await _findInactiveCouple(invite.createdByUid, redeemerUid);

    final batch = _db.batch();

    CoupleModel couple;
    if (existingCouple != null) {
      // Reactivate existing couple
      couple = CoupleModel(
        coupleId: existingCouple.coupleId,
        userAUid: existingCouple.userAUid,
        userBUid: existingCouple.userBUid,
        status: 'active',
        pairedAt: DateTime.now(),
        unpairHistory: existingCouple.unpairHistory,
        createdAt: existingCouple.createdAt,
      );
      batch.update(
        _db.collection('couples').doc(existingCouple.coupleId),
        {'status': 'active', 'pairedAt': DateTime.now().millisecondsSinceEpoch},
      );
    } else {
      // Create new couple
      final coupleId = _uuid.v4();
      couple = CoupleModel(
        coupleId: coupleId,
        userAUid: invite.createdByUid,
        userBUid: redeemerUid,
      );
      batch.set(_db.collection('couples').doc(coupleId), couple.toMap());
    }

    // Update both users' coupleId
    batch.update(_db.collection('users').doc(invite.createdByUid),
        {'coupleId': couple.coupleId});
    batch.update(_db.collection('users').doc(redeemerUid),
        {'coupleId': couple.coupleId});

    // Mark invite as accepted
    batch.update(_db.collection('invites').doc(code), {
      'status': 'accepted',
      'coupleId': couple.coupleId,
    });

    await batch.commit();
    return couple;
  }

  Future<CoupleModel?> _findInactiveCouple(String uidA, String uidB) async {
    // Check both orderings
    var query = await _db.collection('couples')
        .where('userAUid', isEqualTo: uidA)
        .where('userBUid', isEqualTo: uidB)
        .where('status', isEqualTo: 'inactive')
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      query = await _db.collection('couples')
          .where('userAUid', isEqualTo: uidB)
          .where('userBUid', isEqualTo: uidA)
          .where('status', isEqualTo: 'inactive')
          .limit(1)
          .get();
    }

    if (query.docs.isEmpty) return null;
    return CoupleModel.fromMap(query.docs.first.id, query.docs.first.data());
  }

  Future<void> unpair(CoupleModel couple) async {
    final batch = _db.batch();

    // Soft delete — set status to inactive
    batch.update(_db.collection('couples').doc(couple.coupleId), {
      'status': 'inactive',
      'unpairHistory': FieldValue.arrayUnion([
        {'at': DateTime.now().millisecondsSinceEpoch, 'reason': 'user_initiated'},
      ]),
    });

    // Clear both users' coupleId
    batch.update(_db.collection('users').doc(couple.userAUid), {'coupleId': null});
    batch.update(_db.collection('users').doc(couple.userBUid), {'coupleId': null});

    await batch.commit();
  }

  Stream<CoupleModel?> watchCouple(String coupleId) {
    return _db.collection('couples').doc(coupleId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return CoupleModel.fromMap(snap.id, snap.data()!);
    });
  }
}
```

**Step 2: Write pairing providers**

```dart
// lib/services/providers/pairing_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:couple_schedule/services/pairing_service.dart';

final pairingServiceProvider = Provider<PairingService>((_) => PairingService());
```

**Step 3: Run analyze**

Run: `flutter analyze`
Expected: No errors

**Step 4: Commit**

```bash
git add lib/services/pairing_service.dart lib/services/providers/pairing_providers.dart
git commit -m "feat: add pairing service with re-pairing support"
```

---

### Task 6: Block Service

**Files:**
- Create: `lib/services/block_service.dart`
- Create: `lib/services/providers/block_providers.dart`

**Step 1: Write block service**

```dart
// lib/services/block_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_schedule/core/models/models.dart';
import 'package:uuid/uuid.dart';

class BlockService {
  final FirebaseFirestore _db;
  static const _uuid = Uuid();

  BlockService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _blocksRef(String coupleId) =>
      _db.collection('timeblocks').doc(coupleId).collection('blocks');

  Future<TimeBlockModel> createBlock({
    required String coupleId,
    required String userId,
    required String title,
    required BlockType type,
    required BlockCategory category,
    required int startUtc,
    required int endUtc,
    required String timezone,
    String? recurrenceRule,
    BlockSource source = BlockSource.manual,
    BlockVisibility visibility = BlockVisibility.bothPartners,
  }) async {
    final id = _uuid.v4();
    final block = TimeBlockModel(
      id: id,
      userId: userId,
      title: title,
      type: type,
      category: category,
      startUtc: startUtc,
      endUtc: endUtc,
      timezone: timezone,
      recurrenceRule: recurrenceRule,
      source: source,
      visibility: visibility,
    );
    await _blocksRef(coupleId).doc(id).set(block.toMap());
    return block;
  }

  Future<void> updateBlock(String coupleId, TimeBlockModel block) async {
    await _blocksRef(coupleId).doc(block.id).update(block.toMap());
  }

  Future<void> deleteBlock(String coupleId, String blockId) async {
    await _blocksRef(coupleId).doc(blockId).delete();
  }

  Stream<List<TimeBlockModel>> watchBlocks(String coupleId) {
    return _blocksRef(coupleId)
        .orderBy('startUtc')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => TimeBlockModel.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<TimeBlockModel>> watchUserBlocks(String coupleId, String userId) {
    return _blocksRef(coupleId)
        .where('userId', isEqualTo: userId)
        .orderBy('startUtc')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => TimeBlockModel.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<void> deleteGoogleBlocksForUser(String coupleId, String userId) async {
    final query = await _blocksRef(coupleId)
        .where('userId', isEqualTo: userId)
        .where('source', isEqualTo: 'google')
        .get();

    final batch = _db.batch();
    for (final doc in query.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> createBlocksBatch(String coupleId, List<TimeBlockModel> blocks) async {
    final batch = _db.batch();
    for (final block in blocks) {
      batch.set(_blocksRef(coupleId).doc(block.id), block.toMap());
    }
    await batch.commit();
  }
}
```

**Step 2: Write block providers**

```dart
// lib/services/providers/block_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:couple_schedule/core/models/models.dart';
import 'package:couple_schedule/services/block_service.dart';

final blockServiceProvider = Provider<BlockService>((_) => BlockService());

final coupleBlocksProvider = StreamProvider.family<List<TimeBlockModel>, String>(
  (ref, coupleId) => ref.read(blockServiceProvider).watchBlocks(coupleId),
);
```

**Step 3: Run analyze, commit**

Run: `flutter analyze`

```bash
git add lib/services/block_service.dart lib/services/providers/block_providers.dart
git commit -m "feat: add block service with CRUD and batch operations"
```

---

### Task 7: Google Calendar Service

**Files:**
- Create: `lib/services/google_calendar_service.dart`
- Create: `lib/services/providers/calendar_providers.dart`

**Step 1: Write Google Calendar service**

```dart
// lib/services/google_calendar_service.dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;
import 'package:couple_schedule/core/models/models.dart';
import 'package:uuid/uuid.dart';

class GoogleCalendarService {
  final GoogleSignIn _googleSignIn;
  static const _uuid = Uuid();

  GoogleCalendarService(this._googleSignIn);

  Future<List<TimeBlockModel>> fetchBusyPeriods({
    required String userId,
    required String timezone,
    int days = 14,
  }) async {
    final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) throw Exception('Not signed into Google');

    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);

    try {
      final calApi = gcal.CalendarApi(client);
      final now = DateTime.now().toUtc();
      final end = now.add(Duration(days: days));

      final request = gcal.FreeBusyRequest(
        timeMin: now,
        timeMax: end,
        items: [gcal.FreeBusyRequestItem(id: 'primary')],
      );

      final response = await calApi.freebusy.query(request);
      final busySlots = response.calendars?['primary']?.busy ?? [];

      return busySlots.where((slot) => slot.start != null && slot.end != null).map((slot) {
        return TimeBlockModel(
          id: _uuid.v4(),
          userId: userId,
          title: 'Google Calendar',
          type: BlockType.busy,
          category: BlockCategory.other,
          startUtc: slot.start!.toUtc().millisecondsSinceEpoch,
          endUtc: slot.end!.toUtc().millisecondsSinceEpoch,
          timezone: timezone,
          source: BlockSource.google,
        );
      }).toList();
    } finally {
      client.close();
    }
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  void close() => _inner.close();
}
```

**Step 2: Write calendar providers**

```dart
// lib/services/providers/calendar_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:couple_schedule/services/google_calendar_service.dart';
import 'package:couple_schedule/services/providers/auth_providers.dart';

final googleCalendarServiceProvider = Provider<GoogleCalendarService?>((ref) {
  final googleSignIn = ref.read(googleSignInProvider);
  if (googleSignIn == null) return null;
  return GoogleCalendarService(googleSignIn);
});
```

**Step 3: Run analyze, commit**

```bash
git add lib/services/google_calendar_service.dart lib/services/providers/calendar_providers.dart
git commit -m "feat: add Google Calendar freebusy service"
```

---

### Task 8: Overlap Providers & Notification Service

**Files:**
- Create: `lib/services/providers/overlap_providers.dart`
- Create: `lib/services/notification_service.dart`
- Create: `lib/services/providers/providers.dart` (barrel export)

**Step 1: Write overlap providers**

```dart
// lib/services/providers/overlap_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_schedule/core/models/models.dart';

final overlapResultProvider = StreamProvider.family<OverlapResult?, String>(
  (ref, coupleId) {
    return FirebaseFirestore.instance
        .collection('overlaps')
        .doc(coupleId)
        .collection('windows')
        .doc('latest')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return OverlapResult.fromMap(coupleId, snap.data()!);
    });
  },
);
```

**Step 2: Write notification service**

```dart
// lib/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_showLocalNotification);
  }

  Future<void> saveToken(String uid) async {
    final token = await _fcm.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
    }

    // Listen for token refresh
    _fcm.onTokenRefresh.listen((newToken) {
      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmTokens': FieldValue.arrayUnion([newToken]),
      });
    });
  }

  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'overlap_updates',
          'Overlap Updates',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
```

**Step 3: Create barrel export**

```dart
// lib/services/providers/providers.dart
export 'auth_providers.dart';
export 'pairing_providers.dart';
export 'block_providers.dart';
export 'calendar_providers.dart';
export 'overlap_providers.dart';
```

**Step 4: Run analyze, commit**

```bash
git add lib/services/
git commit -m "feat: add overlap providers and notification service"
```

---

## Phase 3: Router & Screens

### Task 9: Router with Redirect Logic

**Files:**
- Create: `lib/core/router/router.dart`
- Modify: `lib/main.dart`
- Modify: `lib/app.dart` (create)

**Step 1: Write router**

```dart
// lib/core/router/router.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:couple_schedule/services/providers/auth_providers.dart';
import 'package:couple_schedule/features/auth/auth_screen.dart';
import 'package:couple_schedule/features/onboarding/timezone_setup_screen.dart';
import 'package:couple_schedule/features/onboarding/routine_setup_screen.dart';
import 'package:couple_schedule/features/pairing/pairing_screen.dart';
import 'package:couple_schedule/features/home/home_screen.dart';
import 'package:couple_schedule/features/calendar/calendar_screen.dart';
import 'package:couple_schedule/features/overlap/overlap_screen.dart';
import 'package:couple_schedule/features/blocks/blocks_screen.dart';
import 'package:couple_schedule/features/blocks/block_form_screen.dart';
import 'package:couple_schedule/features/settings/settings_screen.dart';

final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final currentUser = ref.watch(currentUserProvider);
  final currentCouple = ref.watch(currentCoupleProvider);
  final hydrated = ref.watch(hydrationCompleteProvider);

  return GoRouter(
    initialLocation: '/auth',
    redirect: (context, state) {
      final isLoggedIn = authState.value != null;
      final path = state.matchedLocation;

      // Not logged in — force to auth
      if (!isLoggedIn) {
        return path == '/auth' ? null : '/auth';
      }

      // Logged in but not hydrated — wait
      if (!hydrated) return null;

      // On auth screen — redirect based on state
      if (path == '/auth') {
        if (currentUser == null) return null;
        if (currentUser.timezone == 'UTC') return '/timezone-setup';
        if (currentCouple == null) return '/pairing';
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
      GoRoute(path: '/timezone-setup', builder: (_, __) => const TimezoneSetupScreen()),
      GoRoute(path: '/routine-setup', builder: (_, __) => const RoutineSetupScreen()),
      GoRoute(path: '/pairing', builder: (_, __) => const PairingScreen()),

      // Shell route with bottom nav
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
          GoRoute(path: '/overlap', builder: (_, __) => const OverlapScreen()),
        ],
      ),

      GoRoute(path: '/blocks', builder: (_, __) => const BlocksScreen()),
      GoRoute(path: '/blocks/add', builder: (_, __) => const BlockFormScreen()),
      GoRoute(
        path: '/blocks/edit/:id',
        builder: (_, state) => BlockFormScreen(editBlockId: state.pathParameters['id']),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
});

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _calculateIndex(GoRouterState.of(context).matchedLocation),
        onDestinationSelected: (i) => _onTap(context, i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Calendar'),
          NavigationDestination(icon: Icon(Icons.access_time), label: 'Free Time'),
        ],
      ),
    );
  }

  int _calculateIndex(String location) {
    if (location.startsWith('/calendar')) return 1;
    if (location.startsWith('/overlap')) return 2;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0: context.go('/home');
      case 1: context.go('/calendar');
      case 2: context.go('/overlap');
    }
  }
}
```

**Step 2: Write app.dart**

```dart
// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:couple_schedule/core/router/router.dart';

class CoupleScheduleApp extends ConsumerWidget {
  const CoupleScheduleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Couple Schedule',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFF4A0B5),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
```

**Step 3: Update main.dart**

```dart
// lib/main.dart
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

**Step 4: Create placeholder screens** (one file each, just a Scaffold with text — will be implemented in later tasks)

Create placeholder for each screen:
- `lib/features/auth/auth_screen.dart`
- `lib/features/onboarding/timezone_setup_screen.dart`
- `lib/features/onboarding/routine_setup_screen.dart`
- `lib/features/pairing/pairing_screen.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/calendar/calendar_screen.dart`
- `lib/features/overlap/overlap_screen.dart`
- `lib/features/blocks/blocks_screen.dart`
- `lib/features/blocks/block_form_screen.dart`
- `lib/features/settings/settings_screen.dart`

Each placeholder follows this pattern:

```dart
import 'package:flutter/material.dart';

class ScreenName extends StatelessWidget {
  const ScreenName({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Screen Name')),
    );
  }
}
```

**Step 5: Run analyze, build**

Run: `flutter analyze && flutter build apk --debug 2>&1 | tail -5`
Expected: Builds

**Step 6: Commit**

```bash
git add lib/
git commit -m "feat: add router with redirect logic and placeholder screens"
```

---

### Task 10: Auth Screen

**Files:**
- Modify: `lib/features/auth/auth_screen.dart`

**Step 1: Implement auth screen**

```dart
// lib/features/auth/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:couple_schedule/services/providers/auth_providers.dart';
import 'package:couple_schedule/services/auth_service.dart';
import 'package:couple_schedule/services/notification_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn(Future<void> Function() signInMethod) async {
    setState(() { _loading = true; _error = null; });
    try {
      await signInMethod();
      await _hydrateAndNavigate();
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _hydrateAndNavigate() async {
    final authService = ref.read(authServiceProvider);
    final user = authService.currentUser;
    if (user == null) return;

    final userModel = await authService.fetchUser(user.uid);
    if (userModel == null) return;

    ref.read(currentUserProvider.notifier).state = userModel;

    // Save FCM token
    await NotificationService().saveToken(user.uid);

    // Check couple
    if (userModel.coupleId != null) {
      final couple = await authService.fetchCoupleForUser(user.uid);
      ref.read(currentCoupleProvider.notifier).state = couple;
    }

    ref.read(hydrationCompleteProvider.notifier).state = true;

    if (!mounted) return;

    if (userModel.timezone == 'UTC') {
      context.go('/timezone-setup');
    } else if (userModel.coupleId == null) {
      context.go('/pairing');
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Couple Schedule',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Find your free time together'),
              const SizedBox(height: 64),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _signIn(() async {
                            final svc = ref.read(authServiceProvider);
                            await svc.signInWithGoogle();
                          }),
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _signIn(() async {
                            final svc = ref.read(authServiceProvider);
                            await svc.signInWithApple();
                          }),
                  icon: const Icon(Icons.apple),
                  label: const Text('Sign in with Apple'),
                ),
              ),
              if (_loading) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

**Step 2: Run analyze, commit**

```bash
git add lib/features/auth/
git commit -m "feat: implement auth screen with Google and Apple sign-in"
```

---

### Task 11: Timezone Setup Screen

**Files:**
- Modify: `lib/features/onboarding/timezone_setup_screen.dart`

**Step 1: Implement timezone setup**

```dart
// lib/features/onboarding/timezone_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:couple_schedule/services/providers/auth_providers.dart';
import 'package:couple_schedule/services/auth_service.dart';

class TimezoneSetupScreen extends ConsumerStatefulWidget {
  const TimezoneSetupScreen({super.key});

  @override
  ConsumerState<TimezoneSetupScreen> createState() => _TimezoneSetupScreenState();
}

class _TimezoneSetupScreenState extends ConsumerState<TimezoneSetupScreen> {
  late String _selected;
  String _search = '';
  bool _saving = false;

  List<String> get _allTimezones => tz.timeZoneDatabase.locations.keys.toList()..sort();

  List<String> get _filtered => _search.isEmpty
      ? _allTimezones
      : _allTimezones.where((t) => t.toLowerCase().contains(_search.toLowerCase())).toList();

  @override
  void initState() {
    super.initState();
    _selected = _detectLocalTimezone();
  }

  String _detectLocalTimezone() {
    final offset = DateTime.now().timeZoneOffset;
    final name = DateTime.now().timeZoneName;
    // Try to match by name first, fallback to offset
    for (final tzId in _allTimezones) {
      final loc = tz.getLocation(tzId);
      final now = tz.TZDateTime.now(loc);
      if (now.timeZoneOffset == offset) return tzId;
    }
    return 'UTC';
  }

  Future<void> _save() async {
    setState(() { _saving = true; });
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;
      await ref.read(authServiceProvider).updateTimezone(user.uid, _selected);
      ref.read(currentUserProvider.notifier).state = user.copyWith(timezone: _selected);
      if (mounted) context.go('/routine-setup');
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Timezone')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search timezones...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() { _search = v; }),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final tzId = _filtered[i];
                return RadioListTile<String>(
                  title: Text(tzId),
                  value: tzId,
                  groupValue: _selected,
                  onChanged: (v) => setState(() { _selected = v!; }),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/features/onboarding/timezone_setup_screen.dart
git commit -m "feat: implement timezone setup screen"
```

---

### Task 12: Routine Setup Wizard

**Files:**
- Modify: `lib/features/onboarding/routine_setup_screen.dart`

**Step 1: Implement routine wizard**

```dart
// lib/features/onboarding/routine_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:couple_schedule/core/models/models.dart';
import 'package:couple_schedule/services/providers/auth_providers.dart';
import 'package:couple_schedule/services/providers/block_providers.dart';

class RoutineSetupScreen extends ConsumerStatefulWidget {
  const RoutineSetupScreen({super.key});

  @override
  ConsumerState<RoutineSetupScreen> createState() => _RoutineSetupScreenState();
}

class _RoutineSetupScreenState extends ConsumerState<RoutineSetupScreen> {
  int _step = 0;
  bool _saving = false;

  // Sleep
  TimeOfDay _bedtime = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay _wakeTime = const TimeOfDay(hour: 7, minute: 0);
  bool _skipSleep = false;

  // Work
  TimeOfDay _workStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _workEnd = const TimeOfDay(hour: 17, minute: 0);
  Set<int> _workDays = {1, 2, 3, 4, 5}; // Mon-Fri
  bool _skipWork = false;

  // Commute
  TimeOfDay _commuteAmStart = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _commuteAmEnd = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _commutePmStart = const TimeOfDay(hour: 17, minute: 30);
  TimeOfDay _commutePmEnd = const TimeOfDay(hour: 18, minute: 30);
  Set<int> _commuteDays = {1, 2, 3, 4, 5};
  bool _skipCommute = false;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _buildWeeklyRRule(Set<int> days) {
    final dayCodes = {1: 'MO', 2: 'TU', 3: 'WE', 4: 'TH', 5: 'FR', 6: 'SA', 7: 'SU'};
    final byday = days.map((d) => dayCodes[d]!).join(',');
    return 'RRULE:FREQ=WEEKLY;BYDAY=$byday';
  }

  int _timeToUtcMs(TimeOfDay time) {
    final now = DateTime.now();
    final local = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return local.toUtc().millisecondsSinceEpoch;
  }

  Future<void> _finish() async {
    setState(() { _saving = true; });
    try {
      final user = ref.read(currentUserProvider);
      final couple = ref.read(currentCoupleProvider);
      if (user == null) {
        if (mounted) context.go('/pairing');
        return;
      }

      final coupleId = couple?.coupleId;
      if (coupleId == null) {
        if (mounted) context.go('/pairing');
        return;
      }

      final blockService = ref.read(blockServiceProvider);
      final blocks = <TimeBlockModel>[];

      if (!_skipSleep) {
        blocks.add(TimeBlockModel(
          id: '', // will be set by service
          userId: user.uid,
          title: 'Sleep',
          type: BlockType.busy,
          category: BlockCategory.sleep,
          startUtc: _timeToUtcMs(_bedtime),
          endUtc: _timeToUtcMs(_wakeTime),
          timezone: user.timezone,
          recurrenceRule: 'RRULE:FREQ=DAILY',
          source: BlockSource.manual,
        ));
      }

      if (!_skipWork) {
        blocks.add(TimeBlockModel(
          id: '',
          userId: user.uid,
          title: 'Work',
          type: BlockType.busy,
          category: BlockCategory.work,
          startUtc: _timeToUtcMs(_workStart),
          endUtc: _timeToUtcMs(_workEnd),
          timezone: user.timezone,
          recurrenceRule: _buildWeeklyRRule(_workDays),
          source: BlockSource.manual,
        ));
      }

      if (!_skipCommute) {
        blocks.add(TimeBlockModel(
          id: '',
          userId: user.uid,
          title: 'Commute (AM)',
          type: BlockType.busy,
          category: BlockCategory.commute,
          startUtc: _timeToUtcMs(_commuteAmStart),
          endUtc: _timeToUtcMs(_commuteAmEnd),
          timezone: user.timezone,
          recurrenceRule: _buildWeeklyRRule(_commuteDays),
          source: BlockSource.manual,
        ));
        blocks.add(TimeBlockModel(
          id: '',
          userId: user.uid,
          title: 'Commute (PM)',
          type: BlockType.busy,
          category: BlockCategory.commute,
          startUtc: _timeToUtcMs(_commutePmStart),
          endUtc: _timeToUtcMs(_commutePmEnd),
          timezone: user.timezone,
          recurrenceRule: _buildWeeklyRRule(_commuteDays),
          source: BlockSource.manual,
        ));
      }

      // Create blocks individually (each triggers overlap recompute)
      for (final block in blocks) {
        await blockService.createBlock(
          coupleId: coupleId,
          userId: block.userId,
          title: block.title,
          type: block.type,
          category: block.category,
          startUtc: block.startUtc,
          endUtc: block.endUtc,
          timezone: block.timezone,
          recurrenceRule: block.recurrenceRule,
        );
      }

      if (mounted) context.go('/home');
    } finally {
      if (mounted) setState(() { _saving = false; });
    }
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) async {
    return showTimePicker(context: context, initialTime: initial);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Routine')),
      body: Stepper(
        currentStep: _step,
        onStepContinue: () {
          if (_step < 2) {
            setState(() { _step++; });
          } else {
            _finish();
          }
        },
        onStepCancel: _step > 0 ? () => setState(() { _step--; }) : null,
        controlsBuilder: (_, details) {
          return Row(
            children: [
              FilledButton(
                onPressed: _saving ? null : details.onStepContinue,
                child: Text(_step == 2 ? 'Finish' : 'Next'),
              ),
              if (_step > 0) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: details.onStepCancel,
                  child: const Text('Back'),
                ),
              ],
            ],
          );
        },
        steps: [
          Step(
            title: const Text('Sleep'),
            content: _skipSleep
                ? TextButton(
                    onPressed: () => setState(() { _skipSleep = false; }),
                    child: const Text('Add sleep schedule'),
                  )
                : Column(
                    children: [
                      ListTile(
                        title: const Text('Bedtime'),
                        trailing: Text(_bedtime.format(context)),
                        onTap: () async {
                          final t = await _pickTime(_bedtime);
                          if (t != null) setState(() { _bedtime = t; });
                        },
                      ),
                      ListTile(
                        title: const Text('Wake time'),
                        trailing: Text(_wakeTime.format(context)),
                        onTap: () async {
                          final t = await _pickTime(_wakeTime);
                          if (t != null) setState(() { _wakeTime = t; });
                        },
                      ),
                      TextButton(
                        onPressed: () => setState(() { _skipSleep = true; }),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
            isActive: _step >= 0,
          ),
          Step(
            title: const Text('Work / Study'),
            content: _skipWork
                ? TextButton(
                    onPressed: () => setState(() { _skipWork = false; }),
                    child: const Text('Add work schedule'),
                  )
                : Column(
                    children: [
                      ListTile(
                        title: const Text('Start'),
                        trailing: Text(_workStart.format(context)),
                        onTap: () async {
                          final t = await _pickTime(_workStart);
                          if (t != null) setState(() { _workStart = t; });
                        },
                      ),
                      ListTile(
                        title: const Text('End'),
                        trailing: Text(_workEnd.format(context)),
                        onTap: () async {
                          final t = await _pickTime(_workEnd);
                          if (t != null) setState(() { _workEnd = t; });
                        },
                      ),
                      Wrap(
                        spacing: 8,
                        children: List.generate(7, (i) {
                          final day = i + 1;
                          return FilterChip(
                            label: Text(_dayNames[i]),
                            selected: _workDays.contains(day),
                            onSelected: (v) => setState(() {
                              v ? _workDays.add(day) : _workDays.remove(day);
                            }),
                          );
                        }),
                      ),
                      TextButton(
                        onPressed: () => setState(() { _skipWork = true; }),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
            isActive: _step >= 1,
          ),
          Step(
            title: const Text('Commute'),
            content: _skipCommute
                ? TextButton(
                    onPressed: () => setState(() { _skipCommute = false; }),
                    child: const Text('Add commute schedule'),
                  )
                : Column(
                    children: [
                      const Text('Morning commute',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ListTile(
                        title: const Text('Leave'),
                        trailing: Text(_commuteAmStart.format(context)),
                        onTap: () async {
                          final t = await _pickTime(_commuteAmStart);
                          if (t != null) setState(() { _commuteAmStart = t; });
                        },
                      ),
                      ListTile(
                        title: const Text('Arrive'),
                        trailing: Text(_commuteAmEnd.format(context)),
                        onTap: () async {
                          final t = await _pickTime(_commuteAmEnd);
                          if (t != null) setState(() { _commuteAmEnd = t; });
                        },
                      ),
                      const Divider(),
                      const Text('Evening commute',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      ListTile(
                        title: const Text('Leave'),
                        trailing: Text(_commutePmStart.format(context)),
                        onTap: () async {
                          final t = await _pickTime(_commutePmStart);
                          if (t != null) setState(() { _commutePmStart = t; });
                        },
                      ),
                      ListTile(
                        title: const Text('Arrive'),
                        trailing: Text(_commutePmEnd.format(context)),
                        onTap: () async {
                          final t = await _pickTime(_commutePmEnd);
                          if (t != null) setState(() { _commutePmEnd = t; });
                        },
                      ),
                      Wrap(
                        spacing: 8,
                        children: List.generate(7, (i) {
                          final day = i + 1;
                          return FilterChip(
                            label: Text(_dayNames[i]),
                            selected: _commuteDays.contains(day),
                            onSelected: (v) => setState(() {
                              v ? _commuteDays.add(day) : _commuteDays.remove(day);
                            }),
                          );
                        }),
                      ),
                      TextButton(
                        onPressed: () => setState(() { _skipCommute = true; }),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
            isActive: _step >= 2,
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/features/onboarding/routine_setup_screen.dart
git commit -m "feat: implement routine setup wizard with sleep/work/commute"
```

---

### Task 13: Pairing Screen

**Files:**
- Modify: `lib/features/pairing/pairing_screen.dart`

**Step 1: Implement pairing screen with share code + enter code tabs, user doc listener for auto-navigate, and re-pairing support.**

The screen should:
- Share tab: call `pairingService.generateInviteCode(uid)`, show code, copy button
- Enter tab: text field (auto-uppercase, 6 char limit), validate button calls `redeemInviteCode`
- Listen to `users/{uid}` snapshots — when `coupleId` appears, fetch couple, set providers, navigate to `/routine-setup` (if new) or `/home` (if re-paired)
- Handle errors: invalid code, expired, self-invite, already paired

**Step 2: Commit**

```bash
git add lib/features/pairing/
git commit -m "feat: implement pairing screen with code sharing and redemption"
```

---

### Task 14: Home Screen

**Files:**
- Modify: `lib/features/home/home_screen.dart`

**Step 1: Implement home screen with:**
- Partner timezone clocks (use `timezone` package to get current time in both timezones)
- Next free window card from `overlapResultProvider`
- List of next 5 windows
- Quick action buttons: Add Block (`/blocks/add`), Sync Calendar, View All (`/overlap`)
- Settings icon button → `/settings`
- Pull-to-refresh: triggers Google Calendar sync → overlap recomputes automatically via Cloud Function

**Step 2: Commit**

```bash
git add lib/features/home/
git commit -m "feat: implement home screen with timezone clocks and overlap display"
```

---

### Task 15: Calendar Week View

**Files:**
- Modify: `lib/features/calendar/calendar_screen.dart`

**Step 1: Implement calendar screen with:**
- `PageView` for week-by-week horizontal scrolling
- 7-column day grid
- Blocks rendered as colored bars (your color vs partner color)
- Overlap windows highlighted in a third color
- Tap block → bottom sheet with details
- "Today" button to jump to current week
- "Sync" button triggers Google Calendar sync
- FAB → `/blocks/add`

**Step 2: Commit**

```bash
git add lib/features/calendar/
git commit -m "feat: implement calendar week view with dual-partner blocks"
```

---

### Task 16: Overlap/Free Windows Screen

**Files:**
- Modify: `lib/features/overlap/overlap_screen.dart`

**Step 1: Implement overlap screen with:**
- Watch `overlapResultProvider(coupleId)`
- SegmentedButton filter: Any / 30m+ / 1h+ / 2h+
- List of window cards showing: date, time in your tz, partner's tz, duration, score
- "Last computed X ago" in app bar subtitle

**Step 2: Commit**

```bash
git add lib/features/overlap/
git commit -m "feat: implement overlap screen with duration filtering"
```

---

### Task 17: Block Management & Form Screens

**Files:**
- Modify: `lib/features/blocks/blocks_screen.dart`
- Modify: `lib/features/blocks/block_form_screen.dart`

**Step 1: Implement blocks screen:**
- Watch `coupleBlocksProvider(coupleId)` filtered to current user
- List tiles: title, category chip, time range, source badge (Google/Manual)
- Swipe to delete (manual only)
- Tap to edit (manual only, opens `/blocks/edit/:id`)
- FAB → `/blocks/add`

**Step 2: Implement block form screen:**
- Title text field
- BlockType segmented control (busy/free/tentative)
- BlockCategory dropdown
- Date picker + time pickers for start and end
- Recurrence: None / Daily / Weekly (with day chips) / Monthly
- Visibility toggle: Both partners / Only me
- Save button validates: title not empty, end > start
- If `editBlockId` is set, pre-populate from existing block

**Step 3: Commit**

```bash
git add lib/features/blocks/
git commit -m "feat: implement block management and form screens"
```

---

### Task 18: Settings Screen

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`

**Step 1: Implement settings screen with sections:**
- **Calendar**: Google connection status, connect/disconnect button, last sync time, manual sync
- **Timezone**: Current timezone display, change button → `/timezone-setup`
- **Routine**: "Re-run setup" button → `/routine-setup`
- **Notifications**: Toggle for overlap alerts (SharedPreferences)
- **Couple**: Partner name, unpair button with confirmation dialog
- **Account**: Sign out button with confirmation

**Step 2: Commit**

```bash
git add lib/features/settings/
git commit -m "feat: implement settings screen"
```

---

## Phase 4: Cloud Functions (Rebuild)

### Task 19: Clean Cloud Functions Scaffold

**Files:**
- Modify: `functions/src/index.ts`
- Modify: `functions/src/overlap.ts`
- Modify: `functions/src/notifications.ts`
- Delete: `functions/src/gemini.ts` (cut for v1)
- Delete: `functions/src/patterns.ts` (cut for v1)
- Modify: `functions/package.json` (remove @google/generative-ai)

**Step 1: Update package.json — remove Gemini dependency**

```json
{
  "dependencies": {
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^4.9.0",
    "luxon": "^3.5.0"
  }
}
```

**Step 2: Rewrite overlap.ts — remove Gemini calls, keep algorithm identical**

The overlap engine stays the same but:
- Remove `import { suggestActivities }`
- Remove the `suggestActivities()` call and set `suggestedActivity: null`
- Keep all RRULE expansion, busy timeline, free inversion, intersection, clipping, scoring logic

**Step 3: Keep notifications.ts as-is — it works correctly**

**Step 4: Update index.ts**

```typescript
import * as admin from "firebase-admin";
import { onBlockWrite } from "./overlap";
import { onOverlapWrite } from "./notifications";

admin.initializeApp();

export { onBlockWrite, onOverlapWrite };
```

**Step 5: Build and deploy**

Run: `cd functions && npm install && npm run build && firebase deploy --only functions`
Expected: Deploy succeeds

**Step 6: Commit**

```bash
git add functions/
git commit -m "feat: clean Cloud Functions - overlap engine and notifications"
```

---

### Task 20: Create Firestore Indexes

**Files:**
- Modify: `firestore.indexes.json`

**Step 1: Add required composite indexes**

```json
{
  "indexes": [
    {
      "collectionGroup": "blocks",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "source", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "blocks",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "startUtc", "order": "ASCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

**Step 2: Deploy indexes**

Run: `firebase deploy --only firestore:indexes`

**Step 3: Commit**

```bash
git add firestore.indexes.json
git commit -m "feat: add Firestore composite indexes"
```

---

## Phase 5: Integration & Testing

### Task 21: End-to-End Smoke Test

**Files:**
- Create: `test/integration/auth_flow_test.dart`
- Create: `test/integration/pairing_flow_test.dart`
- Create: `test/core/models/time_block_model_test.dart`
- Create: `test/core/models/overlap_result_model_test.dart`

**Step 1: Write model unit tests**

Test all `fromMap` / `toMap` round-trips for every model. Test edge cases:
- UserModel with missing fields gets defaults
- TimeBlockModel enum parsing with invalid values falls back
- OverlapWindow score as int vs double
- InviteModel expiration check
- CoupleModel.partnerUid

**Step 2: Write widget tests for auth flow**

Test that:
- AuthScreen renders sign-in buttons
- Router redirects unauthenticated to `/auth`
- Router redirects authenticated without timezone to `/timezone-setup`
- Router redirects authenticated without couple to `/pairing`
- Router allows authenticated with couple to `/home`

**Step 3: Run all tests**

Run: `flutter test`
Expected: All pass

**Step 4: Commit**

```bash
git add test/
git commit -m "test: add model unit tests and auth flow widget tests"
```

---

### Task 22: Final Integration — Wire Everything Together

**Files:**
- Modify: `lib/main.dart` (add notification init)
- Modify: `lib/app.dart` (add auth state listener for re-hydration)
- Modify: `firebase.json` (ensure functions + firestore config)

**Step 1: Update main.dart with notification init**

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  tz.initializeTimeZones();
  await NotificationService().init();
  runApp(const ProviderScope(child: CoupleScheduleApp()));
}
```

**Step 2: Update firebase.json**

```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "functions": {
    "source": "functions",
    "predeploy": ["npm --prefix \"$RESOURCE_DIR\" run build"]
  }
}
```

**Step 3: Full build + analyze + test**

Run: `flutter analyze && flutter test && flutter build apk --debug`
Expected: All pass, APK builds

**Step 4: Deploy everything**

Run: `firebase deploy`
Expected: Rules, indexes, functions all deploy

**Step 5: Commit**

```bash
git add .
git commit -m "feat: wire final integration — notifications, firebase config"
```

---

## Task Dependency Graph

```
Task 1 (Scaffold)
  → Task 2 (Models)
  → Task 3 (Security Rules)
  → Task 4 (Auth Service) → Task 10 (Auth Screen)
  → Task 5 (Pairing Service) → Task 13 (Pairing Screen)
  → Task 6 (Block Service) → Task 12 (Routine Wizard) → Task 17 (Block CRUD Screens)
  → Task 7 (Calendar Service)
  → Task 8 (Overlap + Notification Providers)
  → Task 9 (Router) → Task 11 (Timezone Screen)
  → Task 14 (Home Screen)
  → Task 15 (Calendar View)
  → Task 16 (Overlap Screen)
  → Task 18 (Settings Screen)
  → Task 19 (Cloud Functions)
  → Task 20 (Indexes)
  → Task 21 (Tests)
  → Task 22 (Final Integration)
```

**Parallelizable groups:**
- Tasks 2, 3 can run in parallel
- Tasks 4, 5, 6, 7, 8 can run in parallel (all depend on Task 2 only)
- Tasks 10-18 (screens) can largely be parallelized after services exist
- Tasks 19, 20 are independent of Flutter code

---

## Summary

**22 tasks** across 5 phases. Core path: scaffold → models → services → router → screens → cloud functions → tests → integration. The overlap engine algorithm is preserved from the existing codebase (it's correct). The key differences from the old code:

1. **Single source of truth** for each model (no duplicates)
2. **Clean service layer** (no provider spaghetti)
3. **Routine setup wizard** (new — massive UX improvement)
4. **Soft-delete couples** with re-pairing (new)
5. **No Gemini/AI** in v1 (cut scope)
6. **No pattern detection** in v1 (cut scope)
7. **Proper tests** from the start
