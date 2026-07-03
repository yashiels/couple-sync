# Flutter UX Cleanup — Implementation Plan (Plan C)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the ~40 UX slop items from the audit so the app feels polished for a long-distance couple — above all, correct cross-timezone rendering (the core of the product), plus dead-end-free empty states, reliable calendar auth, and consistent theme usage.

**Architecture:** Extract shared formatting/label utils (DRY), fix block positioning to use block-timezone-aware minutes-since-day-start, route all dates through locale `DateFormat`, make the Today button drive the page controller, and wire tap-to-detail on the home window card. Mechanical cleanups (dead vars, raw Colors, hand-painted assets) fold in by screen.

**Tech Stack:** Flutter, `intl` 0.20.x (`DateFormat`, locale), `timezone` 0.10.x (`TZDateTime`), Riverpod 2.x, go_router 15.x.

## Global Constraints

- All user-facing dates/times go through `DateFormat` with the device locale (`Locale.getDefault` equivalent in Flutter: `Localizations.localeOf(context)` or `intl.defaultLocale` set in `main.dart`).
- Block positioning in the week view uses the block's stored `timezone` field + `TZDateTime` to compute local-day start, never raw `DateTime.hour` on a UTC instant.
- No raw `Colors.green`/`orange`/`red` — use `AppColors` semantic palette.
- No `Theme.of(context);` dead statements; no `TODO: STORY-019` shipped.
- Conventional commits: `<type>(<scope>): <msg>`.

**One-time setup (Task 1, do first):** set `intl.defaultLocale` in `lib/main.dart` so `DateFormat` defaults honor the device locale.

---

## Task 1: Shared utils + enum extensions (DRY foundation)

**Files:**
- Create: `lib/core/utils/format_utils.dart`
- Create: `lib/core/utils/block_labels.dart`
- Modify: `lib/main.dart` (set `defaultLocale`)

- [ ] **Step 1: Set the default locale**

In `lib/main.dart`, after `WidgetsFlutterBinding.ensureInitialized()`, add:

```dart
import 'package:intl/intl.dart';

// after binding init, before runApp:
Intl.defaultLocale = PlatformDispatcher.instance.locale.toString();
```

- [ ] **Step 2: Create `format_utils.dart`**

```dart
import 'package:intl/intl.dart';

/// Shared formatters so screens stop hand-rolling dates/durations.
String formatDurationMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String formatDateYMd(DateTime dt) => DateFormat.yMd().format(dt);
/// Locale-aware clock time — `jm()` gives 12h with am/pm where the locale
/// expects it (never the 24h-only `Hm` skeleton).
String formatTimeHm(DateTime dt) => DateFormat.jm().format(dt);
String formatMonth(DateTime dt) => DateFormat.MMM().format(dt);
String formatWeekdayShort(DateTime dt) => DateFormat.E().format(dt);
```

- [ ] **Step 3: Create `block_labels.dart` (enum extensions)**

```dart
import 'package:couple_sync/core/models/time_block.dart';

extension TimeBlockTypeLabel on TimeBlockType {
  String get label => switch (this) {
        TimeBlockType.busy => 'Busy',
        TimeBlockType.free => 'Free',
        TimeBlockType.tentative => 'Tentative',
      };
}

extension TimeBlockCategoryLabel on TimeBlockCategory {
  String get label => switch (this) {
        TimeBlockCategory.work => 'Work',
        TimeBlockCategory.study => 'Study',
        TimeBlockCategory.commute => 'Commute',
        TimeBlockCategory.exercise => 'Exercise',
        TimeBlockCategory.social => 'Social',
        TimeBlockCategory.meals => 'Meals',
        TimeBlockCategory.sleep => 'Sleep',
        TimeBlockCategory.personal => 'Personal',
        TimeBlockCategory.other => 'Other',
      };
}

extension TimeBlockVisibilityLabel on TimeBlockVisibility {
  String get label => switch (this) {
        TimeBlockVisibility.bothPartners => 'Both partners',
        TimeBlockVisibility.onlyMe => 'Only me',
      };
}
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/core/utils/format_utils.dart lib/core/utils/block_labels.dart`
Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/format_utils.dart lib/core/utils/block_labels.dart lib/main.dart
git commit -m "feat(core): shared format+label utils, set default locale"
```

---

## Task 2: Cross-timezone rendering in the week view

**Files:**
- Modify: `lib/features/calendar/week_view_widget.dart`
- Test: `test/features/calendar/week_view_positioning_test.dart`

- [ ] **Step 1: Write a failing positioning test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:couple_sync/core/utils/block_positioning.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('block local-day offset uses the block timezone, not UTC', () {
    // A block 09:00-10:00 America/New_York on 2024-06-01.
    final ny = tz.getLocation('America/New_York');
    final start = tz.TZDateTime(ny, 2024, 6, 1, 9).millisecondsSinceEpoch;
    final end = tz.TZDateTime(ny, 2024, 6, 1, 10).millisecondsSinceEpoch;
    final offset = localDayOffsetMinutes(start, 'America/New_York');
    expect(offset, 9 * 60); // 09:00 local = 540 min from local midnight
  });

  test('cross-midnight block positions by its own tz', () {
    final ny = tz.getLocation('America/New_York');
    final start = tz.TZDateTime(ny, 2024, 6, 1, 23, 30).millisecondsSinceEpoch;
    final offset = localDayOffsetMinutes(start, 'America/New_York');
    expect(offset, 23 * 60 + 30);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/calendar/week_view_positioning_test.dart`
