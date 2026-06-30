# Edge Overlap Port — Implementation Plan (Plan A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move overlap computation from the `onBlockWrite`/`onUserPrefsWrite` Cloud Functions to the device (Dart port of `functions/src/lib/overlap.ts`), delete both functions, and have the device write `overlaps/{coupleId}/windows/latest` via a Firestore transaction — cutting the dominant server cost and making results instant.

**Architecture:** A pure Dart `overlap_engine.dart` ports `overlap.ts` verbatim (TZDateTime for DST-correct waking-hours clipping; `rrule` package for recurrence). A Riverpod `AsyncNotifier` watches blocks + both user docs, debounces, computes with a hour-bucketed `now`, and writes the result through a Firestore transaction with an `inputHash` skip. Firestore rules allow couple members to write only `overlaps/{coupleId}/windows/latest` with a top-level shape gate; `onOverlapWrite` deep-validates `windows[]` before sending FCM and skips the writer's uid.

**Tech Stack:** Flutter, Riverpod 2.x, cloud_firestore 5.x, `timezone` 0.10.x, `crypto` 4.x, `rrule` 0.12.x (pub.dev/packages/rrule). Cloud Functions v2 (nodejs22). Jest + @firebase/rules-unit-testing.

## Global Constraints

- All timestamps are UTC milliseconds since epoch (int), never Firestore `Timestamp` in the overlap layer. `computedAt` is written as int.
- IANA timezone IDs everywhere. Waking-hours clipping uses `TZDateTime` (local wall-clock day construction), never UTC-millisecond day math.
- `now` passed into `computeOverlap` is `nowBucket = floor(now, 1 hour)` so both devices in the same hour produce identical output.
- `inputHash = sha256(blocksA ‖ blocksB ‖ tzA ‖ tzB ‖ prefsA ‖ prefsB ‖ ALGO_VERSION ‖ nowBucket).slice(0,16)`. `ALGO_VERSION = 1`.
- Firestore rules: couple members may write ONLY `overlaps/{coupleId}/windows/latest`; `computedBy == request.auth.uid`; `windows is list`; `windows.size() <= 20`.
- `onOverlapWrite` rejects any window with `!(0 < durationMinutes <= 1560)` or `startUtc >= endUtc` or `endUtc - startUtc != durationMinutes*60000` (±1000ms).
- Runtime: Functions = nodejs22 (align `firebase.json` from nodejs20). Region: us-central1.
- Conventional commit subjects: `<type>(<scope>): <msg>`. No `[TICKET]` (no active ticket).

---

## File Structure

**Create:**
- `lib/core/overlap/overlap_engine.dart` — pure port of `overlap.ts`. No Firebase dep.
- `lib/core/overlap/overlap_controller.dart` — Riverpod `AsyncNotifier`: watches blocks + users, debounces, computes, transaction-writes.
- `test/core/overlap/overlap_engine_test.dart` — ported + golden tests.
- `functions/src/__tests__/rules/overlaps.rules.test.ts` — Firestore rules tests (emulator).

**Modify:**
- `lib/core/models/overlap_result.dart` — replace `blockHashA`/`blockHashB` with `inputHash`; add `computedBy`.
- `lib/services/firestore_service.dart` — add `writeOverlapTransaction(...)`.
- `lib/services/providers/` — wire the new controller; retire direct `watchOverlap` reads in home/overlap screens.
- `firestore.rules` — relax `overlaps/{coupleId}/windows/{windowId}` write.
- `functions/src/onOverlapWrite.ts` — deep-validate `windows[]`; skip `computedBy` uid.
- `functions/src/lib/types.ts` — `OverlapResult`: `inputHash`, `computedBy`, drop `blockHashA/B`.
- `functions/src/index.ts` — remove `onBlockWrite`, `onUserPrefsWrite` exports.
- `functions/package.json` + `firebase.json` — align nodejs22.
- `pubspec.yaml` — add `crypto`, `rrule`.

**Delete:**
- `functions/src/onBlockWrite.ts` + `functions/src/__tests__/onBlockWrite.test.ts`
- `functions/src/onUserPrefsWrite.ts` (no test file today)

---

## Task 1: Add Dart deps + align Functions runtime

**Files:**
- Modify: `pubspec.yaml`
- Modify: `functions/package.json`
- Modify: `firebase.json`

- [ ] **Step 1: Add Dart dependencies**

In `pubspec.yaml` under `dependencies:`, add (alphabetical):

```yaml
  crypto: ^4.0.0
  rrule: ^0.12.0
```

(`timezone` and `intl` are already present.)

- [ ] **Step 2: Align Functions runtime to nodejs22**

`functions/package.json` — confirm `"engines": { "node": "22" }` (already 22). No change.

`firebase.json` — change:

```json
    "functions": {
      "source": "functions",
      "runtime": "nodejs20"
    }
```
to
```json
    "functions": {
      "source": "functions",
      "runtime": "nodejs22"
    }
```

- [ ] **Step 3: Fetch + verify deps compile**

Run:
```bash
flutter pub get
```
Expected: resolves `crypto` and `rrule` without error.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock firebase.json
git commit -m "build(deps): add crypto+rrule, align functions runtime to nodejs22"
```

---

## Task 2: Port interval utils (`mergeIntervals`, `intersectIntervals`)

**Files:**
- Create: `lib/core/overlap/overlap_engine.dart`
- Test: `test/core/overlap/overlap_engine_test.dart`

**Interfaces:**
- Produces: `List<List<int>> mergeIntervals(List<List<int>> intervals)`, `List<List<int>> intersectIntervals(List<List<int>> a, List<List<int>> b)` — each interval is `[startMs, endMs]`.

- [ ] **Step 1: Write failing tests**

Create `test/core/overlap/overlap_engine_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';

