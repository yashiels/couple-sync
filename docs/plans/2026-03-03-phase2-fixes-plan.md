# Phase 2: Auth Fix, Multi-Calendar & Remaining MVP

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the infinite loading bug, add multi-Google-account calendar support, and close remaining MVP gaps.

**Architecture:** Fix the auth hydration gap so `currentUserProvider` is populated on session restore. Replace flat `googleConnected` boolean with `calendarConnections` array in UserModel/Firestore. Wire up remaining UI stubs to real services.

**Tech Stack:** Flutter/Dart, Riverpod, Firestore, Google Calendar API v3, Firebase Cloud Functions (Node 20), FCM

---

### Task 1: Fix Auth Session Hydration (Infinite Loading Bug)

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/shared/providers/auth_providers.dart`
- Modify: `lib/shared/services/auth_service.dart`
- Test: `test/providers/auth_hydration_test.dart`

**Context:** `currentUserProvider` is a `StateProvider<UserModel?>` initialized to `null` (line 21 of auth_providers.dart). It only gets set when `AuthNotifier.signInWithGoogle()` completes (line 38). On app restart, Firebase restores the session → router redirects to `/home` → but `currentUserProvider` is never populated → infinite spinner.

**Step 1: Add `fetchUserModel` method to AuthService**

In `lib/shared/services/auth_service.dart`, add after the `currentUser` getter (line 31):

```dart
/// Fetches the [UserModel] for [uid] from Firestore, or `null` if missing.
Future<UserModel?> fetchUserModel(String uid) async {
  final doc = await _firestore.collection('users').doc(uid).get();
  if (!doc.exists) return null;
  return UserModel.fromFirestore(doc);
}
```

**Step 2: Add `fetchCoupleForUser` method to AuthService**

In `lib/shared/services/auth_service.dart`, add after `fetchUserModel`:

```dart
/// Fetches the [CoupleModel] where [uid] is userA or userB, or `null`.
Future<CoupleModel?> fetchCoupleForUser(String uid) async {
  // Check userA
  var query = await _firestore
      .collection('couples')
      .where('userAUid', isEqualTo: uid)
      .limit(1)
      .get();
  if (query.docs.isNotEmpty) return CoupleModel.fromFirestore(query.docs.first);

  // Check userB
  query = await _firestore
      .collection('couples')
      .where('userBUid', isEqualTo: uid)
      .limit(1)
      .get();
  if (query.docs.isNotEmpty) return CoupleModel.fromFirestore(query.docs.first);

  return null;
}
```

Add `import '../models/couple_model.dart';` at the top.

**Step 3: Create AppStartupWidget to hydrate providers**

In `lib/main.dart`, replace the `CoupleScheduleApp` class with:

```dart
class CoupleScheduleApp extends ConsumerStatefulWidget {
  const CoupleScheduleApp({super.key});

  @override
  ConsumerState<CoupleScheduleApp> createState() => _CoupleScheduleAppState();
}

