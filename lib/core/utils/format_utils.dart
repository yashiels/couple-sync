import 'package:intl/intl.dart';

/// Shared formatters so screens stop hand-rolling dates/durations.
String formatDurationMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (mins == 0) return '$hours hr';
  return '$hours hr $mins min';
}

String formatDateYMd(DateTime dt) => DateFormat.yMd().format(dt);

/// Locale-aware clock time — `jm()` gives 12h with am/pm where the locale
/// expects it (never the 24h-only `Hm` skeleton).
String formatTimeHm(DateTime dt) => DateFormat.jm().format(dt);
String formatMonth(DateTime dt) => DateFormat.MMM().format(dt);
String formatWeekdayShort(DateTime dt) => DateFormat.E().format(dt);
