import 'package:flutter_test/flutter_test.dart';
import 'package:couple_sync/core/utils/week_pagination.dart';

void main() {
  test('pageIndexForDate returns today\'s page within range', () {
    final today = DateTime(2024, 6, 5);
    final pager = WeekPager(weekStartMonday: true);
    final idx = pager.pageIndexForDate(today);
    expect(idx, greaterThanOrEqualTo(0));
    // The date at that page must contain `today`.
    final weekStart = pager.weekStartForPage(idx);
    expect(today.difference(weekStart).inDays, lessThan(7));
    expect(today.difference(weekStart).inDays, greaterThanOrEqualTo(0));
  });
}