class _CoupleScheduleAppState extends ConsumerState<CoupleScheduleApp> {
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _hydrateSession();
  }

  Future<void> _hydrateSession() async {
    final authService = ref.read(authServiceProvider);
    final firebaseUser = authService.currentUser;
    if (firebaseUser != null) {
      final userModel = await authService.fetchUserModel(firebaseUser.uid);
      if (userModel != null) {
        ref.read(currentUserProvider.notifier).state = userModel;
        if (userModel.coupleId != null) {
          final couple = await authService.fetchCoupleForUser(firebaseUser.uid);
          ref.read(currentCoupleProvider.notifier).state = couple;
        }
      }
    }
    if (mounted) setState(() => _hydrated = true);
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state changes to re-hydrate on sign-in/sign-out
    ref.listen(firebaseAuthStateProvider, (prev, next) {
      final prevUser = prev?.valueOrNull;
      final nextUser = next.valueOrNull;
      if (prevUser?.uid != nextUser?.uid) {
        _hydrated = false;
        _hydrateSession();
      }
    });

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

Add these imports to `lib/main.dart`:
```dart
import 'shared/providers/auth_providers.dart';
import 'shared/providers/pairing_providers.dart';
```

**Step 4: Write test for auth hydration**

Create `test/providers/auth_hydration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/shared/models/user_model.dart';

void main() {
  group('Auth hydration', () {
    test('UserModel.fromFirestore round-trips correctly', () {
      final model = UserModel(
        uid: 'test-uid',
        email: 'test@test.com',
        displayName: 'Test User',
        timezone: 'Africa/Johannesburg',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final map = model.toFirestore();
      expect(map['uid'], 'test-uid');
      expect(map['email'], 'test@test.com');
      expect(map['timezone'], 'Africa/Johannesburg');
    });
  });
}
```

**Step 5: Run tests**

Run: `flutter test`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/main.dart lib/shared/services/auth_service.dart test/providers/
git commit -m "fix: hydrate currentUserProvider on session restore

Fixes infinite loading on home screen when Firebase auto-restores
the auth session but currentUserProvider stays null."
```

---

### Task 2: Multi-Google-Account Data Model

**Files:**
- Modify: `lib/shared/models/user_model.dart`
- Create: `lib/shared/models/calendar_connection.dart`
- Test: `test/models/calendar_connection_test.dart`

**Context:** Currently `UserModel` has flat booleans `googleConnected` (line 14) and `microsoftConnected` (line 15). Need to replace with a `calendarConnections` list.

**Step 1: Create CalendarConnection model**

Create `lib/shared/models/calendar_connection.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

enum CalendarProvider { google, microsoft }

class CalendarConnection {
  final String id;
  final CalendarProvider provider;
  final String email;
  final DateTime connectedAt;
  final DateTime? lastSync;

  CalendarConnection({
    String? id,
    required this.provider,
    required this.email,
    required this.connectedAt,
    this.lastSync,
  }) : id = id ?? const Uuid().v4();

  factory CalendarConnection.fromMap(Map<String, dynamic> map) {
    return CalendarConnection(
      id: map['id'] as String,
      provider: CalendarProvider.values.byName(map['provider'] as String),
      email: map['email'] as String,
      connectedAt: (map['connectedAt'] as Timestamp).toDate(),
      lastSync: map['lastSync'] != null
          ? (map['lastSync'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'provider': provider.name,
        'email': email,
        'connectedAt': Timestamp.fromDate(connectedAt),
        if (lastSync != null) 'lastSync': Timestamp.fromDate(lastSync!),
      };

  CalendarConnection copyWith({DateTime? lastSync}) => CalendarConnection(
        id: id,
        provider: provider,
        email: email,
        connectedAt: connectedAt,
        lastSync: lastSync ?? this.lastSync,
      );
}
```

**Step 2: Update UserModel to use calendarConnections**

In `lib/shared/models/user_model.dart`, replace the flat boolean fields (lines 14-17) with:

```dart
final List<CalendarConnection> calendarConnections;
```

Update the constructor default: `this.calendarConnections = const [],`

Remove: `googleConnected`, `microsoftConnected`, `microsoftEmail`, `defaultCoupleCalendarId` from constructor and fields.

Update `fromFirestore()` — replace lines 44-47 with:
```dart
calendarConnections: (data['calendarConnections'] as List<dynamic>?)
    ?.map((e) => CalendarConnection.fromMap(e as Map<String, dynamic>))
    .toList() ?? [],
```

Update `toFirestore()` — replace lines 59-62 with:
```dart
'calendarConnections': calendarConnections.map((c) => c.toMap()).toList(),
```

Update `copyWith()` — replace the four removed fields with:
```dart
List<CalendarConnection>? calendarConnections,
```
and in the return: `calendarConnections: calendarConnections ?? this.calendarConnections,`

Add import: `import 'calendar_connection.dart';`

**Step 3: Add convenience getters to UserModel**

```dart
/// Whether any Google account is connected.
bool get googleConnected =>
    calendarConnections.any((c) => c.provider == CalendarProvider.google);

/// Whether any Microsoft account is connected.
bool get microsoftConnected =>
    calendarConnections.any((c) => c.provider == CalendarProvider.microsoft);

/// All connected Google account emails.
List<String> get googleEmails => calendarConnections
    .where((c) => c.provider == CalendarProvider.google)
    .map((c) => c.email)
    .toList();
```

**Step 4: Write tests**

Create `test/models/calendar_connection_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/shared/models/calendar_connection.dart';

void main() {
  group('CalendarConnection', () {
    test('toMap / fromMap round-trip', () {
      final conn = CalendarConnection(
        id: 'abc',
        provider: CalendarProvider.google,
        email: 'user@gmail.com',
        connectedAt: DateTime.utc(2026, 3, 3),
      );
      final map = conn.toMap();
      expect(map['provider'], 'google');
      expect(map['email'], 'user@gmail.com');
      expect(map['id'], 'abc');
    });
  });
}
```

**Step 5: Fix existing user_model_test.dart**

Update `test/models/user_model_test.dart` to remove references to old `googleConnected`, `microsoftConnected` fields and use `calendarConnections: []` instead.

**Step 6: Run tests**

Run: `flutter test`
Expected: All tests pass

**Step 7: Commit**

```bash
git add lib/shared/models/calendar_connection.dart lib/shared/models/user_model.dart test/models/
git commit -m "feat: add CalendarConnection model for multi-account support

Replaces flat googleConnected/microsoftConnected booleans with a
calendarConnections array supporting multiple Google accounts."
```

---

### Task 3: Update GoogleCalendarService for Multi-Account

**Files:**
- Modify: `lib/features/calendar/services/google_calendar_service.dart`
- Modify: `lib/features/calendar/providers/google_calendar_provider.dart`

**Context:** The service currently manages a single `GoogleSignIn` instance. Need to support adding multiple accounts and syncing all of them.

**Step 1: Update GoogleCalendarService**

In `lib/features/calendar/services/google_calendar_service.dart`:

Replace `connect()` (lines 32-40) with a method that returns the connected email:

```dart
/// Initiates Google OAuth and returns the connected email, or null if cancelled.
Future<String?> connectAccount() async {
  try {
    final account = await _googleSignIn.signIn();
    return account?.email;
  } catch (e) {
    debugPrint('GoogleCalendarService.connectAccount error: $e');
    return null;
  }
}
```

Update `syncToFirestore()` (lines 115-144) to accept email and update the connection's lastSync:

```dart
/// Syncs busy periods and updates the connection's lastSync in Firestore.
Future<void> syncToFirestore({
  required String userId,
  required String coupleId,
  String? connectionId,
}) async {
  final blocks = await fetchBusyPeriods(userId: userId, coupleId: coupleId);
  final blocksRef = FirebaseFirestore.instance
      .collection('timeblocks')
      .doc(coupleId)
      .collection('blocks');

  final batch = FirebaseFirestore.instance.batch();

  // Delete stale Google blocks for this user
  final stale = await blocksRef
      .where('ownerUid', isEqualTo: userId)
      .where('source', isEqualTo: 'google')
      .get();
  for (final doc in stale.docs) {
    batch.delete(doc.reference);
  }

  // Write fresh blocks
  for (final block in blocks) {
    batch.set(blocksRef.doc(), block.toFirestore());
  }

  await batch.commit();

  if (connectionId != null) {
    await _updateConnectionLastSync(userId, connectionId);
  }
}
```

Add helper:

```dart
Future<void> _updateConnectionLastSync(String userId, String connectionId) async {
  final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
  final doc = await userRef.get();
  if (!doc.exists) return;

  final connections = (doc.data()?['calendarConnections'] as List<dynamic>?) ?? [];
  final updated = connections.map((c) {
    final map = c as Map<String, dynamic>;
    if (map['id'] == connectionId) {
      return {...map, 'lastSync': FieldValue.serverTimestamp()};
    }
    return map;
  }).toList();

  await userRef.update({'calendarConnections': updated});
}
```

**Step 2: Update GoogleCalendarProvider for multi-account**

In `lib/features/calendar/providers/google_calendar_provider.dart`, update the `_ConnectionNotifier` to manage a list of connections:

Replace the single boolean notifier with:

```dart
/// Notifier managing Google Calendar account connections.
class GoogleCalendarConnectionNotifier extends StateNotifier<List<CalendarConnection>> {
  final GoogleCalendarService _service;
  final FirebaseFirestore _firestore;

  GoogleCalendarConnectionNotifier(this._service)
      : _firestore = FirebaseFirestore.instance,
        super([]);

  /// Loads connections from the user's Firestore document.
  void loadConnections(List<CalendarConnection> connections) {
    state = connections
        .where((c) => c.provider == CalendarProvider.google)
        .toList();
  }

  /// Connects a new Google account and persists it.
  Future<bool> connectAccount(String userId) async {
    final email = await _service.connectAccount();
    if (email == null) return false;

    // Check if already connected
    if (state.any((c) => c.email == email)) return true;

    final connection = CalendarConnection(
      provider: CalendarProvider.google,
      email: email,
      connectedAt: DateTime.now().toUtc(),
    );

    // Add to Firestore
    await _firestore.collection('users').doc(userId).update({
      'calendarConnections': FieldValue.arrayUnion([connection.toMap()]),
    });

    state = [...state, connection];
    return true;
  }

  /// Removes a connected account.
  Future<void> removeAccount(String userId, String connectionId) async {
    final connection = state.firstWhere((c) => c.id == connectionId);
    await _firestore.collection('users').doc(userId).update({
      'calendarConnections': FieldValue.arrayRemove([connection.toMap()]),
    });
    state = state.where((c) => c.id != connectionId).toList();
    await _service.disconnect();
  }
}

final googleCalendarConnectionsProvider =
    StateNotifierProvider<GoogleCalendarConnectionNotifier, List<CalendarConnection>>((ref) {
  return GoogleCalendarConnectionNotifier(
    ref.watch(googleCalendarServiceProvider),
  );
});
```

Add imports:
```dart
import '../../../shared/models/calendar_connection.dart';
```

**Step 3: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 4: Commit**

```bash
git add lib/features/calendar/services/google_calendar_service.dart lib/features/calendar/providers/google_calendar_provider.dart
git commit -m "feat: update Google Calendar service for multi-account support

Supports connecting multiple Google accounts and syncing all of them.
Each connection is tracked with its own lastSync timestamp."
```

---

### Task 4: Update Settings Screen for Multi-Account UI

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`

**Context:** The settings screen currently shows a single toggle for Google Calendar (lines 89-105). Need to show a list of connected accounts with "Add Account" button.

**Step 1: Replace calendar connections section**

Replace `_buildCalendarConnectionsSection()` (lines 79-126) with a version that:
- Lists each connected Google account with email + last sync + remove button
- Shows "Add Google Account" button at the bottom
- Hides Microsoft for now (no client ID configured)

```dart
Widget _buildCalendarConnectionsSection(
  List<CalendarConnection> googleConnections,
  WidgetRef ref,
  String userId,
) {
  return _SettingsSection(
    title: 'Calendar Connections',
    icon: Icons.calendar_month_rounded,
    children: [
      // Connected Google accounts
      ...googleConnections.map((conn) => _CalendarAccountTile(
            email: conn.email,
            lastSync: conn.lastSync,
            onRemove: () {
              ref.read(googleCalendarConnectionsProvider.notifier)
                  .removeAccount(userId, conn.id);
            },
          )),

      // Add account button
      ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.lavenderLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.add_rounded, size: 18, color: AppColors.lavenderDark),
        ),
        title: const Text('Add Google Account'),
        subtitle: const Text('Connect another Google Calendar'),
        onTap: () {
          ref.read(googleCalendarConnectionsProvider.notifier)
              .connectAccount(userId);
        },
      ),
    ],
  );
}
```

Create a `_CalendarAccountTile` widget:

```dart
class _CalendarAccountTile extends StatelessWidget {
  const _CalendarAccountTile({
    required this.email,
    this.lastSync,
    required this.onRemove,
  });

  final String email;
  final DateTime? lastSync;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.lavenderLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.g_mobiledata_rounded, size: 20, color: AppColors.lavenderDark),
      ),
      title: Text(email, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        lastSync != null
            ? 'Last sync: ${DateFormat('MMM d, h:mm a').format(lastSync!.toLocal())}'
            : 'Not synced yet',
        style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: onRemove,
        color: AppColors.onSurfaceMuted,
      ),
    );
  }
}
```

**Step 2: Update the build method to pass new data**

Replace the watches for `googleCalendarConnectionProvider`/`microsoftCalendarConnectionProvider` with:

```dart
final googleConnections = ref.watch(googleCalendarConnectionsProvider);
```

And pass to the section builder:
```dart
_buildCalendarConnectionsSection(googleConnections, ref, user.uid),
```

**Step 3: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 4: Commit**

```bash
git add lib/features/settings/settings_screen.dart
git commit -m "feat: settings UI shows multi-account Google Calendar list

Shows connected accounts with email, last sync, and remove button.
Add Account button connects another Google account."
```

---

### Task 5: Wire "Sync Calendars" Quick Action

**Files:**
- Modify: `lib/features/home/home_screen.dart`

**Context:** The "Sync Calendars" chip (lines 576-587) currently shows a "coming soon" snackbar. Need to trigger actual sync.

**Step 1: Convert _QuickActionsRow to ConsumerWidget**

Change `_QuickActionsRow` from `StatelessWidget` to `ConsumerWidget` and update the "Sync Calendars" onTap:

```dart
class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow({required this.coupleId});
  final String? coupleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick actions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _ActionChip(
              icon: Icons.add_rounded,
              label: 'Add Block',
              onTap: () => context.go('/blocks/add'),
            ),
            const SizedBox(width: 10),
            _ActionChip(
              icon: Icons.sync_rounded,
              label: 'Sync Calendars',
              onTap: () async {
                final user = ref.read(currentUserProvider);
                if (user == null || coupleId == null) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Syncing calendars...')),
                );
                try {
                  final service = ref.read(googleCalendarServiceProvider);
                  await service.syncToFirestore(
                    userId: user.uid,
                    coupleId: coupleId!,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Calendars synced!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sync failed: $e')),
                    );
                  }
                }
              },
            ),
            const SizedBox(width: 10),
            _ActionChip(
              icon: Icons.view_timeline_rounded,
              label: 'All Windows',
              onTap: () => context.go('/overlap'),
            ),
          ],
        ),
      ],
    );
  }
}
```

Add imports for `googleCalendarServiceProvider` and `currentUserProvider`.

**Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 3: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "feat: wire Sync Calendars quick action to real sync"
```

---

### Task 6: Partner Timezone Display

**Files:**
- Modify: `lib/features/home/home_screen.dart`

**Context:** The `_TimezoneSection` (lines 85-150) has a TODO at line 123 to fetch partner's timezone. Currently shows only the user's clock.

**Step 1: Add partner data fetching**

In `_TimezoneSection`, fetch the partner's user document from Firestore using the couple model. Update the widget to show two clocks side by side when a partner exists:

```dart
class _TimezoneSection extends ConsumerWidget {
  const _TimezoneSection({
    required this.userTimezone,
    required this.coupleId,
    required this.couple,
    required this.currentUid,
  });

  final String userTimezone;
  final String? coupleId;
  final dynamic couple;
  final String currentUid;

  static String _cityFromTimezone(String tz) {
    final parts = tz.split('/');
    return parts.length > 1 ? parts.last.replaceAll('_', ' ') : tz;
  }

  static Duration _estimateOffset(String tz) {
    return DateTime.now().timeZoneOffset;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userCity = _cityFromTimezone(userTimezone);
    final userOffset = _estimateOffset(userTimezone);

    // Get partner UID from couple
    String? partnerUid;
    if (couple != null) {
      partnerUid = couple.userAUid == currentUid
          ? couple.userBUid
          : couple.userAUid;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Time zones',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TimezoneClock(
                city: userCity,
                utcOffset: userOffset,
                isMe: true,
                label: 'You',
              ),
            ),
            if (partnerUid != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _PartnerClock(partnerUid: partnerUid),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PartnerClock extends ConsumerWidget {
  const _PartnerClock({required this.partnerUid});
  final String partnerUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerAsync = ref.watch(_partnerProvider(partnerUid));
    return partnerAsync.when(
      data: (partner) {
        if (partner == null) return const SizedBox.shrink();
        final city = _TimezoneSection._cityFromTimezone(partner.timezone);
        final offset = _TimezoneSection._estimateOffset(partner.timezone);
        return TimezoneClock(
          city: city,
          utcOffset: offset,
          isMe: false,
          label: partner.displayName.split(' ').first,
        );
      },
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Fetches partner UserModel from Firestore.
final _partnerProvider = FutureProvider.family<UserModel?, String>((ref, uid) async {
  final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  if (!doc.exists) return null;
  return UserModel.fromFirestore(doc);
});
```

Add imports:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../shared/models/user_model.dart';
```

**Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 3: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "feat: display partner timezone clock on home screen"
```

---

### Task 7: Hide Microsoft Calendar & Clean Up Placeholder

**Files:**
- Modify: `lib/features/settings/settings_screen.dart` (already handled in Task 4 — Microsoft removed from UI)
- Modify: `lib/features/calendar/services/microsoft_calendar_service.dart`

**Context:** Microsoft client ID is `YOUR_MS_CLIENT_ID` (line 18). Since it's not configured, hide from UI (done in Task 4) and add a guard in the service.

**Step 1: Add guard to Microsoft service**

In `lib/features/calendar/services/microsoft_calendar_service.dart`, update `connect()` to check for placeholder:

```dart
Future<bool> connect() async {
  if (_clientId == 'YOUR_MS_CLIENT_ID') {
    debugPrint('Microsoft Calendar: client ID not configured');
    return false;
  }
  // ... existing connect logic
}
```

**Step 2: Commit**

```bash
git add lib/features/calendar/services/microsoft_calendar_service.dart
git commit -m "fix: guard Microsoft calendar against unconfigured client ID"
```

---

### Task 8: Implement Unpair Logic

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`
- File already exists: `lib/shared/services/pairing_service.dart` (has `unpair()` at lines 121-133)

**Context:** Settings screen has a TODO at line 398 for unpair logic. PairingService already has `unpair(couple)` method.

**Step 1: Wire the unpair button**

In `lib/features/settings/settings_screen.dart`, find the unpair button's onPressed (near line 398) and replace the TODO with:

```dart
onPressed: () async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Unpair from partner?'),
      content: const Text(
        'This will disconnect your calendars and remove the pairing. '
        'You can pair again later with a new invite code.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Unpair'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    final couple = ref.read(currentCoupleProvider);
    if (couple != null) {
      await ref.read(pairingServiceProvider).unpair(couple);
      ref.read(currentCoupleProvider.notifier).state = null;
      if (context.mounted) context.go('/pairing');
    }
  }
},
```

Add imports for `pairingServiceProvider`, `currentCoupleProvider`.

**Step 2: Run flutter analyze**

Run: `flutter analyze`
Expected: No errors

**Step 3: Commit**

```bash
git add lib/features/settings/settings_screen.dart
git commit -m "feat: implement unpair flow with confirmation dialog"
```

---

### Task 9: Deploy Cloud Functions

**Files:**
- Create: `.firebaserc`
- Modify: `firebase.json` (add firestore rules reference)
- Create: `firestore.rules`

**Context:** Cloud Functions are compiled but not deployed. Firebase project is `astra-488209`. Need `.firebaserc`, Firestore rules, and deployment.

**Step 1: Create .firebaserc**

Create `.firebaserc`:

```json
{
  "projects": {
    "default": "astra-488209"
  }
}
```

**Step 2: Create basic Firestore rules**

Create `firestore.rules`:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can read/write their own document
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      // Partners can read each other's data
      allow read: if request.auth != null;
    }

    // Couple members can read/write couple data
    match /couples/{coupleId} {
      allow read, write: if request.auth != null;
    }

    // Time blocks scoped to couple
    match /timeblocks/{coupleId}/blocks/{blockId} {
      allow read, write: if request.auth != null;
    }

    // Overlap windows scoped to couple
    match /overlaps/{coupleId}/{document=**} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions write
    }

    // Invite codes
    match /invites/{code} {
      allow read, write: if request.auth != null;
    }

    // Recurring windows
    match /couples/{coupleId}/recurringWindows/{windowId} {
      allow read: if request.auth != null;
      allow write: if false; // Only Cloud Functions write
    }

    // Pattern requests (trigger for manual detection)
    match /couples/{coupleId}/patternRequests/{requestId} {
      allow create: if request.auth != null;
    }
  }
}
```

**Step 3: Update firebase.json to include firestore**

Add firestore section to `firebase.json`:

```json
{
  "firestore": {
    "rules": "firestore.rules"
  },
  "functions": { ... existing ... },
  "flutter": { ... existing ... }
}
```

**Step 4: Set Gemini API key as Firebase config**

Run: `firebase functions:secrets:set GEMINI_API_KEY`
(User needs to provide their Gemini API key interactively)

**Step 5: Build and deploy functions**

Run from project root:
```bash
cd functions && npm run build && cd ..
firebase deploy --only functions,firestore:rules
```

**Step 6: Commit**

```bash
git add .firebaserc firestore.rules firebase.json
git commit -m "feat: add Firebase deployment config and Firestore rules"
```

---

### Task 10: Final Integration Verification

**Files:** None (verification only)

**Step 1: Run flutter analyze**

Run: `flutter analyze`
Expected: No issues

**Step 2: Run flutter test**

Run: `flutter test`
Expected: All tests pass

**Step 3: Build Android**

Run: `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

**Step 4: Build Web**

Run: `flutter build web`
Expected: Compiling complete

**Step 5: Verify Cloud Functions deployed**

Run: `firebase functions:list`
Expected: 4 functions listed (onBlockWrite, onOverlapWrite, detectPatterns, detectPatternsManual)

**Step 6: Commit any remaining fixes**

```bash
git add -A
git commit -m "chore: final phase 2 integration verification"
```
