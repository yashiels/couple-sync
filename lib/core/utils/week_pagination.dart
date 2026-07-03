/// Fixed-epoch week pagination helper.
///
/// Maps dates <-> PageView page indices so that "Today" can jump to a stable
/// page regardless of which week the user has swiped to. Page 0 is the week
/// of 2000-01-03 (a Monday), giving a large positive range for all real dates.
class WeekPager {
  final bool weekStartMonday;
  WeekPager({this.weekStartMonday = true});

  /// Fixed epoch: 2000-01-03 was a Monday.
  static final DateTime epoch = DateTime(2000, 1, 3);

  /// Start of the week (Monday or Sunday) containing [d].
  DateTime weekStartForDate(DateTime d) {
    final weekday = d.weekday; // Mon=1..Sun=7
    final offset = weekStartMonday ? weekday - 1 : (weekday % 7);
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: offset));
  }

  /// Week start for a given page index.
  DateTime weekStartForPage(int page) {
    return epoch.add(Duration(days: page * 7));
  }

  /// Page index whose week contains [d].
  int pageIndexForDate(DateTime d) {
    final start = weekStartForDate(d);
    return start.difference(epoch).inDays ~/ 7;
  }
}
