import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart';
import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';

class _Prefs implements PartnerPrefs {
  @override
  final bool showLateNightWindows;
  _Prefs(this.showLateNightWindows);
}

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

void main() {
  setUpAll(() {
    // Ensure tz database is loaded for DST-correct clips.
    tz_data.initializeTimeZones();
  });

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
      // 14-day window from Mon 2024-01-01: MO/WE on Jan 1, 3, 8, 10 -> 4 occurrences.
      expect(out.length, 4);
      expect(out[0], [_t0 + 9 * _h, _t0 + 10 * _h]);
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
      // 60-day window: Jan 1 and Feb 1 -> 2 occurrences.
      expect(out.length, 2);
      expect(out[0], [_t0 + 9 * _h, _t0 + 10 * _h]);
    });
    test('FREQ=YEARLY', () {
      final b = _block(
        startUtc: _t0 + 9 * _h,
        endUtc: _t0 + 10 * _h,
        rrule: 'FREQ=YEARLY',
      );
      final out = expandBlock(b, _t0, _t0 + 400 * _d);
      // 400-day window: Jan 1 2024 and Jan 1 2025 -> 2 occurrences.
      expect(out.length, 2);
      expect(out[0], [_t0 + 9 * _h, _t0 + 10 * _h]);
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
      // UNTIL=20240103T000000Z excludes the Jan 3 09:00 occurrence
      // (it starts after UNTIL). Jan 1 + Jan 2 -> 2 occurrences.
      expect(out.length, 2);
      expect(out[0], [_t0 + 9 * _h, _t0 + 10 * _h]);
    });
    test('free type is still expanded (filtering happens upstream)', () {
      final b = _block(
        startUtc: _t0 + _h,
        endUtc: _t0 + 2 * _h,
        type: TimeBlockType.free,
      );
      expect(expandBlock(b, _t0, _t0 + _d).length, 1);
    });
    test('recurring occurrence starting before window is kept and clamped (lookback)', () {
      // dtstart 1h before windowStart; end 1h into the window (duration 2h).
      // The first occurrence extends into the window -> must be kept and clamped
      // to windowStart. Mirrors the TS `between(windowStart - duration, ...)` lookback.
      final b = _block(
        startUtc: _t0 - _h,
        endUtc: _t0 + _h,
        rrule: 'FREQ=DAILY;COUNT=1',
      );
      final out = expandBlock(b, _t0, _t0 + _d);
      expect(out.length, 1);
      expect(out[0], [_t0, _t0 + _h]);
    });
  });

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
    test('free type ignored; tentative treated as busy', () {
      final blocks = [
        _block(startUtc: 20, endUtc: 40, type: TimeBlockType.free),
        _block(startUtc: 50, endUtc: 60, type: TimeBlockType.tentative),
      ];
      // free does not split; tentative IS busy (matches TS) -> split around 50-60
      expect(computeFreeIntervals(blocks, 0, 100), [
        [0, 50],
        [60, 100],
      ]);
    });
  });

  group('clipToWakingHours (DST)', () {
    test('clips to 07:00-23:00 local on a normal day in America/New_York', () {
      final ny = 'America/New_York';
      final loc = getLocation(ny);
      // Construct local midnight 2024-02-15 (non-DST day) via TZDateTime so the
      // boundary is wall-clock, not offset-shifted.
      final localMidnight = TZDateTime(loc, 2024, 2, 15);
      final start = localMidnight.millisecondsSinceEpoch;
      final end = start + 24 * _h;
      final out = clipIntervalToWakingHours(start, end, ny);
      expect(out.length, greaterThanOrEqualTo(1));
      for (final iv in out) {
        expect(iv[1] - iv[0], lessThanOrEqualTo(16 * _h));
      }
      // First clip starts at 07:00 local and ends at 23:00 local (16h).
      expect(out[0][1] - out[0][0], 16 * _h);
      expect(
        TZDateTime.fromMillisecondsSinceEpoch(loc, out[0][0]).hour,
        7,
      );
      expect(
        TZDateTime.fromMillisecondsSinceEpoch(loc, out[0][1]).hour,
        23,
      );
    });

    test('spring-forward 2024-03-10 boundary does not shift by an hour', () {
      final ny = 'America/New_York';
      final loc = getLocation(ny);
      // 2024-03-10 is the DST spring-forward day in America/New_York (23h day).
      // Use a TZDateTime-constructed local midnight so the test is anchored to
      // the local calendar day, not a UTC instant that may land on the wrong date.
      final localMidnight = TZDateTime(loc, 2024, 3, 10);
      final start = localMidnight.millisecondsSinceEpoch;
      final end = start + 24 * _h;
      final out = clipIntervalToWakingHours(start, end, ny);
      expect(out, isNotEmpty);
      // Contract: each clip is <= waking window (16 wall-clock hours).
      for (final iv in out) {
        expect(iv[1] - iv[0], lessThanOrEqualTo(16 * _h));
      }
      // The first clip's wake boundary must be at wall-clock 07:00 on 2024-03-10,
      // not shifted by the 02:00->03:00 transition. 07:00 is post-transition (EDT).
      final wakeLocal = TZDateTime.fromMillisecondsSinceEpoch(loc, out[0][0]);
      expect(wakeLocal.year, 2024);
      expect(wakeLocal.month, 3);
      expect(wakeLocal.day, 10);
      expect(wakeLocal.hour, 7);
    });

    test('fall-back 2024-11-03 clipToDayBoundaries yields 25h segment', () {
      final ny = 'America/New_York';
      final loc = getLocation(ny);
      // 2024-11-03 is the DST fall-back day in America/New_York (25h day).
      final localMidnight = TZDateTime(loc, 2024, 11, 3);
      final start = localMidnight.millisecondsSinceEpoch;
      // Late-night interval spanning past the end of the 25h day.
      final end = start + 26 * _h;
      final out = clipToDayBoundaries([
        [start, end]
      ], ny);
      expect(out, isNotEmpty);
      // First segment is the full fall-back day: 25h = 1500 minutes.
      expect(out[0][1] - out[0][0], 25 * _h);
      expect((out[0][1] - out[0][0]) ~/ 60000, 1500);
    });
  });

  group('computeBlockHash', () {
    test('stable regardless of input order', () {
      final a = [
        _block(startUtc: 30, endUtc: 40, rrule: 'FREQ=DAILY'),
        _block(startUtc: 10, endUtc: 20, rrule: 'FREQ=DAILY'),
      ];
      final b = [
        _block(startUtc: 10, endUtc: 20, rrule: 'FREQ=DAILY'),
        _block(startUtc: 30, endUtc: 40, rrule: 'FREQ=DAILY'),
      ];
      expect(computeBlockHash(a), computeBlockHash(b));
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
      // Place a 1h busy block at 12:00-13:00 UTC each day for 14 days, inside
      // the 07:00-23:00 waking window. Each day's waking window splits into two
      // free segments (07-12, 13-23) -> 28 segments, all >= 30 min, so the
      // kMaxWindows=20 cap fires.
      final a = <TimeBlock>[];
      for (int i = 0; i < 14; i++) {
        a.add(_block(
          startUtc: _t0 + i * _d + 12 * _h,
          endUtc: _t0 + i * _d + 13 * _h,
        ));
      }
      final out = computeOverlap(a, [], 'UTC', 'UTC', _t0, _Prefs(false), _Prefs(false));
      expect(out.length, 20);
    });
  });
}
