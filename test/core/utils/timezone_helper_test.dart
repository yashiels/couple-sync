import 'package:couple_sync/core/utils/timezone_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await TimezoneHelper.initialize();
  });

  group('TimezoneHelper.isValidTimezone', () {
    test('returns true for known IANA timezone IDs', () {
      expect(TimezoneHelper.isValidTimezone('UTC'), isTrue);
      expect(TimezoneHelper.isValidTimezone('Africa/Johannesburg'), isTrue);
      expect(TimezoneHelper.isValidTimezone('America/New_York'), isTrue);
    });

    test('returns false for invalid timezone IDs', () {
      expect(TimezoneHelper.isValidTimezone('Not/ATimezone'), isFalse);
      expect(TimezoneHelper.isValidTimezone(''), isFalse);
      expect(TimezoneHelper.isValidTimezone('INVALID'), isFalse);
    });

    test('UTC is always valid', () {
      expect(TimezoneHelper.isValidTimezone('UTC'), isTrue);
    });
  });

  group('TimezoneHelper.getAllTimezones', () {
    test('returns a non-empty sorted list of timezone IDs', () {
      final zones = TimezoneHelper.getAllTimezones();
      expect(zones, isNotEmpty);
      expect(zones, isSorted);
    });

    test('contains common well-known timezone IDs', () {
      final zones = TimezoneHelper.getAllTimezones();
      expect(zones, contains('UTC'));
      expect(zones, contains('America/New_York'));
      expect(zones, contains('Europe/London'));
      expect(zones, contains('Asia/Tokyo'));
    });
  });

  group('TimezoneHelper.getTimezonesGroupedByRegion', () {
    test('returns map with known regions', () {
      final grouped = TimezoneHelper.getTimezonesGroupedByRegion();
      expect(grouped, isNotEmpty);
      expect(grouped.keys, contains('America'));
      expect(grouped.keys, contains('Europe'));
      expect(grouped.keys, contains('Asia'));
    });

    test('timezones without a slash are placed under Other', () {
      final grouped = TimezoneHelper.getTimezonesGroupedByRegion();
      // UTC has no slash — lands in "Other"
      if (grouped.containsKey('Other')) {
        expect(grouped['Other'], contains('UTC'));
      }
    });

    test('regions are sorted alphabetically', () {
      final regions = TimezoneHelper.getTimezonesGroupedByRegion().keys.toList();
      final sorted = [...regions]..sort();
      expect(regions, equals(sorted));
    });
  });

  group('TimezoneHelper.getDisplayName', () {
    test('formats city and region for standard IANA IDs', () {
      expect(
        TimezoneHelper.getDisplayName('Africa/Johannesburg'),
        equals('Johannesburg (Africa)'),
      );
      expect(
        TimezoneHelper.getDisplayName('America/New_York'),
        equals('New York (America)'),
      );
    });

    test('replaces underscores with spaces in city name', () {
      expect(
        TimezoneHelper.getDisplayName('America/New_York'),
        equals('New York (America)'),
      );
    });

    test('returns the ID as-is when there is no slash', () {
      expect(TimezoneHelper.getDisplayName('UTC'), equals('UTC'));
    });
  });

  group('TimezoneHelper.getCurrentOffset', () {
    test('returns UTC string for UTC timezone', () {
      final offset = TimezoneHelper.getCurrentOffset('UTC');
      expect(offset, equals('UTC+0'));
    });

    test('returns a formatted UTC±N string for valid timezones', () {
      final offset = TimezoneHelper.getCurrentOffset('America/New_York');
      // Offset is either UTC-5 (EST) or UTC-4 (EDT)
      expect(offset, matches(RegExp(r'^UTC[+-]\d+(:\d{2})?$')));
    });

    test('returns UTC fallback for invalid timezone ID', () {
      final offset = TimezoneHelper.getCurrentOffset('Not/Valid');
      expect(offset, equals('UTC'));
    });
  });

  group('TimezoneHelper.getCurrentTime', () {
    test('returns HH:MM formatted string for a valid timezone', () {
      final time = TimezoneHelper.getCurrentTime('UTC');
      expect(time, matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    test('returns -- :-- sentinel for invalid timezone ID', () {
      final time = TimezoneHelper.getCurrentTime('Not/Valid');
      expect(time, equals('--:--'));
    });
  });

  group('TimezoneHelper.searchTimezones', () {
    test('returns all timezones for empty query', () {
      final all = TimezoneHelper.getAllTimezones();
      final results = TimezoneHelper.searchTimezones('');
      expect(results.length, equals(all.length));
    });

    test('returns matching timezones for a partial query', () {
      final results = TimezoneHelper.searchTimezones('London');
      expect(results, contains('Europe/London'));
    });

    test('is case-insensitive', () {
      final lower = TimezoneHelper.searchTimezones('london');
      final upper = TimezoneHelper.searchTimezones('LONDON');
      expect(lower, equals(upper));
    });

    test('returns empty list when no match is found', () {
      final results = TimezoneHelper.searchTimezones('zzz_no_match_xyz');
      expect(results, isEmpty);
    });
  });

  group('TimezoneHelper.getCommonTimezones', () {
    test('returns a non-empty list', () {
      expect(TimezoneHelper.getCommonTimezones(), isNotEmpty);
    });

    test('all entries are valid IANA timezone IDs', () {
      for (final tzId in TimezoneHelper.getCommonTimezones()) {
        expect(
          TimezoneHelper.isValidTimezone(tzId),
          isTrue,
          reason: '$tzId should be a valid timezone',
        );
      }
    });

    test('contains UTC', () {
      expect(TimezoneHelper.getCommonTimezones(), contains('UTC'));
    });
  });

  group('TimezoneHelper.detectDeviceTimezone', () {
    test('returns a non-empty string', () async {
      final tz = await TimezoneHelper.detectDeviceTimezone();
      expect(tz, isNotEmpty);
    });

    test('falls back to UTC when detection fails in test environment', () async {
      // In the test VM the timezone name may not be in the abbreviation map,
      // so the helper always returns UTC or a valid mapped IANA ID.
      final tz = await TimezoneHelper.detectDeviceTimezone();
      expect(TimezoneHelper.isValidTimezone(tz), isTrue);
    });
  });
}

/// Custom matcher that verifies a list is in sorted (ascending) order.
Matcher get isSorted => _IsSorted();

class _IsSorted extends Matcher {
  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    if (item is! List) return false;
    for (var i = 0; i < item.length - 1; i++) {
      if ((item[i] as Comparable).compareTo(item[i + 1]) > 0) return false;
    }
    return true;
  }

  @override
  Description describe(Description description) =>
      description.add('a sorted list');
}
