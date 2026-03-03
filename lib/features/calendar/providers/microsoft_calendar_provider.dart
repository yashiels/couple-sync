import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/microsoft_calendar_service.dart';

// ── Service ───────────────────────────────────────────────────────────────────

/// Singleton [MicrosoftCalendarService] instance.
final microsoftCalendarServiceProvider = Provider<MicrosoftCalendarService>(
  (_) => MicrosoftCalendarService(),
);

// ── Connection status ─────────────────────────────────────────────────────────

/// Whether the user is currently connected to Microsoft Calendar.
final microsoftCalendarConnectionProvider = StateNotifierProvider<
    _ConnectionNotifier, bool>(
  (ref) => _ConnectionNotifier(ref.watch(microsoftCalendarServiceProvider)),
);

class _ConnectionNotifier extends StateNotifier<bool> {
  _ConnectionNotifier(this._service) : super(_service.isConnected);

  final MicrosoftCalendarService _service;

  /// Initiates the Microsoft OAuth 2.0 PKCE sign-in flow.
  Future<bool> connect() async {
    final success = await _service.connect();
    state = success;
    return success;
  }

  /// Disconnects and clears stored OAuth tokens.
  Future<void> disconnect() async {
    await _service.disconnect();
    state = false;
  }

  /// Tries to restore a previous session from stored tokens (no UI prompt).
  Future<void> tryRestoreSession() async {
    final restored = await _service.tryRestoreSession();
    state = restored;
  }
}

// ── Last sync time ────────────────────────────────────────────────────────────

/// Tracks the timestamp of the most recent successful Microsoft sync.
final microsoftCalendarLastSyncProvider =
    StateNotifierProvider<_LastSyncNotifier, DateTime?>(
  (_) => _LastSyncNotifier(),
);

class _LastSyncNotifier extends StateNotifier<DateTime?> {
  _LastSyncNotifier() : super(null);

  void recordSync() => state = DateTime.now().toUtc();
}

// ── Sync trigger ──────────────────────────────────────────────────────────────

/// Provides a method to trigger a full Microsoft Calendar sync.
/// Exposes [AsyncValue] to let the UI react to loading / error states.
final microsoftCalendarSyncProvider =
    StateNotifierProvider<_SyncNotifier, AsyncValue<void>>(
  (ref) => _SyncNotifier(
    ref.watch(microsoftCalendarServiceProvider),
    ref.watch(microsoftCalendarLastSyncProvider.notifier),
  ),
);

class _SyncNotifier extends StateNotifier<AsyncValue<void>> {
  _SyncNotifier(this._service, this._lastSync)
      : super(const AsyncValue.data(null));

  final MicrosoftCalendarService _service;
  final _LastSyncNotifier _lastSync;

  /// Syncs Microsoft Calendar busy periods to Firestore.
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
