import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../calendar_service.dart';

/// Provider for the CalendarService singleton.
final calendarServiceProvider = Provider<CalendarService>((ref) {
  return CalendarService();
});

/// Provider for calendar connection state.
/// Returns true if Google Calendar is connected.
final calendarConnectionProvider = FutureProvider<bool>((ref) async {
  final calendarService = ref.watch(calendarServiceProvider);
  return calendarService.isConnected;
});

/// Notifier for managing calendar connection state with loading/error states.
class CalendarConnectionNotifier extends StateNotifier<AsyncValue<bool>> {
  final CalendarService _calendarService;
  final Ref _ref;

  CalendarConnectionNotifier(this._calendarService, this._ref)
      : super(const AsyncValue.loading()) {
    _loadConnectionState();
  }

  Future<void> _loadConnectionState() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _calendarService.isConnected);
  }

  /// Connects to Google Calendar.
  /// Returns true if connection was successful.
  Future<bool> connect() async {
    state = const AsyncValue.loading();
    try {
      final connected = await _calendarService.connect();
      state = AsyncValue.data(connected);
      // Refresh the connection provider
      _ref.invalidate(calendarConnectionProvider);
      return connected;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  /// Disconnects from Google Calendar.
  Future<void> disconnect() async {
    state = const AsyncValue.loading();
    try {
      await _calendarService.disconnect();
      state = const AsyncValue.data(false);
      // Refresh the connection provider
      _ref.invalidate(calendarConnectionProvider);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  /// Refreshes the connection state.
  Future<void> refresh() async {
    await _loadConnectionState();
  }
}

/// Provider for the calendar connection notifier.
final calendarConnectionNotifierProvider =
    StateNotifierProvider<CalendarConnectionNotifier, AsyncValue<bool>>((ref) {
  final calendarService = ref.watch(calendarServiceProvider);
  return CalendarConnectionNotifier(calendarService, ref);
});
