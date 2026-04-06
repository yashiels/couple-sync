import 'dart:ui' as ui;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Helper class for timezone operations.
/// Provides auto-detection, listing, and grouping of IANA timezone IDs.
class TimezoneHelper {
  /// Whether timezone data has been initialized.
  static bool _initialized = false;

  /// Initialize timezone database.
  /// Must be called before using other methods.
  static Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  /// Get the device's current timezone as an IANA timezone ID.
  /// Falls back to 'UTC' if detection fails.
  static Future<String> detectDeviceTimezone() async {
    try {
      // Use Flutter's window timezone which gives IANA ID
      final String? timezoneName = ui.PlatformDispatcher.instance.timeZoneName;
      if (timezoneName != null && timezoneName.isNotEmpty) {
        // Validate it's a valid IANA timezone
        if (isValidTimezone(timezoneName)) {
          return timezoneName;
        }
      }
    } catch (_) {
      // Fall through to UTC fallback
    }
    return 'UTC';
  }

  /// Check if a timezone ID is valid.
  static bool isValidTimezone(String timezoneId) {
    try {
      tz.getLocation(timezoneId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get all IANA timezone IDs.
  static List<String> getAllTimezones() {
    return tz.timeZoneDatabase.locations.keys.toList()..sort();
  }

  /// Get timezone IDs grouped by region.
  /// Returns a map where keys are region names (e.g., "Africa", "America")
  /// and values are lists of timezone IDs in that region.
  static Map<String, List<String>> getTimezonesGroupedByRegion() {
    final Map<String, List<String>> grouped = {};
    
    for (final tzId in getAllTimezones()) {
      final region = _extractRegion(tzId);
      grouped.putIfAbsent(region, () => []).add(tzId);
    }

    // Sort regions alphabetically
    final sortedKeys = grouped.keys.toList()..sort();
    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  /// Extract the region part of a timezone ID.
  /// E.g., "Africa/Johannesburg" → "Africa"
  static String _extractRegion(String timezoneId) {
    final slashIndex = timezoneId.indexOf('/');
    if (slashIndex == -1) {
      return 'Other';
    }
    return timezoneId.substring(0, slashIndex);
  }

  /// Get a human-readable display name for a timezone ID.
  /// E.g., "Africa/Johannesburg" → "Johannesburg (Africa)"
  static String getDisplayName(String timezoneId) {
    final slashIndex = timezoneId.indexOf('/');
    if (slashIndex == -1) {
      return timezoneId;
    }
    final region = timezoneId.substring(0, slashIndex);
    final city = timezoneId.substring(slashIndex + 1).replaceAll('_', ' ');
    return '$city ($region)';
  }

  /// Get the current offset for a timezone as a formatted string.
  /// E.g., "UTC+2" or "UTC-5"
  static String getCurrentOffset(String timezoneId) {
    try {
      final location = tz.getLocation(timezoneId);
      final now = tz.TZDateTime.now(location);
      final offset = now.timeZoneOffset;
      
      final hours = offset.inHours;
      final minutes = offset.inMinutes.remainder(60).abs();
      
      final sign = hours >= 0 ? '+' : '';
      
      if (minutes == 0) {
        return 'UTC$sign$hours';
      } else {
        return 'UTC$sign$hours:${minutes.toString().padLeft(2, '0')}';
      }
    } catch (_) {
      return 'UTC';
    }
  }

  /// Get the current time in a timezone as a formatted string.
  /// E.g., "14:30"
  static String getCurrentTime(String timezoneId) {
    try {
      final location = tz.getLocation(timezoneId);
      final now = tz.TZDateTime.now(location);
      final hour = now.hour.toString().padLeft(2, '0');
      final minute = now.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '--:--';
    }
  }

  /// Search timezones by query string.
  /// Returns matching timezone IDs, sorted by relevance.
  static List<String> searchTimezones(String query) {
    if (query.isEmpty) {
      return getAllTimezones();
    }

    final normalizedQuery = query.toLowerCase();
    final allTimezones = getAllTimezones();
    
    // Prioritize matches that start with the query
    final startMatches = <String>[];
    final containsMatches = <String>[];
    
    for (final tzId in allTimezones) {
      final normalized = tzId.toLowerCase().replaceAll('_', ' ');
      if (normalized.startsWith(normalizedQuery)) {
        startMatches.add(tzId);
      } else if (normalized.contains(normalizedQuery)) {
        containsMatches.add(tzId);
      }
    }
    
    return [...startMatches, ...containsMatches];
  }

  /// Search timezones grouped by region.
  /// Returns a map of region → matching timezone IDs.
  static Map<String, List<String>> searchTimezonesGroupedByRegion(String query) {
    final matches = searchTimezones(query);
    final Map<String, List<String>> grouped = {};
    
    for (final tzId in matches) {
      final region = _extractRegion(tzId);
      grouped.putIfAbsent(region, () => []).add(tzId);
    }

    // Sort regions alphabetically
    final sortedKeys = grouped.keys.toList()..sort();
    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  /// Get common timezones for quick access.
  /// Returns a list of frequently used timezone IDs.
  static List<String> getCommonTimezones() {
    return [
      'UTC',
      'Africa/Johannesburg',
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Los_Angeles',
      'America/Toronto',
      'America/Vancouver',
      'Europe/London',
      'Europe/Paris',
      'Europe/Berlin',
      'Europe/Amsterdam',
      'Asia/Tokyo',
      'Asia/Shanghai',
      'Asia/Singapore',
      'Asia/Dubai',
      'Australia/Sydney',
      'Australia/Melbourne',
      'Pacific/Auckland',
    ];
  }
}
