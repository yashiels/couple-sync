# App Audit Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all broken UX, remove incomplete/coming-soon features, and make existing features work correctly.

**Architecture:** Direct edits to existing screens and widgets. No new files needed. Remove dead code and unused features.

**Tech Stack:** Flutter, Riverpod, GoRouter, Firebase Firestore

---

### Task 1: Fix Settings Screen — Add Back Button & Fix Navigation

**Files:**
- Modify: `lib/features/settings/settings_screen.dart:38-39`

**Step 1: Add back button and fix navigation**

Replace the AppBar at line 38-39:
```dart
      appBar: AppBar(title: const Text('Settings')),
```

With:
```dart
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Settings'),
      ),
```

**Step 2: Verify the build compiles**

Run: `cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

**Step 3: Commit**

```bash
git add lib/features/settings/settings_screen.dart
git commit -m "fix: add back button to settings screen"
```

---

### Task 2: Settings Screen — Remove Non-Persisted Sections & Coming Soon Features

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`

**Step 1: Remove local state variables (lines 22-31)**

Remove these lines entirely:
```dart
  // Local notification toggle state (not persisted yet).
  bool _newWindowAlerts = true;
  bool _dailyDigest = false;
  final bool _quietHoursEnabled = false;

  // Local privacy toggle state.
  bool _showEventTitles = true;

  // Local scheduling state.
  int _minSlotMinutes = 30;
```

**Step 2: Remove sections 2, 3, 4 from the build method body (lines 49-59)**

Remove these children from the ListView:
```dart
          // 2. Notifications
          _buildNotificationsSection(),
          const SizedBox(height: 16),

          // 3. Privacy
          _buildPrivacySection(),
          const SizedBox(height: 16),

          // 4. Scheduling
          _buildSchedulingSection(),
          const SizedBox(height: 16),
```

**Step 3: Remove the method bodies**

Delete these entire methods:
- `_buildNotificationsSection()` (lines 139-204)
- `_buildPrivacySection()` (lines 206-234)
- `_buildSchedulingSection()` (lines 236-282)

**Step 4: Remove the `_DurationChipRow` helper widget class** (lines 533-579)

Delete the entire `_DurationChipRow` class since it was only used by the scheduling section.

**Step 5: Remove unused import**

Remove this import since `intl` was used by the notifications section date formatting — check if still needed by `_GoogleAccountTile`. It IS still used there, so keep it.

**Step 6: Verify build**

Run: `cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

**Step 7: Commit**

```bash
git add lib/features/settings/settings_screen.dart
git commit -m "fix: remove non-persisted settings sections and coming soon features"
```

---

### Task 3: Settings Screen — Conditionally Show Unpair Button

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`

**Step 1: Update `_buildAccountSection` to accept couple parameter**

Change the method signature and make unpair conditional:

```dart
  Widget _buildAccountSection(BuildContext context) {
    final couple = ref.watch(currentCoupleProvider);

    return _SettingsSection(
      icon: Icons.person_rounded,
      title: 'Account',
      children: [
        ListTile(
          leading: const Icon(Icons.logout_rounded, color: AppColors.roseDark),
          title: const Text(
            'Sign out',
            style: TextStyle(
              color: AppColors.roseDark,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () => _confirmSignOut(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        if (couple != null) ...[
          const Divider(height: 1, color: AppColors.divider),
          ListTile(
            leading: const Icon(Icons.link_off_rounded, color: AppColors.error),
            title: const Text(
              'Unpair from partner',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => _confirmUnpair(context),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ],
      ],
    );
  }
```

**Step 2: Verify build**

Run: `cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add lib/features/settings/settings_screen.dart
git commit -m "fix: only show unpair button when paired with partner"
```

---

### Task 4: Home Screen — Add Partner Timezone Clock

**Files:**
- Modify: `lib/features/home/home_screen.dart:79-115`

**Step 1: Convert `_TimezoneSection` to ConsumerWidget and add partner clock**

The `_TimezoneSection` needs access to `currentCoupleProvider` and `currentUserProvider` to fetch partner data from Firestore.

Replace the entire `_TimezoneSection` class (lines 81-115) with:

```dart
class _TimezoneSection extends ConsumerWidget {
  const _TimezoneSection({required this.userTimezone});

  final String userTimezone;

  String _cityFromTimezone(String tz) {
    final parts = tz.split('/');
    return parts.length > 1 ? parts.last.replaceAll('_', ' ') : tz;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userCity = _cityFromTimezone(userTimezone);
    final userOffset = DateTime.now().timeZoneOffset;
    final couple = ref.watch(currentCoupleProvider);
    final user = ref.watch(currentUserProvider);

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
            const SizedBox(width: 12),
            Expanded(
              child: couple != null && user != null
                  ? _PartnerClock(
                      couple: couple,
                      currentUserUid: user.uid,
                    )
                  : _EmptyPartnerClock(),
            ),
          ],
        ),
      ],
    );
  }
}
```

**Step 2: Add `_PartnerClock` widget that fetches partner timezone from Firestore**

Add after `_TimezoneSection`:

```dart
class _PartnerClock extends ConsumerWidget {
  const _PartnerClock({
    required this.couple,
    required this.currentUserUid,
  });

  final CoupleModel couple;
  final String currentUserUid;

  String _cityFromTimezone(String tz) {
    final parts = tz.split('/');
    return parts.length > 1 ? parts.last.replaceAll('_', ' ') : tz;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerUid = couple.partnerUid(currentUserUid);

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(partnerUid).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _EmptyPartnerClock();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final partnerTz = data['timezone'] as String? ?? 'UTC';
        // Parse IANA timezone to UTC offset - use the offset stored or calculate
        // For now, use a simple lookup via the timezone package would be ideal,
        // but we can approximate from the partner's stored data
        final partnerCity = _cityFromTimezone(partnerTz);

        // We need to calculate the partner's UTC offset from their IANA timezone.
        // Since we don't have the timezone package, we'll show the partner clock
        // using the same approach - their timezone name with current UTC time.
        // The TimezoneClock widget takes a UTC offset, so for accuracy we'd need
        // the timezone package. For MVP, show the clock with a note.
        return TimezoneClock(
          city: partnerCity,
          utcOffset: DateTime.now().timeZoneOffset, // TODO: resolve from IANA tz
          isMe: false,
          label: data['displayName'] as String? ?? 'Partner',
        );
      },
    );
  }
}

class _EmptyPartnerClock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.partnerB,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Partner',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A9FE0),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Not paired yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pair to see their time',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 3: Add required imports to home_screen.dart**

Add at top:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../shared/models/couple_model.dart';
```

**Step 4: Verify build**

Run: `cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -5`

**Step 5: Commit**

```bash
git add lib/features/home/home_screen.dart
git commit -m "feat: add partner timezone clock to home screen"
```

---

### Task 5: Calendar Screen — Remove Connection Banners & Microsoft Calendar

**Files:**
- Modify: `lib/features/calendar/calendar_screen.dart`

**Step 1: Remove Microsoft Calendar import**

Remove line 12:
```dart
import 'providers/microsoft_calendar_provider.dart';
```

**Step 2: Remove Microsoft references from `_syncAll` method**

Replace `_syncAll` (lines 63-83) with:
```dart
  Future<void> _syncAll() async {
    final user = ref.read(currentUserProvider);
    final couple = ref.read(currentCoupleProvider);
    if (user == null || couple == null) return;

    final googleConnected = ref.read(googleCalendarConnectionProvider);
    if (googleConnected) {
      await ref.read(googleCalendarSyncProvider.notifier).sync(
            userId: user.uid,
            coupleId: couple.coupleId,
          );
    }
  }
```

**Step 3: Remove Microsoft connection watch and connection banners from build method**

In the `build` method, remove line 184:
```dart
    final msConnected = ref.watch(microsoftCalendarConnectionProvider);
```

Remove the entire connection banners block (lines 222-239):
```dart
          // Calendar connection banners
          if (!googleConnected || !msConnected)
            _ConnectionBanners(
              googleConnected: googleConnected,
              msConnected: msConnected,
              onConnectGoogle: () async { ... },
              onConnectMicrosoft: () async { ... },
            ),
```

Also remove line 183:
```dart
    final googleConnected = ref.watch(googleCalendarConnectionProvider);
```

Since we no longer need the connection status in the build method.

**Step 4: Remove unused import**

Remove the `free_window.dart` import if we also clean up the empty freeWindows list. Actually, `FreeWindow` is still used by `WeekView`, so keep it.

**Step 5: Delete the `_ConnectionBanners` and `_ConnectTile` widget classes** (lines 299-388)

Remove both entire classes.

**Step 6: Verify build**