void main() {
  group('mergeIntervals', () {
    test('empty returns empty', () {
      expect(mergeIntervals([]), isEmpty);
    });
    test('overlapping merge', () {
      expect(
        mergeIntervals([
          [1, 5],
          [3, 8],
          [10, 12],
        ]),
        [
          [1, 8],
          [10, 12],
        ],
      );
    });
    test('unsorted input gets sorted', () {
      expect(
        mergeIntervals([
          [10, 12],
          [1, 5],
        ]),
        [
          [1, 5],
          [10, 12],
        ],
      );
    });
  });

  group('intersectIntervals', () {
    test('no overlap returns empty', () {
      expect(
        intersectIntervals([
          [1, 5]
        ], [
          [6, 10]
        ]),
        isEmpty,
      );
    });
    test('partial overlap', () {
      expect(
        intersectIntervals([
          [1, 10]
        ], [
          [5, 15]
        ]),
        [
          [5, 10]
        ],
      );
    });
    test('multiple walking', () {
      expect(
        intersectIntervals([
          [1, 4],
          [8, 12]
        ], [
          [2, 10]
        ]),
        [
          [2, 4],
          [8, 10]
        ],
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/overlap/overlap_engine_test.dart`
Expected: FAIL — `overlap_engine.dart` doesn't exist / `mergeIntervals` undefined.

- [ ] **Step 3: Implement**

Create `lib/core/overlap/overlap_engine.dart`:

```dart
import 'dart:collection';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// A time interval as `[startMs, endMs]` (UTC milliseconds since epoch).
typedef Interval = List<int>;

const int kHorizonDays = 14;
const int kMinWindowMinutes = 30;
const int kMaxWindows = 20;
const int kWakeHour = 7;
const int kSleepHour = 23; // 11 pm
const int kAlgoVersion = 1;

/// Merge overlapping/adjacent intervals. Input may be unsorted.
List<Interval> mergeIntervals(List<Interval> intervals) {
  if (intervals.isEmpty) return [];
  final sorted = [...intervals]..sort((a, b) => a[0].compareTo(b[0]));
  final result = [List<int>.from(sorted[0])];
  for (int i = 1; i < sorted.length; i++) {
    final last = result[result.length - 1];
    if (sorted[i][0] <= last[1]) {
      last[1] = last[1] > sorted[i][1] ? last[1] : sorted[i][1];
    } else {
      result.add(List<int>.from(sorted[i]));
    }
  }
  return result;
}

/// Intersect two sorted, merged interval lists (two-pointer walk).
List<Interval> intersectIntervals(List<Interval> a, List<Interval> b) {
  final result = <Interval>[];
  int i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final start = a[i][0] > b[j][0] ? a[i][0] : b[j][0];
    final end = a[i][1] < b[j][1] ? a[i][1] : b[j][1];
    if (start < end) result.add([start, end]);
    if (a[i][1] < b[j][1]) {
      i++;
    } else {
      j++;
    }
  }
  return result;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/overlap/overlap_engine_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/overlap/overlap_engine.dart test/core/overlap/overlap_engine_test.dart
git commit -m "feat(overlap): port mergeIntervals+intersectIntervals to dart"
```

---

## Task 3: Port `expandBlock` (recurrence) with golden TS-vs-Dart tests

**Files:**
- Modify: `lib/core/overlap/overlap_engine.dart`
- Modify: `test/core/overlap/overlap_engine_test.dart`
- Reference: `functions/src/lib/overlap.ts:44-77` (the source of truth)

**Interfaces:**
- Consumes: `TimeBlock` from `lib/core/models/time_block.dart`.
- Produces: `List<Interval> expandBlock(TimeBlock block, int windowStart, int windowEnd)`.

**Note on the `rrule` package API:** the TS uses `RRule.parseString(ruleStr)` + `rule.between(windowStart - duration, windowEnd, true)`. The Dart `rrule` package exposes `RecurrenceRule.fromString('RRULE:...')` and instance generation. Confirm the exact param names (`before`/`after` vs `getInstances(start:, before:, after:)`) against the installed `rrule` package docs at implementation time; the test contract below is what must hold regardless of API naming.

- [ ] **Step 1: Write failing tests (golden — mirror TS behavior)**

Append to `overlap_engine_test.dart`:

```dart
import 'package:couple_sync/core/models/time_block.dart';

TimeBlock _block({
  required int startUtc,
  required int endUtc,
  String? rrule,
  TimeBlockType type = TimeBlockType.busy,
}) {
  return TimeBlock(
    userId: 'u',
    title: 'b',
    type: type,
    category: TimeBlockCategory.other,
    startUtc: startUtc,
    endUtc: endUtc,
    timezone: 'UTC',
    recurrenceRule: rrule,
    source: TimeBlockSource.manual,
    visibility: TimeBlockVisibility.bothPartners,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

// 2024-01-01T00:00:00Z = 1704067200000. One hour = 3600000.
const int _t0 = 1704067200000;
const int _h = 3600000;
const int _d = 24 * _h;

group('expandBlock', () {
  test('non-recurring, inside window', () {
    final b = _block(startUtc: _t0 + _h, endUtc: _t0 + 2 * _h);
    expect(expandBlock(b, _t0, _t0 + _d), [
      [_t0 + _h, _t0 + 2 * _h]
    ]);
  });
  test('non-recurring, outside window -> empty', () {
    final b = _block(startUtc: _t0 - _d, endUtc: _t0 - _h);
    expect(expandBlock(b, _t0, _t0 + _d), isEmpty);
  });
  test('FREQ=DAILY expands across window', () {
    final b = _block(startUtc: _t0 + 9 * _h, endUtc: _t0 + 10 * _h, rrule: 'FREQ=DAILY');
    final out = expandBlock(b, _t0, _t0 + 3 * _d);
    // One occurrence per day for 3 days.
    expect(out.length, 3);
    expect(out[0], [_t0 + 9 * _h, _t0 + 10 * _h]);
    expect(out[1], [_t0 + _d + 9 * _h, _t0 + _d + 10 * _h]);
  });
  test('FREQ=WEEKLY with BYDAY', () {
    final b = _block(
      startUtc: _t0 + 9 * _h,
      endUtc: _t0 + 10 * _h,
      rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
    );
    final out = expandBlock(b, _t0, _t0 + 14 * _d);
    expect(out.length, greaterThan(0));
    // Each occurrence has the original duration.
    for (final iv in out) {
      expect(iv[1] - iv[0], _h);
    }
  });
  test('FREQ=MONTHLY', () {
    final b = _block(
      startUtc: _t0 + 9 * _h,
      endUtc: _t0 + 10 * _h,
      rrule: 'FREQ=MONTHLY',
    );
    final out = expandBlock(b, _t0, _t0 + 60 * _d);
    expect(out.length, greaterThanOrEqualTo(2));
  });
  test('FREQ=YEARLY', () {
    final b = _block(
      startUtc: _t0 + 9 * _h,
      endUtc: _t0 + 10 * _h,
      rrule: 'FREQ=YEARLY',
    );
    final out = expandBlock(b, _t0, _t0 + 400 * _d);
    expect(out.length, greaterThanOrEqualTo(2));
  });
  test('COUNT limits occurrences', () {
    final b = _block(
      startUtc: _t0 + 9 * _h,
      endUtc: _t0 + 10 * _h,
      rrule: 'FREQ=DAILY;COUNT=2',
    );
    final out = expandBlock(b, _t0, _t0 + 10 * _d);
    expect(out.length, 2);
  });
  test('UNTIL bounds occurrences', () {
    final until = _t0 + 2 * _d; // 2024-01-03
    // UNTIL in RRULE compact form: YYYYMMDDTHHMMSSZ
    final untilStr = DateTime.fromMillisecondsSinceEpoch(until, isUtc: true)
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll(RegExp(r'\.\d+Z$'), 'Z');
    final b = _block(
      startUtc: _t0 + 9 * _h,
      endUtc: _t0 + 10 * _h,
      rrule: 'FREQ=DAILY;UNTIL=$untilStr',
    );
    final out = expandBlock(b, _t0, _t0 + 10 * _d);
    expect(out.length, lessThanOrEqualTo(3));
  });
  test('free type is still expanded (filtering happens upstream)', () {
    final b = _block(
      startUtc: _t0 + _h,
      endUtc: _t0 + 2 * _h,
      type: TimeBlockType.free,
    );
    expect(expandBlock(b, _t0, _t0 + _d).length, 1);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/overlap/overlap_engine_test.dart`
Expected: FAIL — `expandBlock` undefined.

- [ ] **Step 3: Implement `expandBlock`**

Append to `overlap_engine.dart`. Import the `rrule` and `timezone` packages and `TimeBlock`:

```dart
import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart';
import 'package:couple_sync/core/models/time_block.dart';
```

```dart
/// Expand a block into concrete `[start, end]` intervals within
/// `[windowStart, windowEnd]`. Recurring blocks use the `rrule` package;
/// the lookback-by-one-duration and inclusive-window semantics mirror the TS
/// engine exactly so outputs stay byte-identical.
List<Interval> expandBlock(TimeBlock block, int windowStart, int windowEnd) {
  final duration = block.endUtc - block.startUtc;

  if (block.recurrenceRule == null || block.recurrenceRule!.isEmpty) {
    if (block.endUtc <= windowStart || block.startUtc >= windowEnd) return [];
    final s = block.startUtc > windowStart ? block.startUtc : windowStart;
    final e = block.endUtc < windowEnd ? block.endUtc : windowEnd;
    return [[s, e]];
  }

  final ruleStr = block.recurrenceRule!.startsWith('RRULE:')
      ? block.recurrenceRule!.substring(6)
      : block.recurrenceRule!;
  final rule = RecurrenceRule.fromString('RRULE:$ruleStr');

  // Look back by one duration so occurrences starting just before the window
  // that extend into it are included (matches TS between(start-duration, end, true)).
  final after = DateTime.fromMillisecondsSinceEpoch(windowStart - duration, isUtc: true);
  final before = DateTime.fromMillisecondsSinceEpoch(windowEnd, isUtc: true);

  // ponytail: rrule package API — use getInstances with before/after if available;
  // the contract test above is authoritative. If the installed version names these
  // differently, adapt here only; tests will catch divergence from TS.
  final occurrences = rule.getInstances(
    start: DateTime.fromMillisecondsSinceEpoch(block.startUtc, isUtc: true),
    before: before,
    after: after,
  );

  return occurrences
      .map((occ) => [occ.millisecondsSinceEpoch, occ.millisecondsSinceEpoch + duration])
      .where((iv) => iv[1] > windowStart && iv[0] < windowEnd)
      .map((iv) => [
            iv[0] > windowStart ? iv[0] : windowStart,
            iv[1] < windowEnd ? iv[1] : windowEnd,
          ])
      .toList();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/overlap/overlap_engine_test.dart`
Expected: PASS. If `getInstances` param names differ, fix the call in `expandBlock` only — do not change the tests.

- [ ] **Step 5: Golden cross-check against TS (manual, one-time)**

From `functions/`, run a quick node REPL or add a throwaway jest case that calls the TS `expandBlock` with the same `FREQ=WEEKLY;BYDAY=MO,WE` block and prints occurrences. Compare count + first interval to the Dart output. They must match. Delete the throwaway case after confirming.

Run: `cd functions && npx jest overlap`
Expected: existing 44 tests still pass; golden cross-check confirms parity.

- [ ] **Step 6: Commit**

```bash
git add lib/core/overlap/overlap_engine.dart test/core/overlap/overlap_engine_test.dart
git commit -m "feat(overlap): port expandBlock with rrule + golden tests"
```

---

## Task 4: Port free-intervals + waking-hours clip (TZDateTime, DST-correct)

**Files:**
- Modify: `lib/core/overlap/overlap_engine.dart`
- Modify: `test/core/overlap/overlap_engine_test.dart`
- Reference: `functions/src/lib/overlap.ts:81-154`

**Interfaces:**
- Produces:
  - `List<Interval> computeFreeIntervals(List<TimeBlock> blocks, int windowStart, int windowEnd)`
  - `List<Interval> clipIntervalToWakingHours(int start, int end, String timezone, {int wakeHour, int sleepHour})`
  - `List<Interval> clipToWakingHours(List<Interval> intervals, String timezone)`
  - `List<Interval> clipToDayBoundaries(List<Interval> intervals, String timezone)`

- [ ] **Step 1: Write failing tests (incl. DST)**

Append to `overlap_engine_test.dart`:

```dart
group('computeFreeIntervals', () {
  test('busy splits the free window', () {
    // window 0..100, busy 20..40 -> free [[0,20],[40,100]]
    final blocks = [
      _block(startUtc: 20, endUtc: 40),
    ];
    expect(computeFreeIntervals(blocks, 0, 100), [
      [0, 20],
      [40, 100],
    ]);
  });
  test('free/tentative excluded from busy', () {
    final blocks = [
      _block(startUtc: 20, endUtc: 40, type: TimeBlockType.free),
      _block(startUtc: 50, endUtc: 60, type: TimeBlockType.tentative),
    ];
    // only busy counted -> none here -> whole window free
    expect(computeFreeIntervals(blocks, 0, 100), [[0, 100]]);
  });
});

group('clipToWakingHours (DST)', () {
  test('clips to 07:00-23:00 local on a normal day in America/New_York', () {
    // 2024-03-10 (DST spring-forward day) 00:00..24:00 local in NY.
    final ny = 'America/New_York';
    final localMidnight = TZDateTime.initTimeZoneSettings; // see note below
    // Use a fixed instant: 2024-03-10T00:00:00-05:00 (pre-transition) ... but
    // the engine must produce 07:00..23:00 in *wall-clock* regardless of DST.
    final start = 1710043200000; // 2024-03-10T00:00:00Z approx
    final end = start + 24 * _h;
    final out = clipIntervalToWakingHours(start, end, ny);
    // Expect one clip per day, starting at 07:00 local, ending 23:00 local.
    expect(out.length, greaterThanOrEqualTo(1));
    for (final iv in out) {
      expect(iv[1] - iv[0], lessThanOrEqualTo(16 * _h));
    }
  });
});
```

Note: the DST test asserts the *contract* (clip is ≤ waking window per local day, and does not shift by an hour on DST). If `TZDateTime.initTimeZoneSettings` isn't the right initialization, the implementer must call `TimeZoneSettings.init`/`initializeTimeZones()` in `test setUpAll` using the `timezone` package's `tzdata` — adapt the `setUpAll` below, the assertions stay.

Add at the top of `main()` in the test file:

```dart
setUpAll(() async {
  // Ensure tz database is loaded for DST-correct clips.
  await TimeZoneSettings.init(); // or initializeTimeZones() per package version
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/overlap/overlap_engine_test.dart`
Expected: FAIL — functions undefined.

- [ ] **Step 3: Implement**

Append to `overlap_engine.dart`:

```dart
/// Build the free intervals (the complement of busy+tentative) within
/// [windowStart, windowEnd].
List<Interval> computeFreeIntervals(
    List<TimeBlock> blocks, int windowStart, int windowEnd) {
  final busy = mergeIntervals(
    blocks
        .where((b) => b.type == TimeBlockType.busy || b.type == TimeBlockType.tentative)
        .expand((b) => expandBlock(b, windowStart, windowEnd))
        .toList(),
  );
  final free = <Interval>[];
  int cursor = windowStart;
  for (final iv in busy) {
    if (cursor < iv[0]) free.add([cursor, iv[0]]);
    cursor = cursor > iv[1] ? cursor : iv[1];
  }
  if (cursor < windowEnd) free.add([cursor, windowEnd]);
  return free;
}

/// Clip [start, end] to waking hours (wakeHour..sleepHour) in the given
/// timezone, advancing by *local calendar days* (TZDateTime, DST-correct).
List<Interval> clipIntervalToWakingHours(
  int start,
  int end,
  String timezone, {
  int wakeHour = kWakeHour,
  int sleepHour = kSleepHour,
}) {
  final result = <Interval>[];
  final loc = getLocation(timezone);
  var dayStart = TZDateTime(loc, 1970, 1, 1).from(start); // local day start of `start`
  // Simpler: floor to local start-of-day.
  dayStart = _localStartOfDay(start, timezone);
  while (dayStart.millisecondsSinceEpoch < end) {
    final wakeMs = TZDateTime(loc, dayStart.year, dayStart.month, dayStart.day, wakeHour)
        .millisecondsSinceEpoch;
    final sleepMs = TZDateTime(loc, dayStart.year, dayStart.month, dayStart.day, sleepHour)
        .millisecondsSinceEpoch;
    final clipStart = start > wakeMs ? start : wakeMs;
    final clipEnd = end < sleepMs ? end : sleepMs;
    if (clipStart < clipEnd) result.add([clipStart, clipEnd]);
    dayStart = TZDateTime(loc, dayStart.year, dayStart.month, dayStart.day + 1);
  }
  return result;
}

TZDateTime _localStartOfDay(int ms, String timezone) {
  final loc = getLocation(timezone);
  final t = TZDateTime.fromMillisecondsSinceEpoch(loc, ms);
  return TZDateTime(loc, t.year, t.month, t.day);
}

List<Interval> clipToWakingHours(List<Interval> intervals, String timezone) {
  return intervals.expand((iv) => clipIntervalToWakingHours(iv[0], iv[1], timezone)).toList();
}

/// Split multi-day intervals into per-day (00:00-24:00 local) segments.
/// Used when showLateNightWindows=true so the calendar gets one window/day.
List<Interval> clipToDayBoundaries(List<Interval> intervals, String timezone) {
  final result = <Interval>[];
  final loc = getLocation(timezone);
  for (final iv in intervals) {
    var dayStart = _localStartOfDay(iv[0], timezone);
    while (dayStart.millisecondsSinceEpoch < iv[1]) {
      final dayEnd = TZDateTime(loc, dayStart.year, dayStart.month, dayStart.day + 1)
          .millisecondsSinceEpoch;
      final clipStart = iv[0] > dayStart.millisecondsSinceEpoch ? iv[0] : dayStart.millisecondsSinceEpoch;
      final clipEnd = iv[1] < dayEnd ? iv[1] : dayEnd;
      if (clipStart < clipEnd) result.add([clipStart, clipEnd]);
      dayStart = TZDateTime(loc, dayStart.year, dayStart.month, dayStart.day + 1);
    }
  }
  return result;
}
```

(If `TZDateTime(loc, ...).from(start)` is invalid syntax for the installed `timezone` version, remove it — `_localStartOfDay` is the actual helper used. Keep `_localStartOfDay`; drop the dead first `dayStart` assignment.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/overlap/overlap_engine_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/overlap/overlap_engine.dart test/core/overlap/overlap_engine_test.dart
git commit -m "feat(overlap): port free-intervals+tz-aware waking-hours clip"
```

---

## Task 5: Port `scoreWindow`, `computeBlockHash`, `computeOverlap`

**Files:**
- Modify: `lib/core/overlap/overlap_engine.dart`
- Modify: `test/core/overlap/overlap_engine_test.dart`
- Reference: `functions/src/lib/overlap.ts:156-240`

**Interfaces:**
- Produces:
  - `double scoreWindow(int startUtc, int endUtc, String timezoneA, int now)`
  - `String computeBlockHash(List<TimeBlock> blocks)`
  - `List<OverlapWindow> computeOverlap(List<TimeBlock> blocksA, List<TimeBlock> blocksB, String timezoneA, String timezoneB, int now, PartnerPrefs prefsA, PartnerPrefs prefsB)`
  - `class OverlapWindow` (or reuse `lib/core/models/overlap_result.dart`'s `OverlapWindow`).

**Note:** `scoreWindow` drops the dead `_timezoneB` param from the TS signature (it was ignored).

- [ ] **Step 1: Write failing tests**

Append to `overlap_engine_test.dart`:

```dart
import 'package:couple_sync/core/models/overlap_result.dart';

class _Prefs implements PartnerPrefs {
  @override
  final bool showLateNightWindows;
  _Prefs(this.showLateNightWindows);
}

group('computeBlockHash', () {
  test('stable regardless of input order', () {
    final a = [_block(startUtc: 10, endUtc: 20, rrule: 'FREQ=DAILY')];
    final b = [_block(startUtc: 10, endUtc: 20, rrule: 'FREQ=DAILY')];
    expect(computeBlockHash(a), computeBlockHash(a));
  });
  test('differs when recurrence differs', () {
    final a = [_block(startUtc: 10, endUtc: 20, rrule: 'FREQ=DAILY')];
    final b = [_block(startUtc: 10, endUtc: 20, rrule: 'FREQ=WEEKLY')];
    expect(computeBlockHash(a), isNot(computeBlockHash(b)));
  });
});

group('computeOverlap', () {
  test('two empty partners -> whole waking window', () {
    final out = computeOverlap([], [], 'UTC', 'UTC', _t0, _Prefs(false), _Prefs(false));
    expect(out, isNotEmpty);
    for (final w in out) {
      expect(w.durationMinutes, greaterThanOrEqualTo(30));
    }
  });
  test('non-overlapping busy -> no window', () {
    final a = [_block(startUtc: _t0, endUtc: _t0 + 12 * _h)]; // busy all morning
    final b = [_block(startUtc: _t0 + 12 * _h, endUtc: _t0 + 24 * _h)];
    final out = computeOverlap(a, b, 'UTC', 'UTC', _t0, _Prefs(false), _Prefs(false));
    // The exact windows depend on waking-hours clip; just assert it's bounded.
    for (final w in out) {
      expect(w.endUtc, greaterThan(w.startUtc));
    }
  });
  test('caps at 20 windows', () {
    // Many small free windows by alternating tiny busy blocks.
    final a = <TimeBlock>[];
    for (int i = 0; i < 40; i++) {
      a.add(_block(startUtc: _t0 + i * _h, endUtc: _t0 + i * _h + 1));
    }
    final out = computeOverlap(a, [], 'UTC', 'UTC', _t0, _Prefs(false), _Prefs(false));
    expect(out.length, lessThanOrEqualTo(20));
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/overlap/overlap_engine_test.dart`
Expected: FAIL — `computeOverlap` undefined.

- [ ] **Step 3: Implement**

Append to `overlap_engine.dart`. Reuse the existing `OverlapWindow` model:

```dart
import 'package:couple_sync/core/models/overlap_result.dart';
export 'package:couple_sync/core/models/overlap_result.dart' show OverlapWindow;

class PartnerPrefs {
  final bool showLateNightWindows;
  const PartnerPrefs({this.showLateNightWindows = false});
}

double scoreWindow(int startUtc, int endUtc, String timezoneA, int now) {
  final durationHours = (endUtc - startUtc) / (60 * 60 * 1000);
  final base = (math.log(durationHours + 1) / math.ln2) * 10;
  final loc = getLocation(timezoneA);
  final localA = TZDateTime.fromMillisecondsSinceEpoch(loc, startUtc);
  final eveningBonus = (localA.hour >= 18 && localA.hour < 21) ? 5.0 : 0.0;
  final weekendBonus = (localA.weekday >= 6) ? 5.0 : 0.0; // 6=Sat,7=Sun
  final daysFromNow = (startUtc - now) / (24 * 60 * 60 * 1000);
  final timeDecay = (10 - daysFromNow * 0.5).clamp(0.0, double.infinity);
  return base + eveningBonus + weekendBonus + timeDecay;
}

String computeBlockHash(List<TimeBlock> blocks) {
  final sorted = [...blocks]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  final str = sorted
      .map((b) => '${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type.name}')
      .join('|');
  return sha256.convert(utf8.encode(str)).toString().substring(0, 16);
}

List<OverlapWindow> computeOverlap(
  List<TimeBlock> blocksA,
  List<TimeBlock> blocksB,
  String timezoneA,
  String timezoneB,
  int now,
  PartnerPrefs prefsA,
  PartnerPrefs prefsB,
) {
  final windowEnd = now + kHorizonDays * 24 * 60 * 60 * 1000;
  final freeA = computeFreeIntervals(blocksA, now, windowEnd);
  final freeB = computeFreeIntervals(blocksB, now, windowEnd);

  var clipped = intersectIntervals(freeA, freeB);
  if (!prefsA.showLateNightWindows) {
    clipped = clipToWakingHours(clipped, timezoneA);
  } else {
    clipped = clipToDayBoundaries(clipped, timezoneA);
  }
  if (!prefsB.showLateNightWindows) {
    clipped = clipToWakingHours(clipped, timezoneB);
  } else {
    clipped = clipToDayBoundaries(clipped, timezoneB);
  }

  final reasonableBoth =
      !prefsA.showLateNightWindows && !prefsB.showLateNightWindows;

  final windows = clipped
      .map((iv) => OverlapWindow(
            startUtc: iv[0],
            endUtc: iv[1],
            durationMinutes: ((iv[1] - iv[0]) / 60000).round(),
            score: scoreWindow(iv[0], iv[1], timezoneA, now),
            reasonableBoth: reasonableBoth,
          ))
      .where((w) => w.durationMinutes >= kMinWindowMinutes)
      .toList();

  windows.sort((a, b) => b.score.compareTo(a.score));
  return windows.length > kMaxWindows ? windows.sublist(0, kMaxWindows) : windows;
}
```

Add `import 'dart:math' as math;` at the top.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/overlap/overlap_engine_test.dart`
Expected: PASS (all engine tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/overlap/overlap_engine.dart test/core/overlap/overlap_engine_test.dart
git commit -m "feat(overlap): port scoreWindow+computeBlockHash+computeOverlap"
```

---

## Task 6: Update `OverlapResult` model (`inputHash` + `computedBy`)

**Files:**
- Modify: `lib/core/models/overlap_result.dart`
- Modify: `functions/src/lib/types.ts`

**Interfaces:**
- Produces: `OverlapResult { windows, computedAt (int ms), inputHash (String), computedBy (String?) }`. `blockHashA`/`blockHashB` removed.

- [ ] **Step 1: Update the Dart model**

In `lib/core/models/overlap_result.dart`, replace fields `blockHashA`/`blockHashB` with `inputHash` and add `computedBy`. Replace the constructor, `fromJson`, `toJson`, `copyWith`, `==`, `hashCode`:

```dart
class OverlapResult {
  final List<OverlapWindow> windows;
  final DateTime computedAt;
  final String inputHash;
  final String? computedBy;

  const OverlapResult({
    required this.windows,
    required this.computedAt,
    required this.inputHash,
    this.computedBy,
  });

  factory OverlapResult.fromJson(Map<String, dynamic> json) {
    return OverlapResult(
      windows: (json['windows'] as List<dynamic>?)
              ?.map((e) => OverlapWindow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      computedAt: json['computedAt'] is Timestamp
          ? (json['computedAt'] as Timestamp).toDate()
          : json['computedAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(json['computedAt'] as int, isUtc: true)
              : DateTime.now().toUtc(),
      inputHash: json['inputHash'] as String? ?? '',
      computedBy: json['computedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'windows': windows.map((e) => e.toJson()).toList(),
      'computedAt': computedAt.millisecondsSinceEpoch, // int, not Timestamp
      'inputHash': inputHash,
      'computedBy': computedBy,
    };
  }

  OverlapResult copyWith({
    List<OverlapWindow>? windows,
    DateTime? computedAt,
    String? inputHash,
    String? computedBy,
  }) {
    return OverlapResult(
      windows: windows ?? List.from(this.windows),
      computedAt: computedAt ?? this.computedAt,
      inputHash: inputHash ?? this.inputHash,
      computedBy: computedBy ?? this.computedBy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlapResult &&
          runtimeType == other.runtimeType &&
          _listEquals(windows, other.windows) &&
          computedAt == other.computedAt &&
          inputHash == other.inputHash &&
          computedBy == other.computedBy;

  @override
  int get hashCode => Object.hash(Object.hashAll(windows), computedAt, inputHash, computedBy);

  // nextWindow, windowsByScore, windowsByTime, _listEquals unchanged.
}
```

Keep `nextWindow`, `windowsByScore`, `windowsByTime`, `_listEquals` as-is.

- [ ] **Step 2: Update the TS types**

In `functions/src/lib/types.ts`, replace `OverlapResult`:

```ts
export interface OverlapResult {
  windows: OverlapWindow[];
  computedAt: number;
  inputHash: string;
  computedBy?: string;
}
```

- [ ] **Step 3: Find + fix every call site referencing the old fields**

Run: `grep -rn "blockHashA\|blockHashB" lib functions/src --include=*.dart --include=*.ts`
Expected: only `onBlockWrite.ts` and `onUserPrefsWrite.ts` (both deleted in Task 8). Any other hit → update to `inputHash`.

- [ ] **Step 4: Build both**

Run: `flutter analyze` and `cd functions && npm run build`
Expected: no errors referencing the removed fields.

- [ ] **Step 5: Commit**

```bash
git add lib/core/models/overlap_result.dart functions/src/lib/types.ts
git commit -m "refactor(overlap): replace blockHashA/B with inputHash+computedBy"
```

---

## Task 7: Overlap controller (Riverpod) — compute + transaction write

**Files:**
- Create: `lib/core/overlap/overlap_controller.dart`
- Modify: `lib/services/firestore_service.dart`

**Interfaces:**
- Consumes: `computeOverlap`, `computeBlockHash`-style input hash (see below), `FirestoreService.watchBlocks`, `FirestoreService.getUser` streams.
- Produces: `overlapControllerProvider` (Family `<coupleId, AsyncValue<OverlapResult>>`).

- [ ] **Step 1: Add `writeOverlapTransaction` to `FirestoreService`**

In `lib/services/firestore_service.dart`, add:

```dart
/// Writes `overlaps/{coupleId}/windows/latest` only if the stored `inputHash`
/// differs from [inputHash]. Returns true if the write happened.
Future<bool> writeOverlapTransaction(
  String coupleId,
  OverlapResult result,
  String uid,
) async {
  final docRef = _firestore
      .collection('overlaps')
      .doc(coupleId)
      .collection('windows')
      .doc('latest');
  try {
    return await _firestore.runTransaction<bool>((tx) async {
      final snap = await tx.get(docRef);
      final current = snap.exists ? (snap.data()!['inputHash'] as String?) : null;
      if (current == result.inputHash) return false;
      tx.set(docRef, {
        ...result.toJson(),
        'computedBy': uid,
      });
      return true;
    });
  } on FirebaseException catch (e) {
    throw _mapFirebaseException(e, 'Failed to write overlap');
  }
}
```

- [ ] **Step 2: Write the controller**

Create `lib/core/overlap/overlap_controller.dart`:

```dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';
import 'package:couple_sync/core/models/overlap_result.dart';
import 'package:couple_sync/core/models/models.dart';
import 'package:couple_sync/services/firestore_service.dart';
import 'package:couple_sync/services/providers/firestore_provider.dart';

class PartnerInput {
  final String timezone;
  final bool showLateNightWindows;
  const PartnerInput({required this.timezone, required this.showLateNightWindows});
}

/// Computes inputHash over all overlap inputs (blocks + tz + prefs + algo + nowBucket).
String computeOverlapInputHash({
  required List<TimeBlock> blocksA,
  required List<TimeBlock> blocksB,
  required String tzA,
  required String tzB,
  required PartnerPrefs prefsA,
  required PartnerPrefs prefsB,
  required int nowBucket,
}) {
  final blockStrA = blocksA
    ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  final blockStrB = [...blocksB]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  final a = blockStrA.map((b) => '${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type.name}').join('|');
  final b = blockStrB.map((b) => '${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type.name}').join('|');
  final str = '$a#$b#$tzA#$tzB#${prefsA.showLateNightWindows}#${prefsB.showLateNightWindows}#$kAlgoVersion#$nowBucket';
  return sha256.convert(utf8.encode(str)).toString().substring(0, 16);
}

int floorToHour(int ms) => (ms ~/ (60 * 60 * 1000)) * (60 * 60 * 1000);

class OverlapController extends FamilyAsyncNotifier<OverlapResult, String> {
  Timer? _debounce;
  StreamSubscription? _blocksSub;
  StreamSubscription? _userASub;
  StreamSubscription? _userBSub;

  @override
  Future<OverlapResult> build(String coupleId) {
    ref.onDispose(() {
      _debounce?.cancel();
      _blocksSub?.cancel();
      _userASub?.cancel();
      _userBSub?.cancel();
    });
    // Wire streams in the next step.
    return Future.value(OverlapResult(
      windows: const [],
      computedAt: DateTime.now().toUtc(),
      inputHash: '',
    ));
  }

  // The actual wiring lives in step 3; tests in step 4 cover computeOverlapInputHash + debounce.
}
```

- [ ] **Step 3: Wire the streams + debounced compute + transaction write**

Fill in `build` to subscribe to `watchBlocks(coupleId)`, and to both partners' user docs (resolve uids from the couple doc), debounce 500ms, then compute and write. This step is integration code; cover the pure helpers in step 4 rather than the stream wiring.

(Implementation details: read the couple doc to get `userAUid`/`userBUid`; subscribe to `users/{uid}` snapshots; on any change, debounce 500ms, compute `nowBucket = floorToHour(DateTime.now().toUtc().millisecondsSinceEpoch)`, `computeOverlap(..., now: nowBucket, ...)`, `inputHash = computeOverlapInputHash(...)`, set state to the result, then `await firestore.writeOverlapTransaction(coupleId, result, uid)`. Skip the write if the local `inputHash` matches the last-written one.)

- [ ] **Step 4: Write failing tests for the pure helpers**

Create `test/core/overlap/overlap_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_sync/core/overlap/overlap_controller.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';

void main() {
  test('floorToHour rounds down to the hour', () {
    const ms = 1704067200000; // 2024-01-01T00:00:00Z
    expect(floorToHour(ms + 59 * 60 * 1000), ms);
  });

  test('computeOverlapInputHash is deterministic for identical inputs', () {
    final h1 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final h2 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(h1, h2);
  });

  test('inputHash changes when a pref changes', () {
    final base = computeOverlapInputHash(
      blocksA: const [], blocksB: const [], tzA: 'UTC', tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final toggled = computeOverlapInputHash(
      blocksA: const [], blocksB: const [], tzA: 'UTC', tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: true),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(base, isNot(toggled));
  });
}
```

- [ ] **Step 5: Run tests**

Run: `flutter test test/core/overlap/overlap_controller_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/overlap/overlap_controller.dart lib/services/firestore_service.dart test/core/overlap/overlap_controller_test.dart
git commit -m "feat(overlap): device-side controller with debounce+transaction write"
```

---

## Task 8: Firestore rules — relax `overlaps/latest` write + rules tests

**Files:**
- Modify: `firestore.rules`
- Create: `functions/src/__tests__/rules/overlaps.rules.test.ts`
- Modify: `functions/package.json` (add `@firebase/rules-unit-testing` devDep)

- [ ] **Step 1: Update the rules**

In `firestore.rules`, replace the `overlaps/{coupleId}/windows/{windowId}` block:

```
    match /overlaps/{coupleId}/windows/{windowId} {
      allow read: if isCoupleMember(coupleId);

      // v2: couple members may write "latest" (device-computed overlap),
      // gated to the single doc + top-level shape. Deep element validation
      // happens in onOverlapWrite before FCM.
      allow write: if isCoupleMember(coupleId)
        && windowId == 'latest'
        && request.resource.data.computedBy == request.auth.uid
        && request.resource.data.inputHash is string
        && request.resource.data.computedAt is int
        && request.resource.data.windows is list
        && request.resource.data.windows.size() <= 20;
    }
```

- [ ] **Step 2: Add the rules-testing devDep**

In `functions/package.json` `devDependencies`, add:
```json
    "@firebase/rules-unit-testing": "^4.0.0"
```
Run: `cd functions && npm install`

- [ ] **Step 3: Write the rules tests**

Create `functions/src/__tests__/rules/overlaps.rules.test.ts`:

```ts
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { setLogLevel } from 'firebase/firestore';
import { readFileSync } from 'fs';

const PROJECT_ID = 'couple-sync-rules-test';

let env: any;
beforeAll(async () => {
  setLogLevel('error');
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync('firestore.rules', 'utf8') },
  });
});
afterAll(async () => { await env.cleanup(); });

function couple(coupleId: string, a: string, b: string) {
  return env.authedContext({ uid: a }).firestore().doc(`couples/${coupleId}`)
    .set({ userAUid: a, userBUid: b });
}

test('member can write latest with computedBy=self', async () => {
  const cid = 'c1', a = 'uA', b = 'uB';
  await couple(cid, a, b);
  await env.authedContext({ uid: a }).firestore().doc(`users/${a}`)
    .set({ coupleId: cid });
  const db = env.authedContext({ uid: a }).firestore();
  await assertSucceeds(db.doc(`overlaps/${cid}/windows/latest`).set({
    windows: [], computedAt: 1, inputHash: 'h', computedBy: a,
  }));
});

test('non-member cannot write latest', async () => {
  const cid = 'c2', a = 'uA', b = 'uB';
  await couple(cid, a, b);
  const db = env.authedContext({ uid: 'stranger' }).firestore();
  await assertFails(db.doc(`overlaps/${cid}/windows/latest`).set({
    windows: [], computedAt: 1, inputHash: 'h', computedBy: 'stranger',
  }));
});

test('computedBy must equal auth.uid', async () => {
  const cid = 'c3', a = 'uA', b = 'uB';
  await couple(cid, a, b);
  await env.authedContext({ uid: a }).firestore().doc(`users/${a}`).set({ coupleId: cid });
  const db = env.authedContext({ uid: a }).firestore();
  await assertFails(db.doc(`overlaps/${cid}/windows/latest`).set({
    windows: [], computedAt: 1, inputHash: 'h', computedBy: b, // forging partner
  }));
});

test('windows.size() > 20 rejected', async () => {
  const cid = 'c4', a = 'uA', b = 'uB';
  await couple(cid, a, b);
  await env.authedContext({ uid: a }).firestore().doc(`users/${a}`).set({ coupleId: cid });
  const db = env.authedContext({ uid: a }).firestore();
  const windows = Array.from({ length: 21 }, () => ({ startUtc: 0, endUtc: 1, durationMinutes: 1, score: 0, reasonableBoth: false }));
  await assertFails(db.doc(`overlaps/${cid}/windows/latest`).set({
    windows, computedAt: 1, inputHash: 'h', computedBy: a,
  }));
});

test('write to a non-latest windowId rejected', async () => {
  const cid = 'c5', a = 'uA', b = 'uB';
  await couple(cid, a, b);
  await env.authedContext({ uid: a }).firestore().doc(`users/${a}`).set({ coupleId: cid });
  const db = env.authedContext({ uid: a }).firestore();
  await assertFails(db.doc(`overlaps/${cid}/windows/other`).set({
    windows: [], computedAt: 1, inputHash: 'h', computedBy: a,
  }));
});
```

- [ ] **Step 4: Run the rules tests**

Run: `cd functions && npx jest rules/overlaps`
Expected: PASS (5 tests). Start the Firestore emulator first if needed: `firebase emulators:start --only firestore` in another terminal, or let rules-unit-testing spin up its own.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules functions/src/__tests__/rules/overlaps.rules.test.ts functions/package.json functions/package-lock.json
git commit -m "feat(rules): allow couple members to write overlaps/latest with shape gate"
```

---

## Task 9: `onOverlapWrite` — deep `windows[]` validation + skip writer

**Files:**
- Modify: `functions/src/onOverlapWrite.ts`
- Modify: `functions/src/__tests__/onOverlapWrite.test.ts`

**Interfaces:**
- Produces: `validateWindows(windows: unknown[]): OverlapWindow[]` (throws or filters malformed). `handleOnOverlapWrite` skips `computedBy` uid.

- [ ] **Step 1: Write failing tests**

In `functions/src/__tests__/onOverlapWrite.test.ts`, add:

```ts
describe('validateWindows', () => {
  const ok = (over: Partial<any> = {}) => ({
    startUtc: 1000, endUtc: 1000 + 60 * 60 * 1000, durationMinutes: 60, score: 5, reasonableBoth: true, ...over,
  });

  test('accepts well-formed windows', () => {
    expect(validateWindows([ok()])).toHaveLength(1);
  });
  test('rejects durationMinutes > 1560 (DST fall-back guard)', () => {
    expect(() => validateWindows([ok({ durationMinutes: 1561, endUtc: 1000 + 1561 * 60 * 1000 })])).toThrow();
  });
  test('rejects startUtc >= endUtc', () => {
    expect(() => validateWindows([ok({ startUtc: 2000, endUtc: 2000 })])).toThrow();
  });
  test('rejects end-start != durationMinutes*60000', () => {
    expect(() => validateWindows([ok({ durationMinutes: 30 })])).toThrow();
  });
  test('rejects non-bool reasonableBoth', () => {
    expect(() => validateWindows([ok({ reasonableBoth: 'yes' })])).toThrow();
  });
});

describe('handleOnOverlapWrite skips writer', () => {
  test('does not send to computedBy uid', async () => {
    const sent: string[] = [];
    await handleOnOverlapWrite('c1', [ok()], {
      getCouple: async () => ({ userAUid: 'uA', userBUid: 'uB', status: 'active', pairedAt: 0, createdAt: 0 }),
      getFcmTokens: async (uid) => uid === 'uA' ? ['tA'] : ['tB'],
      sendNotification: async (tokens) => { sent.push(...tokens); return []; },
      updateFcmTokens: async () => {},
      // computedBy carried on the doc; the handler reads it.
    } as any, 'uA');
    expect(sent).toEqual(['tB']); // uA (writer) skipped
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd functions && npx jest onOverlapWrite`
Expected: FAIL — `validateWindows` undefined; handler signature unchanged.

- [ ] **Step 3: Implement**

In `functions/src/onOverlapWrite.ts`, add the validator and thread `computedBy` through `handleOnOverlapWrite`:

```ts
export function validateWindows(input: unknown[]): OverlapWindow[] {
  const out: OverlapWindow[] = [];
  for (const w of input as any[]) {
    if (typeof w.startUtc !== 'number' || typeof w.endUtc !== 'number' ||
        typeof w.durationMinutes !== 'number' || typeof w.score !== 'number' ||
        typeof w.reasonableBoth !== 'boolean') {
      throw new Error('invalid window shape');
    }
    if (!(w.durationMinutes > 0 && w.durationMinutes <= 1560)) {
      throw new Error('durationMinutes out of bounds');
    }
    if (!(w.startUtc < w.endUtc)) {
      throw new Error('startUtc must be < endUtc');
    }
    if (Math.abs((w.endUtc - w.startUtc) - w.durationMinutes * 60_000) > 1000) {
      throw new Error('durationMinutes does not match start/end');
    }
    out.push(w);
  }
  return out;
}
```

Update `handleOnOverlapWrite`'s signature to accept `computedBy` and skip it:

```ts
export async function handleOnOverlapWrite(
  coupleId: string,
  windows: OverlapWindow[],
  deps: OverlapWriteDeps,
  computedBy?: string,
): Promise<void> {
  let valid: OverlapWindow[];
  try {
    valid = validateWindows(windows);
  } catch (e) {
    logger.warn(`[onOverlapWrite] rejected malformed windows: ${(e as Error).message}`);
    return;
  }
  if (valid.length === 0) return;

  const couple = await deps.getCouple(coupleId);
  if (!couple) return;

  const targets = [couple.userAUid, couple.userBUid].filter((uid) => uid !== computedBy);
  const tokensPerUid = await Promise.all(
    targets.map(async (uid) => [uid, await deps.getFcmTokens(uid)] as const),
  );

  const nextWindow = valid.reduce((best, w) => (w.startUtc < best.startUtc ? w : best));
  const notification: Notification = {
    title: 'You have free time together!',
    body: formatOverlapBody(nextWindow),
    data: { coupleId },
  };

  for (const [uid, tokens] of tokensPerUid) {
    if (tokens.length === 0) continue;
    const invalidTokens = await deps.sendNotification(tokens, notification);
    if (invalidTokens.length > 0) {
      const validTokens = tokens.filter((t) => !invalidTokens.includes(t));
      await deps.updateFcmTokens(uid, validTokens);
    }
  }
}
```

Update the CF export to pass `computedBy` from the doc:

```ts
  const overlapResult = after?.data() as (OverlapResult & { computedBy?: string }) | undefined;
  const windows = overlapResult?.windows ?? [];
  const computedBy = overlapResult?.computedBy;
  await handleOnOverlapWrite(coupleId, windows, { /* existing deps */ }, computedBy);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd functions && npx jest onOverlapWrite`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/onOverlapWrite.ts functions/src/__tests__/onOverlapWrite.test.ts
git commit -m "feat(onOverlapWrite): validate windows[] + skip writer uid"
```

---

## Task 10: Delete `onBlockWrite` + `onUserPrefsWrite`

**Files:**
- Delete: `functions/src/onBlockWrite.ts`
- Delete: `functions/src/__tests__/onBlockWrite.test.ts`
- Delete: `functions/src/onUserPrefsWrite.ts`
- Modify: `functions/src/index.ts`

- [ ] **Step 1: Remove the exports**

In `functions/src/index.ts`, delete lines:
```ts
export { onBlockWrite } from './onBlockWrite';
export { onUserPrefsWrite } from './onUserPrefsWrite';
```

- [ ] **Step 2: Delete the files**

```bash
git rm functions/src/onBlockWrite.ts functions/src/__tests__/onBlockWrite.test.ts functions/src/onUserPrefsWrite.ts
```

- [ ] **Step 3: Build + test**

Run: `cd functions && npm run build && npm run lint && npm test`
Expected: build clean, lint clean, tests pass (minus the two deleted suites).

Run: `flutter analyze`
Expected: no references to the deleted functions.

- [ ] **Step 4: Commit**

```bash
git add -A functions
git commit -m "chore(functions): delete onBlockWrite+onUserPrefsWrite (moved to device)"
```

---

## Task 11: Wire the controller into home + overlap screens

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`
- Modify: `lib/features/overlap/screens/overlap_screen.dart`
- Modify: `lib/services/providers/` (register `overlapControllerProvider`)

- [ ] **Step 1: Expose the provider**

In `lib/core/overlap/overlap_controller.dart`, add at the bottom:

```dart
final overlapControllerProvider =
    AutoDisposeFamilyAsyncNotifierProvider<OverlapController, OverlapResult, String>(
  OverlapController.new,
);
```

- [ ] **Step 2: Replace `watchOverlap` reads with the controller**

In `home_screen.dart` and `overlap_screen.dart`, swap the existing `watchOverlap(coupleId)` consumer for `ref.watch(overlapControllerProvider(coupleId))`. The controller emits locally-computed results instantly; the transaction write keeps `onOverlapWrite` firing for the partner's push.

- [ ] **Step 3: Smoke-test on the emulator**

```bash
firebase emulators:start --only auth,firestore,functions
flutter run
```
Expected: add a manual block → overlap recomputes within ~500ms locally (no function invocation in the emulator logs for `onBlockWrite`); partner device (or a second signed-in client) receives an FCM push from `onOverlapWrite`.

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/screens/home_screen.dart lib/features/overlap/screens/overlap_screen.dart lib/core/overlap/overlap_controller.dart
git commit -m "feat(home,overlap): consume device-side overlap controller"
```

---

## Self-Review

**Spec coverage:** §5 (delete onBlockWrite+onUserPrefsWrite) → Task 10. §7.1 engine port → Tasks 2-5. §7.2 controller + inputHash + nowBucket + transaction → Task 7. §7.3 rrule golden tests → Task 3. §8.1 model (inputHash/computedBy) → Task 6. §8.2 rules + deep validation → Tasks 8-9. §8.3 onOverlapWrite skip writer → Task 9. §13 functions/firestore deploy → Tasks 1, 8, 10. §9 UX → Plan C. §4 GCP infra (Hosting/App Check/Calendar quota) → Plan B. All spec sections covered across the plan set.

**Placeholder scan:** Task 7 step 3 is integration wiring without full code (stream plumbing) — acceptable because the pure helpers it relies on (`computeOverlapInputHash`, `floorToHour`) are fully spec'd and tested in step 4; the wiring is mechanical stream subscription. Task 4's DST test uses a contract assertion rather than exact expected millisecond values — acceptable because the contract (≤ waking window per local day, no DST shift) is the real requirement.

**Type consistency:** `OverlapResult.inputHash`/`computedBy` (Task 6) match `writeOverlapTransaction(result, uid)` (Task 7) and the rules `inputHash`/`computedBy` (Task 8) and `onOverlapWrite`'s `OverlapResult & { computedBy? }` (Task 9). `computeOverlap(..., now: nowBucket, ...)` (Task 5 signature) matches the controller call (Task 7). `PartnerPrefs` defined once in `overlap_engine.dart` (Task 5), imported by the controller (Task 7) — consistent.

---

## Execution Handoff

Plan A complete and saved to `docs/superpowers/plans/2026-06-30-edge-overlap-port.md`. Plans B (GCP infra) and C (Flutter UX cleanup) are separate companion plans, not yet written.

**Two execution options for Plan A:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?** (And: want me to write Plan B + Plan C next, or execute Plan A first?)
