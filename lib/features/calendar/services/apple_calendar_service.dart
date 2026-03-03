import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';

import '../../../shared/models/time_block_model.dart';

/// Provides Apple / device calendar integration via the device_calendar plugin.
///
/// On iOS this reads from EventKit (Apple Calendar).
/// On Android this reads from the system calendar store.
/// Permission denial is handled gracefully -- callers receive an empty list.
class AppleCalendarService {
  AppleCalendarService({DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? DeviceCalendarPlugin();

  final DeviceCalendarPlugin _plugin;

  // ── Permissions ───────────────────────────────────────────────────────────

  /// Returns true if calendar read permission is already granted.
  Future<bool> hasPermission() async {
    try {
      final result = await _plugin.hasPermissions();
      return result.isSuccess && (result.data ?? false);
    } catch (e) {
      debugPrint('AppleCalendarService.hasPermission error: $e');
      return false;
    }
  }

  /// Requests calendar read permission from the OS.
  /// Returns true when permission is granted.
  Future<bool> requestPermission() async {
    try {
      final result = await _plugin.requestPermissions();
      return result.isSuccess && (result.data ?? false);
    } catch (e) {
      debugPrint('AppleCalendarService.requestPermission error: $e');
      return false;
    }
  }

  /// Ensures permission is granted, requesting it if not already held.
  /// Returns false if the user denies.
  Future<bool> ensurePermission() async {
    if (await hasPermission()) return true;
    return requestPermission();
  }

  // ── Calendars ─────────────────────────────────────────────────────────────

  /// Returns all calendars visible on the device.
  /// Returns an empty list when permission is denied.
  Future<List<Calendar>> getCalendars() async {
    final granted = await ensurePermission();
    if (!granted) return [];

    try {
      final result = await _plugin.retrieveCalendars();
      if (!result.isSuccess) return [];
      return result.data ?? [];
    } catch (e) {
      debugPrint('AppleCalendarService.getCalendars error: $e');
      return [];
    }
  }

  // ── Event fetch ───────────────────────────────────────────────────────────

  /// Reads all events from all device calendars for the next [days] days and
  /// converts them to [TimeBlock] models (source = google, type = busy).
  ///
  /// Events with null start or end times are skipped.
  /// Returns an empty list when permission is denied.
  Future<List<TimeBlock>> fetchEvents({
    required String userId,
    required String coupleId,
    int days = 14,
  }) async {
    final calendars = await getCalendars();
    if (calendars.isEmpty) return [];

    final now = DateTime.now();
    final until = now.add(Duration(days: days));
    final blocks = <TimeBlock>[];

    for (final calendar in calendars) {
      if (calendar.id == null) continue;

      try {
        final result = await _plugin.retrieveEvents(
          calendar.id!,
          RetrieveEventsParams(startDate: now, endDate: until),
        );
        if (!result.isSuccess || result.data == null) continue;

        for (final event in result.data!) {
          final start = event.start;
          final end = event.end;
          if (start == null || end == null) continue;

          // Skip all-day events if they have zero duration after UTC conversion.
          if (!end.toUtc().isAfter(start.toUtc())) continue;

          blocks.add(TimeBlock(
            id: '',
            userId: userId,
            coupleId: coupleId,
            title: event.title ?? 'Busy',
            startUtc: start.toUtc(),
            endUtc: end.toUtc(),
            type: BlockType.busy,
            timezone: 'UTC',
            source: BlockSource.manual,
            visibility: TimeBlockVisibility.bothPartners,
            category: BlockCategory.other,
            createdAt: DateTime.now().toUtc(),
          ));
        }
      } catch (e) {
        debugPrint(
          'AppleCalendarService.fetchEvents error for calendar '
          '${calendar.id}: $e',
        );
        // Continue with remaining calendars.
      }
    }

    return blocks;
  }
}
