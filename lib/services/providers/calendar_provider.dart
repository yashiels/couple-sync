import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../calendar_service.dart';
import '../firestore_service.dart';
import 'auth_state_provider.dart';
import 'firestore_provider.dart';

/// Provider for the CalendarService singleton.
/// Injects the shared [GoogleSignIn] instance from [googleSignInProvider] so
/// that only one platform-channel handle is ever created for the whole app.
final calendarServiceProvider = Provider<CalendarService>((ref) {
  final calendarService = CalendarService(
    googleSignIn: ref.watch(googleSignInProvider),
  );
  ref.onDispose(calendarService.dispose);
  return calendarService;
});

/// Provider for calendar connection state.
/// Returns true if Google Calendar is connected.
final calendarConnectionProvider = FutureProvider<bool>((ref) async {
  final calendarService = ref.watch(calendarServiceProvider);
  return calendarService.isConnected;
});

/// State for calendar sync operations.
class CalendarSyncState {
  final bool isSyncing;
  final DateTime? lastSyncTime;
  final String? syncError;
  final CalendarSyncResult? lastSyncResult;

  const CalendarSyncState({
    this.isSyncing = false,
    this.lastSyncTime,
    this.syncError,
    this.lastSyncResult,
  });

  CalendarSyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncTime,
    String? syncError,
    CalendarSyncResult? lastSyncResult,
    bool clearSyncError = false,
    bool clearLastSyncResult = false,
  }) {
    return CalendarSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
      lastSyncResult: clearLastSyncResult ? null : (lastSyncResult ?? this.lastSyncResult),
    );
  }
}

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

/// Notifier for managing calendar sync operations.
class CalendarSyncNotifier extends StateNotifier<CalendarSyncState> {
  final CalendarService _calendarService;
  final FirestoreService _firestoreService;
  final Ref _ref;

  CalendarSyncNotifier(this._calendarService, this._firestoreService, this._ref)
      : super(const CalendarSyncState()) {
    _loadLastSyncTime();
  }

  /// Load the last sync time from storage.
  Future<void> _loadLastSyncTime() async {
    final lastSync = await _calendarService.getLastSyncTime();
    state = state.copyWith(lastSyncTime: lastSync);
  }

  /// Syncs Google Calendar freebusy data to Firestore.
  ///
  /// Uses a single Firestore WriteBatch (atomic replace strategy): all deletes
  /// of existing google-sourced blocks and all writes of new blocks are staged
  /// together and committed in one shot. There is no window where the old
  /// blocks are gone but the new ones have not yet been written.
  ///
  /// Privacy-first: NEVER fetches or stores event titles.
  Future<CalendarSyncResult> sync() async {
    // Check if connected
    final isConnected = await _calendarService.isConnected;
    if (!isConnected) {
      return CalendarSyncResult(
        blocksFetched: 0,
        blocksDeleted: 0,
        blocksCreated: 0,
        syncedAt: DateTime.now(),
        error: 'Google Calendar is not connected',
      );
    }

    // Get current user info
    final authState = _ref.read(authStateProvider);
    final userProfile = authState.profile;
    final coupleId = userProfile?.coupleId;
    final userId = authState.uid;

    if (userProfile == null || coupleId == null || userId == null) {
      return CalendarSyncResult(
        blocksFetched: 0,
        blocksDeleted: 0,
        blocksCreated: 0,
        syncedAt: DateTime.now(),
        error: 'User not authenticated or not paired',
      );
    }

    state = state.copyWith(isSyncing: true, clearSyncError: true);

    // Track counts so the catch block can report accurate numbers when the
    // error occurs after any partial work (e.g. during the atomic commit).
    int blocksFetched = 0;

    try {
      // 1. Fetch freebusy data from Google Calendar (privacy-first: no titles)
      final busyIntervals = await _calendarService.fetchFreebusy();
      blocksFetched = busyIntervals.length;

      // 2. Convert to TimeBlocks (with generic "Busy" title)
      final newBlocks = _calendarService.convertToTimeBlocks(
        busyIntervals,
        userId: userId,
        timezone: userProfile.timezone,
      );

      // 3. Atomically delete existing google-sourced blocks and write new ones
      //    in a single WriteBatch commit — eliminates the data-loss window that
      //    existed when delete and write were two separate operations.
      final (:deletedCount, :createdCount) =
          await _firestoreService.atomicReplaceGoogleSourcedBlocks(
        coupleId,
        userId,
        newBlocks,
      );

      // 4. Update last sync time
      await _calendarService.updateLastSyncTime();
      final syncTime = DateTime.now();

      final result = CalendarSyncResult(
        blocksFetched: blocksFetched,
        blocksDeleted: deletedCount,
        blocksCreated: createdCount,
        syncedAt: syncTime,
      );

      state = state.copyWith(
        isSyncing: false,
        lastSyncTime: syncTime,
        lastSyncResult: result,
      );

      return result;
    } catch (e) {
      final errorMessage = e is CalendarException
          ? e.message
          : 'Failed to sync calendar: ${e.toString()}';

      // Report the number of blocks that were fetched before the failure so
      // the caller has accurate diagnostics. Because the replace is now atomic,
      // blocksDeleted and blocksCreated are always both 0 on any error —
      // the batch either fully commits or fully rolls back.
      final result = CalendarSyncResult(
        blocksFetched: blocksFetched,
        blocksDeleted: 0,
        blocksCreated: 0,
        syncedAt: DateTime.now(),
        error: errorMessage,
      );

      state = state.copyWith(
        isSyncing: false,
        syncError: errorMessage,
        lastSyncResult: result,
      );

      return result;
    }
  }

  /// Auto-sync if last sync was > 1 hour ago.
  /// Returns null if sync was not needed, otherwise returns the sync result.
  Future<CalendarSyncResult?> autoSyncIfNeeded() async {
    final shouldSync = await _calendarService.shouldAutoSync();
    if (!shouldSync) {
      return null;
    }

    final isConnected = await _calendarService.isConnected;
    if (!isConnected) {
      return null;
    }

    return await sync();
  }

  /// Refresh the last sync time from storage.
  Future<void> refreshLastSyncTime() async {
    await _loadLastSyncTime();
  }
}

/// Provider for the calendar connection notifier.
final calendarConnectionNotifierProvider =
    StateNotifierProvider<CalendarConnectionNotifier, AsyncValue<bool>>((ref) {
  final calendarService = ref.watch(calendarServiceProvider);
  return CalendarConnectionNotifier(calendarService, ref);
});

/// Provider for the calendar sync notifier.
final calendarSyncNotifierProvider =
    StateNotifierProvider<CalendarSyncNotifier, CalendarSyncState>((ref) {
  final calendarService = ref.watch(calendarServiceProvider);
  final firestoreService = ref.watch(firestoreServiceProvider);
  return CalendarSyncNotifier(calendarService, firestoreService, ref);
});
