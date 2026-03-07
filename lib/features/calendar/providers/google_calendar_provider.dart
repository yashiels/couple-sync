import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../../shared/models/calendar_connection.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/providers/auth_providers.dart';
import '../../../shared/providers/pairing_providers.dart';
import '../services/google_calendar_service.dart';

// ── Shared GoogleSignIn instance ──────────────────────────────────────────────

/// A single [GoogleSignIn] instance shared between [AuthService] and
/// [GoogleCalendarService]. Only created on mobile — on web, Firebase Auth
/// uses [signInWithPopup] directly and does not need [GoogleSignIn].
final sharedGoogleSignInProvider = Provider<GoogleSignIn?>(
  (_) => kIsWeb
      ? null
      : GoogleSignIn(
          scopes: [
            'email',
          ],
        ),
);

// ── Service ───────────────────────────────────────────────────────────────────

/// Singleton [GoogleCalendarService] instance backed by the shared
/// [GoogleSignIn] so that auth and calendar use the same OAuth session.
/// On web, passes null so the service creates its own instance if needed.
final googleCalendarServiceProvider = Provider<GoogleCalendarService>(
  (ref) {
    final googleSignIn = ref.watch(sharedGoogleSignInProvider);
    return GoogleCalendarService(
      googleSignIn: googleSignIn,
    );
  },
);

// ── Multi-account connection management ──────────────────────────────────────

/// Manages Google Calendar account connections (supports multiple accounts).
class GoogleCalendarConnectionNotifier
    extends StateNotifier<List<CalendarConnection>> {
  GoogleCalendarConnectionNotifier(this._service, this._ref)
      : _firestore = FirebaseFirestore.instance,
        super([]);

  final GoogleCalendarService _service;
  final FirebaseFirestore _firestore;
  final Ref _ref;

  /// Loads connections from the user's calendarConnections list.
  void loadConnections(List<CalendarConnection> connections) {
    state = connections
        .where((c) => c.provider == CalendarProvider.google)
        .toList();
  }

  /// Connects a new Google account and persists it.
  ///
  /// Uses a read-then-write approach to check email uniqueness in Firestore,
  /// preventing duplicates even when in-memory state is stale.
  /// Does NOT disconnect the current Google session so that sync can work
  /// immediately after connecting.
  Future<bool> connectAccount(String userId) async {
    final email = await _service.connectAccount();
    if (email == null) return false;

    // Read current connections from Firestore to check for duplicates
    // (in-memory state may be stale).
    final userDoc =
        await _firestore.collection('users').doc(userId).get();
    final existingRaw =
        (userDoc.data()?['calendarConnections'] as List<dynamic>?) ?? [];
    final existingConnections = existingRaw
        .map((e) => CalendarConnection.fromMap(e as Map<String, dynamic>))
        .toList();

    // If email already exists as a Google connection, skip the write.
    if (existingConnections.any(
        (c) => c.email == email && c.provider == CalendarProvider.google)) {
      // Still refresh local state from Firestore to stay in sync.
      await _refreshUserState(userId);
      return true;
    }

    final connection = CalendarConnection(
      provider: CalendarProvider.google,
      email: email,
      connectedAt: DateTime.now().toUtc(),
    );

    // Write the full updated list to Firestore (avoids arrayUnion
    // deduplication issues caused by unique id/timestamp fields).
    final updatedList = [...existingConnections, connection];
    await _firestore.collection('users').doc(userId).update({
      'calendarConnections': updatedList.map((c) => c.toMap()).toList(),
    });

    // Refresh currentUserProvider from Firestore so the rest of the app
    // sees the updated connections immediately.
    await _refreshUserState(userId);
    return true;
  }

  /// Adds a calendar connection for the given email if one doesn't already
  /// exist. Used to auto-add the Google sign-in account.
  Future<void> ensureConnection({
    required String userId,
    required String email,
  }) async {
    final userDoc =
        await _firestore.collection('users').doc(userId).get();
    final existingRaw =
        (userDoc.data()?['calendarConnections'] as List<dynamic>?) ?? [];
    final existingConnections = existingRaw
        .map((e) => CalendarConnection.fromMap(e as Map<String, dynamic>))
        .toList();

    if (existingConnections.any(
        (c) => c.email == email && c.provider == CalendarProvider.google)) {
      return; // Already exists
    }

    final connection = CalendarConnection(
      provider: CalendarProvider.google,
      email: email,
      connectedAt: DateTime.now().toUtc(),
    );

    final updatedList = [...existingConnections, connection];
    await _firestore.collection('users').doc(userId).update({
      'calendarConnections': updatedList.map((c) => c.toMap()).toList(),
    });

    // Refresh currentUserProvider so the UI picks up the new connection.
    await _refreshUserState(userId);
  }

  /// Removes a connected account by its connection ID and cleans up all
  /// Google-sourced time blocks for that user in the couple's subcollection.
  Future<void> removeAccount(String userId, String connectionId) async {
    // Read-then-write to stay consistent with Firestore.
    final userDoc =
        await _firestore.collection('users').doc(userId).get();
    final existingRaw =
        (userDoc.data()?['calendarConnections'] as List<dynamic>?) ?? [];
    final updatedList = existingRaw
        .map((e) => CalendarConnection.fromMap(e as Map<String, dynamic>))
        .where((c) => c.id != connectionId)
        .map((c) => c.toMap())
        .toList();

    await _firestore.collection('users').doc(userId).update({
      'calendarConnections': updatedList,
    });

    // Delete all Google-sourced time blocks for this user so stale busy
    // periods don't linger after disconnecting the calendar.
    final couple = _ref.read(currentCoupleProvider);
    if (couple != null) {
      final blocksRef = _firestore
          .collection('timeblocks')
          .doc(couple.coupleId)
          .collection('blocks');
      final staleBlocks = await blocksRef
          .where('userId', isEqualTo: userId)
          .where('source', isEqualTo: 'google')
          .get();

      final batch = _firestore.batch();
      for (final doc in staleBlocks.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // Refresh state from Firestore.
    await _refreshUserState(userId);
  }

  /// Re-reads the user document from Firestore and updates
  /// [currentUserProvider] so all providers see the latest data.
  Future<void> _refreshUserState(String userId) async {
    final freshDoc =
        await _firestore.collection('users').doc(userId).get();
    if (freshDoc.exists) {
      final freshUser = UserModel.fromFirestore(freshDoc);
      _ref.read(currentUserProvider.notifier).state = freshUser;
    }
  }
}

/// Provider for the list of connected Google Calendar accounts.
/// Automatically loads connections from the current user's Firestore data.
final googleCalendarConnectionsProvider = StateNotifierProvider<
    GoogleCalendarConnectionNotifier, List<CalendarConnection>>((ref) {
  final notifier = GoogleCalendarConnectionNotifier(
    ref.watch(googleCalendarServiceProvider),
    ref,
  );

  // Auto-load connections from the current user's Firestore data.
  final user = ref.watch(currentUserProvider);
  if (user != null) {
    notifier.loadConnections(user.calendarConnections);
  }

  return notifier;
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