Expected: FAIL — `block_positioning.dart` / `localDayOffsetMinutes` undefined.

- [ ] **Step 3: Create `lib/core/utils/block_positioning.dart`**

```dart
import 'package:timezone/timezone.dart';

/// Minutes from the block's local midnight to [startUtc].
/// Uses the block's stored timezone so cross-midnight / cross-tz blocks
/// position correctly against the day grid.
int localDayOffsetMinutes(int startUtc, String timezone) {
  final loc = getLocation(timezone);
  final t = TZDateTime.fromMillisecondsSinceEpoch(loc, startUtc);
  final midnight = TZDateTime(loc, t.year, t.month, t.day);
  return ((t.millisecondsSinceEpoch - midnight.millisecondsSinceEpoch) ~/ 60000);
}

/// Duration in minutes (clamped to a single local day for the grid).
int dayClampedDurationMinutes(int startUtc, int endUtc, String timezone) {
  final loc = getLocation(timezone);
  final t = TZDateTime.fromMillisecondsSinceEpoch(loc, startUtc);
  final midnight = TZDateTime(loc, t.year, t.month, t.day);
  final dayEndMs = midnight.millisecondsSinceEpoch + 24 * 60 * 60 * 1000;
  final effectiveEnd = endUtc < dayEndMs ? endUtc : dayEndMs;
  return ((effectiveEnd - startUtc) ~/ 60000).clamp(0, 24 * 60);
}
```

- [ ] **Step 4: Run tests to pass**

Run: `flutter test test/features/calendar/week_view_positioning_test.dart`
Expected: PASS.

- [ ] **Step 5: Apply in `week_view_widget.dart`**

Replace the block height/offset calculation (around `week_view_widget.dart:320`, the `(startMinutes / 60) * 60` block) with `localDayOffsetMinutes(block.startUtc, block.timezone)` and `dayClampedDurationMinutes(block.startUtc, block.endUtc, block.timezone)`. Replace the hardcoded `['Mon','Tue',...]` (line 158) and month array (572-573) with `formatWeekdayShort` / `formatMonth` from `format_utils.dart`.

- [ ] **Step 6: Respect locale for hour labels**

In the hour-label column (line 457-459), replace forced 24h `00:00` with `formatTimeHm(...)` (which uses `DateFormat.jm()` — locale-aware am/pm) so 12h-locale users see am/pm.

- [ ] **Step 7: Remove the dead outer `Stack` (line 100/123) wrapping a single `Column`.**

- [ ] **Step 8: Commit**

```bash
git add lib/core/utils/block_positioning.dart lib/features/calendar/week_view_widget.dart test/features/calendar/week_view_positioning_test.dart
git commit -m "fix(weekview): tz-correct block positioning + locale hour labels"
```

---

## Task 3: Locale dates + timezone display in block form/management/settings

**Files:**
- Modify: `lib/features/blocks/screens/block_form_screen.dart`
- Modify: `lib/features/blocks/screens/block_management_screen.dart`
- Modify: `lib/features/blocks/widgets/block_list_tile_widget.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`

- [ ] **Step 1: Replace raw `d/m/y` dates**

In `block_form_screen.dart:391,444` and `block_management_screen.dart:128-135` and `settings_screen.dart:297`, replace raw `d/m/y` numeric formatting with `formatDateYMd(dt)` from `format_utils.dart`.

