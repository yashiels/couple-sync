import 'package:timezone/timezone.dart';

/// Minutes from the block's local midnight to [startUtc].
/// Uses the block's stored timezone so cross-midnight / cross-tz blocks
/// position correctly against the day grid.
int localDayOffsetMinutes(int startUtc, String timezone) {
  final loc = getLocation(timezone);
  final t = TZDateTime.fromMillisecondsSinceEpoch(loc, startUtc);
  final midnight = TZDateTime(loc, t.year, t.month, t.day);
  return ((t.millisecondsSinceEpoch - midnight.millisecondsSinceEpoch) ~/
      60000);
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
