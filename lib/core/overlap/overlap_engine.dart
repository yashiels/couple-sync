import 'dart:math' as math;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart';
import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/core/models/overlap_result.dart';
export 'package:couple_sync/core/models/overlap_result.dart' show OverlapWindow;

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
    return [
      [s, e],
    ];
  }

  final ruleStr = block.recurrenceRule!.startsWith('RRULE:')
      ? block.recurrenceRule!.substring(6)
      : block.recurrenceRule!;
  final rule = RecurrenceRule.fromString('RRULE:$ruleStr');

  // pub.dev rrule 0.2.x: getInstances(start:) returns an Iterable<DateTime> from
  // the rule's dtstart onward (ascending). Walk it and stop once occurrences pass
  // the window end. Keeping occurrences whose [occ, occ+duration] overlaps the
  // window reproduces the TS `between(windowStart - duration, windowEnd, true)`
  // inclusive lookback: an occurrence starting just before the window that extends
  // into it is kept because its end > windowStart.
  final dtStart = DateTime.fromMillisecondsSinceEpoch(
    block.startUtc,
    isUtc: true,
  );
  final occurrences = <DateTime>[];
  for (final occ in rule.getInstances(start: dtStart)) {
    final s = occ.millisecondsSinceEpoch;
    if (s >= windowEnd) break; // ascending; stop
    final e = s + duration;
    if (e > windowStart) occurrences.add(occ);
  }

  return occurrences.map((occ) {
    final s = occ.millisecondsSinceEpoch;
    final e = s + duration;
    return [s > windowStart ? s : windowStart, e < windowEnd ? e : windowEnd];
  }).toList();
}

/// Build the free intervals (the complement of busy+tentative) within
/// [windowStart, windowEnd].
List<Interval> computeFreeIntervals(
  List<TimeBlock> blocks,
  int windowStart,
  int windowEnd,
) {
  final busy = mergeIntervals(
    blocks
        .where(
          (b) =>
              b.type == TimeBlockType.busy || b.type == TimeBlockType.tentative,
        )
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

/// Floor `ms` to the start of its local calendar day in [timezone].
/// Uses TZDateTime so DST transitions do not shift the wall-clock boundary.
TZDateTime _localStartOfDay(int ms, String timezone) {
  final loc = getLocation(timezone);
  final t = TZDateTime.fromMillisecondsSinceEpoch(loc, ms);
  return TZDateTime(loc, t.year, t.month, t.day);
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
  var dayStart = _localStartOfDay(start, timezone);
  while (dayStart.millisecondsSinceEpoch < end) {
    final wakeMs = TZDateTime(
      loc,
      dayStart.year,
      dayStart.month,
      dayStart.day,
      wakeHour,
    ).millisecondsSinceEpoch;
    final sleepMs = TZDateTime(
      loc,
      dayStart.year,
      dayStart.month,
      dayStart.day,
      sleepHour,
    ).millisecondsSinceEpoch;
    final clipStart = start > wakeMs ? start : wakeMs;
    final clipEnd = end < sleepMs ? end : sleepMs;
    if (clipStart < clipEnd) result.add([clipStart, clipEnd]);
    dayStart = TZDateTime(loc, dayStart.year, dayStart.month, dayStart.day + 1);
  }
  return result;
}

List<Interval> clipToWakingHours(List<Interval> intervals, String timezone) {
  return intervals
      .expand((iv) => clipIntervalToWakingHours(iv[0], iv[1], timezone))
      .toList();
}

/// Split multi-day intervals into per-day (00:00-24:00 local) segments.
/// Used when showLateNightWindows=true so the calendar gets one window/day.
List<Interval> clipToDayBoundaries(List<Interval> intervals, String timezone) {
  final result = <Interval>[];
  final loc = getLocation(timezone);
  for (final iv in intervals) {
    var dayStart = _localStartOfDay(iv[0], timezone);
    while (dayStart.millisecondsSinceEpoch < iv[1]) {
      final dayEnd = TZDateTime(
        loc,
        dayStart.year,
        dayStart.month,
        dayStart.day + 1,
      ).millisecondsSinceEpoch;
      final clipStart = iv[0] > dayStart.millisecondsSinceEpoch
          ? iv[0]
          : dayStart.millisecondsSinceEpoch;
      final clipEnd = iv[1] < dayEnd ? iv[1] : dayEnd;
      if (clipStart < clipEnd) result.add([clipStart, clipEnd]);
      dayStart = TZDateTime(
        loc,
        dayStart.year,
        dayStart.month,
        dayStart.day + 1,
      );
    }
  }
  return result;
}

/// Per-partner preferences that affect how overlap windows are clipped and
/// scored. Mirrors the TS `PartnerPrefs` interface.
class PartnerPrefs {
  final bool showLateNightWindows;
  const PartnerPrefs({this.showLateNightWindows = false});
}

/// Score a candidate overlap window. Longer windows score higher; evenings
/// (18:00-21:00 local) and weekends (Sat/Sun) get a +5 bonus each; windows
/// further in the future decay by 0.5/day from a base of 10.
///
/// Drops the dead `_timezoneB` param from the TS signature (it was ignored).
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

/// Stable hash of a block list, independent of input order. Used to short-circuit
/// recomputation when neither partner's blocks have changed.
String computeBlockHash(List<TimeBlock> blocks) {
  final sorted = [...blocks]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  final str = sorted
      .map(
        (b) =>
            '${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type.name}',
      )
      .join('|');
  return sha256.convert(utf8.encode(str)).toString().substring(0, 16);
}

/// Compute mutual free-time windows for two partners over the next
/// [kHorizonDays] days. Busy+tentative blocks are subtracted, the result is
/// intersected and clipped per partner (waking-hours vs day-boundaries based
/// on `showLateNightWindows`), filtered to >= [kMinWindowMinutes], sorted by
/// score descending, and capped at [kMaxWindows].
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
      .map(
        (iv) => OverlapWindow(
          startUtc: iv[0],
          endUtc: iv[1],
          durationMinutes: ((iv[1] - iv[0]) / 60000).round(),
          score: scoreWindow(iv[0], iv[1], timezoneA, now),
          reasonableBoth: reasonableBoth,
        ),
      )
      .where((w) => w.durationMinutes >= kMinWindowMinutes)
      .toList();

  windows.sort((a, b) => b.score.compareTo(a.score));
  return windows.length > kMaxWindows
      ? windows.sublist(0, kMaxWindows)
      : windows;
}