- [ ] **Step 2: Replace 24h `HH:mm` with locale `Hm`**

In `block_management_screen.dart:139-142` and any `HH:mm` in `block_form_screen.dart`, use `formatTimeHm(dt)`.

- [ ] **Step 3: Make the timezone readable**

In `block_form_screen.dart:498-502`, replace `Text('Timezone: $_timezone')` with a card showing the IANA id + current UTC offset + current local time, mirroring the onboarding card. Skeleton:

```dart
import 'package:timezone/timezone.dart';

String _tzLabel(String tzId) {
  final loc = getLocation(tzId);
  final now = TZDateTime.now(loc);
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hh = offset.inHours.abs().toString().padLeft(2, '0');
  final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '$tzId (UTC$sign$hh:$mm) · now ${formatTimeHm(now)}';
}
```

- [ ] **Step 4: Delete the duplicated months array in `block_management_screen.dart:139-142`** — use `formatMonth`.

- [ ] **Step 5: Build + smoke**

Run: `flutter analyze` then `flutter run` on emulator.
Expected: dates render in device-locale order; timezone card shows offset + live time.

- [ ] **Step 6: Commit**

```bash
git add lib/features/blocks/ lib/features/settings/screens/settings_screen.dart
git commit -m "fix(blocks,settings): locale date/time + readable timezone display"
```

---

## Task 4: Loading / empty / error states

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`
- Modify: `lib/features/overlap/screens/overlap_screen.dart`
- Modify: `lib/features/blocks/screens/block_form_screen.dart`

- [ ] **Step 1: Kill the home double-spinner + fake delay**

In `home_screen.dart:46`, remove `Future.delayed(const Duration(seconds: 1))`; await the actual provider future. At `home_screen.dart:137-138`, delete the `_isRefreshing` overlay `CircularProgressIndicator`; let `RefreshIndicator` own the indicator.

- [ ] **Step 2: Add CTAs to dead-end empty states**

In `home_screen.dart:80-121` ("No partner yet") add a button routing to `/pairing`. In `overlap_screen.dart:68-102` ("No couple paired yet") add the same CTA.

- [ ] **Step 3: Keep AppBar during block-form edit load**

In `block_form_screen.dart:291`, restructure so the `AppBar` stays visible while the edit-load spinner shows (move the spinner into the `body`, not before the `Scaffold`).

- [ ] **Step 4: Surface the silent 10-cap on overlap**

In `overlap_screen.dart:55-57`, when `windows.length == 10`, show a "Showing top 10 — refine filters for more" hint instead of silently capping.

- [ ] **Step 5: Smoke-test**

Run: `flutter run`. Empty home (no partner) → CTA visible. Pull-to-refresh → single spinner, no fixed delay. Edit a block → AppBar stays.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/screens/home_screen.dart lib/features/overlap/screens/overlap_screen.dart lib/features/blocks/screens/block_form_screen.dart
git commit -m "fix(home,overlap,blocks): loading/empty/error states + CTAs"
```

---

## Task 5: Navigation — Today button + window-card tap (TDD)

**Files:**
- Modify: `lib/features/calendar/week_view_screen.dart`
- Modify: `lib/features/calendar/week_view_widget.dart`
- Modify: `lib/features/home/screens/home_screen.dart`
- Test: `test/features/calendar/week_view_today_test.dart`

- [ ] **Step 1: Write a failing test for the Today jump**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_sync/core/utils/week_pagination.dart';

