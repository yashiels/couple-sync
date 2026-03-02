import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/apple_calendar_service.dart';

// ── Service ───────────────────────────────────────────────────────────────────

/// Singleton [AppleCalendarService] instance.
final appleCalendarServiceProvider = Provider<AppleCalendarService>(
  (_) => AppleCalendarService(),
);

// ── Permission status ─────────────────────────────────────────────────────────

/// Tracks calendar permission state.
/// [null] = not yet determined, [true] = granted, [false] = denied.
final appleCalendarPermissionProvider =
    StateNotifierProvider<_PermissionNotifier, AsyncValue<bool>>(
  (ref) => _PermissionNotifier(ref.watch(appleCalendarServiceProvider)),
);

class _PermissionNotifier extends StateNotifier<AsyncValue<bool>> {
  _PermissionNotifier(this._service) : super(const AsyncValue.loading()) {
    _checkInitial();
  }

  final AppleCalendarService _service;

  Future<void> _checkInitial() async {
    state = await AsyncValue.guard(() => _service.hasPermission());
  }

  /// Requests permission from the OS and updates state.
  Future<bool> request() async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => _service.requestPermission());
    state = result;
    return result.valueOrNull ?? false;
  }
}

// ── Calendar list ─────────────────────────────────────────────────────────────

/// Provides the list of device calendars (requires permission).
final appleCalendarsProvider =
    FutureProvider<List<Calendar>>((ref) async {
  final service = ref.watch(appleCalendarServiceProvider);
  return service.getCalendars();
});

// ── Sync trigger ──────────────────────────────────────────────────────────────

/// Tracks the last time device calendars were successfully synced to Firestore.
final appleCalendarLastSyncProvider =
    StateNotifierProvider<_LastSyncNotifier, DateTime?>(
  (_) => _LastSyncNotifier(),
);

class _LastSyncNotifier extends StateNotifier<DateTime?> {
  _LastSyncNotifier() : super(null);

  void recordSync() => state = DateTime.now().toUtc();
}

/// Triggers a fetch of device calendar events and exposes loading / error state.
final appleCalendarSyncProvider =
    StateNotifierProvider<_SyncNotifier, AsyncValue<void>>(
  (ref) => _SyncNotifier(
    ref.watch(appleCalendarServiceProvider),
    ref.watch(appleCalendarLastSyncProvider.notifier),
    ref.watch(appleCalendarPermissionProvider.notifier),
  ),
);

class _SyncNotifier extends StateNotifier<AsyncValue<void>> {
  _SyncNotifier(this._service, this._lastSync, this._permission)
      : super(const AsyncValue.data(null));

  final AppleCalendarService _service;
  final _LastSyncNotifier _lastSync;
  final _PermissionNotifier _permission;

  /// Fetches events and passes them to the provided [onBlocks] callback
  /// so the caller (typically [CalendarSyncService]) can persist them.
  Future<void> sync({
    required String userId,
    required String coupleId,
    required Future<void> Function(List<dynamic> blocks) onBlocks,
  }) async {
    state = const AsyncValue.loading();

    state = await AsyncValue.guard(() async {
      final granted = await _permission.request();
      if (!granted) throw Exception('Calendar permission denied');

      final blocks = await _service.fetchEvents(
        userId: userId,
        coupleId: coupleId,
      );
      await onBlocks(blocks);
      _lastSync.recordSync();
    });
  }
}