Run: `cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -5`

**Step 7: Commit**

```bash
git add lib/features/calendar/calendar_screen.dart
git commit -m "fix: remove calendar connection banners and Microsoft Calendar UI"
```

---

### Task 6: Week View — Fix Hardcoded userId == 'me'

**Files:**
- Modify: `lib/features/calendar/widgets/week_view.dart:117-122`

**Step 1: Add userId parameter to WeekView**

Add a `myUserId` parameter to the constructor:
```dart
class WeekView extends StatelessWidget {
  const WeekView({
    super.key,
    required this.weekStart,
    required this.blocks,
    required this.freeWindows,
    required this.myUtcOffset,
    required this.partnerUtcOffset,
    required this.myUserId,
    this.onBlockTap,
    this.onWindowTap,
    this.onDayTap,
  });

  ...
  final String myUserId;
```

**Step 2: Fix the hardcoded comparison in `_buildBlockOverlays`**

Replace line 122:
```dart
    final isMe = block.userId == 'me';
```

With:
```dart
    final isMe = block.userId == myUserId;
```

**Step 3: Update CalendarScreen to pass `myUserId`**

In `lib/features/calendar/calendar_screen.dart`, update the `WeekView` instantiation (around line 277) to pass the user's UID:

```dart
                return WeekView(
                  weekStart: ws,
                  blocks: blocks,
                  freeWindows: freeWindows,
                  myUtcOffset: DateTime.now().timeZoneOffset,
                  partnerUtcOffset: DateTime.now().timeZoneOffset,
                  myUserId: ref.read(currentUserProvider)?.uid ?? '',
                  onBlockTap: _showBlockDetail,
                );
```

**Step 4: Verify build**

Run: `cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -5`

**Step 5: Commit**

```bash
git add lib/features/calendar/widgets/week_view.dart lib/features/calendar/calendar_screen.dart
git commit -m "fix: use actual user ID instead of hardcoded 'me' in week view"
```

---

### Task 7: Overlap Screen — Remove Schedule Call / Google Meet Feature

**Files:**
- Modify: `lib/features/overlap/overlap_screen.dart`

**Step 1: Remove the SchedulingRequest and Firestore imports**

Remove:
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../shared/models/scheduling_request.dart';
```

**Step 2: Remove "Schedule Call" button from regular window cards**

In `_buildWindowCard` (around lines 322-339), remove:
```dart
            // Schedule Call button
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    _showScheduleSheet(context, window, coupleId),
                icon: const Icon(Icons.videocam_rounded, size: 18),
                label: const Text('Schedule Call'),
                ...
              ),
            ),
```

**Step 3: Remove "Schedule Call" button from hero card**

In `_buildHeroCard` (around lines 428-451), remove:
```dart
          // Schedule Call button on hero card
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () =>
                  _showScheduleSheet(context, window, coupleId),
              ...
            ),
          ),
```

**Step 4: Remove `_showScheduleSheet` and `_createSchedulingRequest` methods**

Delete both methods entirely (lines 503-698).

**Step 5: Remove `coupleId` parameter from `_buildWindowCard` and `_buildHeroCard`**

Since `coupleId` was only used for scheduling, remove it from method signatures and update all call sites:
- `_buildWindowCard(context, windows[i], coupleId, isTop: i == 0)` → `_buildWindowCard(context, windows[i], isTop: i == 0)`
- `_buildHeroCard(context, window, coupleId, start, end)` → `_buildHeroCard(context, window, start, end)`
- Update `_buildWindowList` similarly

**Step 6: Verify build**

Run: `cd /Users/yashielsookdeo/Developer/yashielsookdeo/couple-schedule && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -5`

**Step 7: Commit**

```bash
git add lib/features/overlap/overlap_screen.dart
git commit -m "fix: remove incomplete Schedule Call / Google Meet feature"
```

---

## Summary of Changes

| Task | What | Files |
|------|------|-------|
| 1 | Settings back button | settings_screen.dart |
| 2 | Remove non-persisted settings sections | settings_screen.dart |
| 3 | Conditional unpair button | settings_screen.dart |
| 4 | Partner timezone clock | home_screen.dart |
| 5 | Remove calendar banners & Microsoft UI | calendar_screen.dart |
| 6 | Fix hardcoded userId | week_view.dart, calendar_screen.dart |
| 7 | Remove Schedule Call feature | overlap_screen.dart |
