import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/google_calendar_service.dart';

// ── Service ───────────────────────────────────────────────────────────────────

final googleCalendarServiceProvider = Provider<GoogleCalendarService>(
  (_) => GoogleCalendarService(),
);

// ── Connection status ─────────────────────────────────────────────────────────

/// Whether the user is currently connected to Google Calendar.
final googleCalendarConnectionProvider = StateNotifierProvider<
    _ConnectionNotifier, bool>(
  (ref) => _ConnectionNotifier(ref.watch(googleCalendarServiceProvider)),
);

class _ConnectionNotifier extends StateNotifier<bool> {
  _ConnectionNotifier(this._service) : super(_service.isConnected);

  final GoogleCalendarService _service;

  /// Initiates the Google OAuth sign-in flow.
  Future<bool> connect() async {
    final success = await _service.connect();
    state = success;
    return success;
  }

  /// Disconnects and revokes the OAuth token.
  Future<void> disconnect() async {
    await _service.disconnect();
    state = false;
  }

  /// Tries to restore a previous session silently (no UI prompt).
  Future<void> trySilentRestore() async {
    final restored = await _service.trySilentSignIn();
    state = restored;
  }
}

// ── Last sync time ────────────────────────────────────────────────────────────

/// Tracks the timestamp of the most recent successful sync.
final googleCalendarLastSyncProvider =
    StateNotifierProvider<_LastSyncNotifier, DateTime?>(
  (_) => _LastSyncNotifier(),
);

class _LastSyncNotifier extends StateNotifier<DateTime?> {
  _LastSyncNotifier() : super(null);

  void recordSync() => state = DateTime.now().toUtc();
}

// ── Sync trigger ──────────────────────────────────────────────────────────────

/// Provides a method to trigger a full Google Calendar sync.
/// Exposes [AsyncValue] to let the UI react to loading / error states.
final googleCalendarSyncProvider =
    StateNotifierProvider<_SyncNotifier, AsyncValue<void>>(
  (ref) => _SyncNotifier(
    ref.watch(googleCalendarServiceProvider),
    ref.watch(googleCalendarLastSyncProvider.notifier),
  ),
);

class _SyncNotifier extends StateNotifier<AsyncValue<void>> {
  _SyncNotifier(this._service, this._lastSync) : super(const AsyncValue.data(null));

  final GoogleCalendarService _service;
  final _LastSyncNotifier _lastSync;

  /// Syncs Google Calendar busy periods to Firestore.
  Future<void> sync({
    required String userId,
    required String coupleId,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () async {
        await _service.syncToFirestore(userId: userId, coupleId: coupleId);
        _lastSync.recordSync();
      },
    );
  }
}
