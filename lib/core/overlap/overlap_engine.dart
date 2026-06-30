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
