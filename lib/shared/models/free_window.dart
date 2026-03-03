/// A window in which both partners are simultaneously free.
///
/// Used by the calendar UI to highlight overlap periods.
class FreeWindow {
  final String id;
  final DateTime startUtc;
  final DateTime endUtc;
  final String timezoneA;
  final String timezoneB;
  final String cityA;
  final String cityB;
  final String? suggestedActivity;

  const FreeWindow({
    required this.id,
    required this.startUtc,
    required this.endUtc,
    required this.timezoneA,
    required this.timezoneB,
    required this.cityA,
    required this.cityB,
    this.suggestedActivity,
  });

  /// Wall-clock length of the free window.
  Duration get duration => endUtc.difference(startUtc);

  /// Human-readable duration string, e.g. `"2h 30m"`.
  String get durationLabel {
    final mins = duration.inMinutes;
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
