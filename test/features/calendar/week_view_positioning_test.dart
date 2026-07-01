import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:couple_sync/core/utils/block_positioning.dart';

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('block local-day offset uses the block timezone, not UTC', () {
    // A block 09:00-10:00 America/New_York on 2024-06-01.
    final ny = tz.getLocation('America/New_York');
    final start = tz.TZDateTime(ny, 2024, 6, 1, 9).millisecondsSinceEpoch;
    final end = tz.TZDateTime(ny, 2024, 6, 1, 10).millisecondsSinceEpoch;
    final offset = localDayOffsetMinutes(start, 'America/New_York');
    expect(offset, 9 * 60); // 09:00 local = 540 min from local midnight
  });

  test('cross-midnight block positions by its own tz', () {
    final ny = tz.getLocation('America/New_York');
    final start = tz.TZDateTime(ny, 2024, 6, 1, 23, 30).millisecondsSinceEpoch;
    final offset = localDayOffsetMinutes(start, 'America/New_York');
    expect(offset, 23 * 60 + 30);
  });
}
