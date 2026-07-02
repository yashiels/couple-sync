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
