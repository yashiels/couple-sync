import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/calendar_connection.dart';
import '../services/google_calendar_service.dart';

// ── Service ───────────────────────────────────────────────────────────────────

/// Singleton [GoogleCalendarService] instance.
final googleCalendarServiceProvider = Provider<GoogleCalendarService>(
  (_) => GoogleCalendarService(),
);

// ── Multi-account connection management ──────────────────────────────────────

/// Manages Google Calendar account connections (supports multiple accounts).
class GoogleCalendarConnectionNotifier
    extends StateNotifier<List<CalendarConnection>> {
  GoogleCalendarConnectionNotifier(this._service)
      : _firestore = FirebaseFirestore.instance,
        super([]);

  final GoogleCalendarService _service;
  final FirebaseFirestore _firestore;

  /// Loads connections from the user's calendarConnections list.
  void loadConnections(List<CalendarConnection> connections) {
    state = connections
        .where((c) => c.provider == CalendarProvider.google)
        .toList();
  }

  /// Connects a new Google account and persists it.
  Future<bool> connectAccount(String userId) async {
    final email = await _service.connectAccount();
    if (email == null) return false;

    // Check if already connected
    if (state.any((c) => c.email == email)) return true;

    final connection = CalendarConnection(
      provider: CalendarProvider.google,
      email: email,
      connectedAt: DateTime.now().toUtc(),
    );

    // Add to Firestore
    await _firestore.collection('users').doc(userId).update({
      'calendarConnections': FieldValue.arrayUnion([connection.toMap()]),
    });

    state = [...state, connection];
    return true;
  }

  /// Removes a connected account by its connection ID.
  Future<void> removeAccount(String userId, String connectionId) async {
    final connection = state.firstWhere((c) => c.id == connectionId);
    await _firestore.collection('users').doc(userId).update({
      'calendarConnections': FieldValue.arrayRemove([connection.toMap()]),
    });
    state = state.where((c) => c.id != connectionId).toList();
    await _service.disconnect();
  }
}

/// Provider for the list of connected Google Calendar accounts.
final googleCalendarConnectionsProvider = StateNotifierProvider<
    GoogleCalendarConnectionNotifier, List<CalendarConnection>>((ref) {
  return GoogleCalendarConnectionNotifier(
    ref.watch(googleCalendarServiceProvider),
  );
});

// ── Backward-compatible boolean provider ─────────────────────────────────────

/// Whether the user has at least one Google Calendar connected.
/// Backward-compatible for screens that still check a simple boolean.
final googleCalendarConnectionProvider = Provider<bool>((ref) {
  final connections = ref.watch(googleCalendarConnectionsProvider);
  return connections.isNotEmpty;
});

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
  _SyncNotifier(this._service, this._lastSync)
      : super(const AsyncValue.data(null));

  final GoogleCalendarService _service;
  final _LastSyncNotifier _lastSync;

  /// Syncs Google Calendar busy periods to Firestore.
  Future<void> sync({
    required String userId,
    required String coupleId,
    String? connectionId,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () async {
        await _service.syncToFirestore(
          userId: userId,
          coupleId: coupleId,
          connectionId: connectionId,
        );
        _lastSync.recordSync();
      },
    );
  }
}
