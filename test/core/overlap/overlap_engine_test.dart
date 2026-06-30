import 'package:flutter_test/flutter_test.dart';
import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';

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
}