void main() {
  test('pageIndexForDate returns today\'s page within range', () {
    final today = DateTime(2024, 6, 5);
    final pager = WeekPager(weekStartMonday: true);
    final idx = pager.pageIndexForDate(today);
    expect(idx, greaterThanOrEqualTo(0));
    // The date at that page must contain `today`.
    final weekStart = pager.weekStartForPage(idx);
    expect(today.difference(weekStart).inDays, lessThan(7));
    expect(today.difference(weekStart).inDays, greaterThanOrEqualTo(0));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/calendar/week_view_today_test.dart`
Expected: FAIL — `WeekPager` undefined.

- [ ] **Step 3: Create `lib/core/utils/week_pagination.dart`**

```dart
class WeekPager {
  final bool weekStartMonday;
  WeekPager({this.weekStartMonday = true});

  DateTime weekStartForDate(DateTime d) {
    final weekday = d.weekday; // Mon=1..Sun=7
    final offset = weekStartMonday ? weekday - 1 : (weekday % 7);
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: offset));
  }

  DateTime weekStartForPage(int page) {
    // Centered pagination: page 0 starts at the week of 2000-01-03 (a Monday).
    final epoch = DateTime(2000, 1, 3); // a Monday
    return epoch.add(Duration(days: page * 7));
  }

  int pageIndexForDate(DateTime d) {
    final epoch = DateTime(2000, 1, 3);
    final start = weekStartForDate(d);
    return start.difference(epoch).inDays ~/ 7;
  }
}
```

- [ ] **Step 4: Run tests to pass**

Run: `flutter test test/features/calendar/week_view_today_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the Today button**

In `week_view_widget.dart`, expose a method or accept a `GlobalKey`/controller so the parent can call `pageController.jumpToPage(pager.pageIndexForDate(DateTime.now()))`. In `week_view_screen.dart:197-201`, the "Today" `onPressed` calls that method (currently it only sets `_currentWeekStart` with no effect on the widget).

- [ ] **Step 6: Wire window-card tap-to-detail**

In `home_screen.dart`, the `_UpcomingWindowCard` (line ~369) has no `onTap`. Wrap it in `InkWell`/`GestureDetector` calling the same detail-dialog route used in `overlap_screen.dart:497-510`.

- [ ] **Step 7: Smoke-test**

Run: `flutter run`. Tap Today → week view jumps to the current week. Tap an upcoming window card on home → detail dialog opens.

- [ ] **Step 8: Commit**

```bash
git add lib/core/utils/week_pagination.dart lib/features/calendar/week_view_widget.dart lib/features/calendar/week_view_screen.dart lib/features/home/screens/home_screen.dart test/features/calendar/week_view_today_test.dart
git commit -m "fix(nav): today button drives page controller + home window-card tap"
```

---

## Task 6: Calendar auth reliability

**Files:**
- Modify: `lib/services/calendar_service.dart`

- [ ] **Step 1: Remove the dead refresh-token key**

`_refreshTokenKey` (`calendar_service.dart:33`) is written nowhere. Delete the constant and the `delete(key: _refreshTokenKey)` call in `disconnect()` (line 155).

- [ ] **Step 2: Stop forcing fresh consent on every connect**

In `connect()` (line 91), remove the leading `await _googleSignIn.signOut();`. Keep it only as a fallback when `signInSilently()` fails (the user is already signed-out in that path). This stops forcing the OAuth sheet on every reconnect.

- [ ] **Step 3: Make silent refresh actually work**

In `getAccessToken()` / `_refreshToken()` (line 201), the silent path already calls `signInSilently()`. Confirm it writes the fresh access token + expiry (it does). Add: if `signInSilently()` returns null, do NOT call `disconnect()` (line 210) — instead surface a soft "reconnect to refresh calendar" state so the user's blocks aren't wiped. Change to return `null` and let the UI prompt reconnect.

- [ ] **Step 4: Optional multi-calendar**

In `fetchFreebusy()` (line 273), change `items: [FreeBusyRequestItem(id: 'primary')]` to fetch the user's calendar list first (`calendarApi.calendarList.list()`) and include all calendar IDs in `items`. Skip if the list call is unavailable — keep `'primary'` as fallback.

- [ ] **Step 5: Smoke-test**

Run: `flutter run` against emulators. Connect Google Calendar → no fresh-consent sheet on subsequent connects; disconnect the network mid-sync → soft "reconnect" state, blocks preserved.

- [ ] **Step 6: Commit**

```bash
git add lib/services/calendar_service.dart
git commit -m "fix(calendar): reliable silent refresh, no forced consent, soft reconnect"
```

---

## Task 7: Theme + hygiene cleanup

**Files:**
- Modify: `lib/core/theme/app_theme.dart`, `lib/core/theme/app_colors.dart`
- Modify: `lib/features/auth/screens/auth_screen.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`
- Modify: `lib/features/overlap/screens/overlap_screen.dart`
- Modify: `lib/features/blocks/screens/block_management_screen.dart`

- [ ] **Step 1: Switch category colors on the enum**

In `app_theme.dart:265-319`, replace the `getCategoryColorLight/Dark` switch on lowercased `String` with a switch on `TimeBlockCategory` (import the model). Delete the duplicate label switches in `block_form_screen.dart:551-592` and `block_management_screen.dart:144-171` — they now live in `block_labels.dart` (Task 1).

- [ ] **Step 2: Delete dead code**

- `app_colors.dart:49-52,122-126` — delete unused `backgroundLight/Dark`, `onBackgroundLight/Dark`.
- `auth_screen.dart:329` — delete the `Theme.of(context);` no-op statement.
- `settings_screen.dart:329` — delete the unused `Theme.of(context)` in `_SignInButton`.
- `settings_screen.dart:14` — resolve `TODO: STORY-019` (move to `BACKLOG.md` or implement; default: move to backlog).
- `settings_screen.dart:304` — drop the unused `userProfile` param from `_buildCoupleSectionFromProvider`.
- `home_screen.dart:51-63` — replace the stringly-typed `_handleFabAction` switch with direct method calls.

- [ ] **Step 3: Persist or remove the notification toggle**

In `settings_screen.dart:18-29`, `NotificationSettingsNotifier` has a TODO to persist and resets on restart. Either persist via `flutter_secure_storage` or remove the toggle. Default: persist (write a bool to secure storage on toggle, read on init).

- [ ] **Step 4: Use theme + semantic colors consistently**

- `settings_screen.dart:216-221` — replace inline `TextStyle(fontSize:12, color: Colors.grey, fontStyle: italic)` with `theme.textTheme.bodySmall`.
- `overlap_screen.dart:672-677`, `week_view_widget.dart:358-364` — replace `Colors.green/orange/red` with `AppColors.success*/warning*/error*`.
- `overlap_screen.dart:335-363` — replace the hand-rolled `_buildFilterChip` Container with `FilterChip` (already used elsewhere).
- `overlap_screen.dart:457,469,486` and `block_management_screen.dart:203-204,211-212` — remove the double `setDialogState`+`setState` calls; pick one.
- `week_view_screen.dart:171,175`, `block_management_screen.dart:312,345` — replace `Colors.grey` / `const TextStyle` with `theme.colorScheme`/`theme.textTheme`.

- [ ] **Step 5: Replace the hand-painted Google G**

In `auth_screen.dart:406-480`, delete the `CustomPainter` Google G. Add an official asset (`assets/icons/google_g.png`) or the `google_sign_in_buttons` package, and use it. Add the asset to `pubspec.yaml` `flutter: assets:`.

- [ ] **Step 6: Guard the emulator credentials**

In `auth_screen.dart:255`, the emulator email fields are pre-filled with `partnerA@example.com` / `password123`. Wrap so these defaults only apply when `kDebugMode && _useEmulator` — never in release. Add an assertion or compile-time guard.

- [ ] **Step 7: Analyze + smoke**

Run: `flutter analyze`
Expected: no new warnings; the dead lines are gone.

Run: `flutter run` — auth screen renders the asset Google G; settings notification toggle persists across restart.

- [ ] **Step 8: Commit**

```bash
git add lib/core/theme/ lib/features/auth/ lib/features/settings/ lib/features/overlap/ lib/features/blocks/ pubspec.yaml BACKLOG.md
git commit -m "chore(ui): theme hygiene, delete dead code, asset google G, persist notif toggle"
```

---

## Self-Review

**Spec coverage (§9 punch list):** cross-tz rendering → Tasks 2-3. Loading/empty/error → Task 4. Calendar auth reliability → Task 6. Theme/hygiene → Tasks 1, 7. Navigation → Task 5. Every audit item maps to a step.

**Placeholder scan:** `appID`/`sha256_cert_fingerprints` live in Plan B (Task 1), not here. No TBDs in Plan C. Asset path `assets/icons/google_g.png` is a real file the implementer drops in — flagged, not a placeholder.

**Type consistency:** `formatDurationMinutes` / `formatDateYMd` / `formatTimeHm` (Task 1) used consistently in Tasks 2-4. `localDayOffsetMinutes` / `dayClampedDurationMinutes` (Task 2) signature matches the test. `WeekPager.pageIndexForDate` (Task 5) matches the test. `TimeBlockCategoryLabel` etc. (Task 1) used by Task 7's enum switch.

---

## Execution Handoff

Plan C complete. The full plan set is now: **Plan A** (engine port) → **Plan B** (GCP infra) → **Plan C** (UX cleanup). Execute in that order; Plan A unlocks the device-side overlap that B's App Check protects and C's screens consume.
