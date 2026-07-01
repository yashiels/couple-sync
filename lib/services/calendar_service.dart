import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import '../core/models/time_block.dart';

/// Service for handling Google Calendar OAuth and API operations.
/// Manages secure token storage and calendar access with calendar.readonly scope.
/// Result of a calendar sync operation.
class CalendarSyncResult {
  final int blocksFetched;
  final int blocksDeleted;
  final int blocksCreated;
  final DateTime syncedAt;
  final String? error;

  const CalendarSyncResult({
    required this.blocksFetched,
    required this.blocksDeleted,
    required this.blocksCreated,
    required this.syncedAt,
    this.error,
  });

  bool get isSuccess => error == null;
}

class CalendarService {
  static const String _accessTokenKey = 'google_calendar_access_token';
  static const String _tokenExpiryKey = 'google_calendar_token_expiry';
  static const String _lastSyncKey = 'google_calendar_last_sync';

  final GoogleSignIn _googleSignIn;
  final FlutterSecureStorage _secureStorage;

  /// Broadcasts calendar connection-state changes to subscribers.
  /// Closed in [dispose] to prevent timer leaks.
  late final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast(
    // Emit the current connection state whenever a new listener subscribes
    // so that callers using `.first` always receive a value without needing
    // a prior call to [notifyConnectionStateChanged].
    onListen: () => notifyConnectionStateChanged(),
  );

  CalendarService({
    required GoogleSignIn googleSignIn,
    FlutterSecureStorage? secureStorage,
  })  : _googleSignIn = googleSignIn,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Stream of calendar connection state changes.
  ///
  /// Every new subscriber immediately receives the current connection state
  /// via the [onListen] hook.  Subsequent emissions are pushed explicitly via
  /// [notifyConnectionStateChanged] (e.g. after [connect] or [disconnect]),
  /// preventing the unbounded timer leak of the previous [Stream.periodic]
  /// implementation.
  Stream<bool> get connectionStateChanges => _connectionStateController.stream;

  /// Push the current connection state to all active [connectionStateChanges]
  /// subscribers.  Called after [connect] or [disconnect].
  Future<void> notifyConnectionStateChanged() async {
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(await isConnected);
    }
  }

  /// Releases the [StreamController] used by [connectionStateChanges].
  /// Called automatically by the Riverpod provider via [ref.onDispose].
  void dispose() {
    _connectionStateController.close();
  }

  /// Whether Google Calendar is currently connected.
  Future<bool> get isConnected async {
    final accessToken = await _secureStorage.read(key: _accessTokenKey);
    return accessToken != null && accessToken.isNotEmpty;
  }

  /// Connects to Google Calendar with OAuth flow.
  /// Requests calendar.readonly scope and stores tokens securely.
  ///
  /// Returns true if connection was successful.
  /// Throws [CalendarException] with a user-friendly message on failure.
  Future<bool> connect() async {
    try {
      // Trigger the Google Sign-In flow with calendar scope.
      // NOTE: we intentionally do NOT sign out first — signing out before
      // every connect forced a fresh OAuth consent sheet on each reconnect
      // and broke silent refresh. If the user is already signed in, Google
      // returns the existing account without prompting.
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        throw const CalendarException(
          code: 'sign-in-cancelled',
          message: 'Calendar connection was cancelled. Please try again.',
        );
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final accessToken = googleAuth.accessToken;

      if (accessToken == null) {
        throw const CalendarException(
          code: 'no-access-token',
          message: 'Failed to get access token from Google. Please try again.',
        );
      }

      // Store tokens securely
      await _secureStorage.write(
        key: _accessTokenKey,
        value: accessToken,
      );

      // Store token expiry (Google access tokens typically expire in 1 hour)
      final expiryTime = DateTime.now().add(const Duration(hours: 1));
      await _secureStorage.write(
        key: _tokenExpiryKey,
        value: expiryTime.toIso8601String(),
      );

      // Note: google_sign_in doesn't expose refresh tokens directly
      // For long-term access, we'll need to re-authenticate when token expires
      // This is a known limitation - production apps should use server-side OAuth

      await notifyConnectionStateChanged();
      return true;
    } on CalendarException {
      rethrow;
    } catch (e) {
      throw CalendarException(
        code: 'connection-failed',
        message: 'Failed to connect to Google Calendar: ${_getUserFriendlyError(e)}',
      );
    }
  }

  /// Disconnects from Google Calendar.
  /// Clears stored tokens and signs out from Google.
  ///
  /// Throws [CalendarException] with a user-friendly message on failure.
  Future<void> disconnect() async {
    try {
      // Clear stored tokens
      await _secureStorage.delete(key: _accessTokenKey);
      await _secureStorage.delete(key: _tokenExpiryKey);

      // Sign out from Google
      await _googleSignIn.signOut();

      await notifyConnectionStateChanged();
    } catch (e) {
      throw CalendarException(
        code: 'disconnect-failed',
        message: 'Failed to disconnect from Google Calendar. Please try again.',
      );
    }
  }

  /// Gets the current access token, refreshing if necessary.
  /// Returns null if not connected or token refresh failed.
  Future<String?> getAccessToken() async {
    try {
      final accessToken = await _secureStorage.read(key: _accessTokenKey);
      if (accessToken == null || accessToken.isEmpty) {
        return null;
      }

      // Check if token is expired
      final expiryStr = await _secureStorage.read(key: _tokenExpiryKey);
      if (expiryStr != null) {
        final expiry = DateTime.parse(expiryStr);
        if (DateTime.now().isAfter(expiry)) {
          // Token expired, try to refresh
          final refreshed = await _refreshToken();
          if (!refreshed) {
            return null;
          }
          return await _secureStorage.read(key: _accessTokenKey);
        }
      }

      return accessToken;
    } catch (e) {
      return null;
    }
  }

  /// Refreshes the access token.
  /// Returns true if refresh was successful.
  Future<bool> _refreshToken() async {
    try {
      // For google_sign_in, we need to re-authenticate silently
      // Try to sign in silently with the existing account
      final GoogleSignInAccount? googleUser =
          await _googleSignIn.signInSilently();

      if (googleUser == null) {
        // Silent sign-in failed — the user needs to re-authenticate
        // interactively. Do NOT call disconnect() here: that would wipe
        // the cached access token and (via the sync layer) the user's
        // Google-sourced blocks. Returning false lets getAccessToken()
        // surface null so the UI can prompt a soft "reconnect to refresh
        // calendar" state while preserving existing blocks.
        return false;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final accessToken = googleAuth.accessToken;
      if (accessToken == null) {
        return false;
      }

      // Store the new token
      await _secureStorage.write(
        key: _accessTokenKey,
        value: accessToken,
      );

      final expiryTime = DateTime.now().add(const Duration(hours: 1));
      await _secureStorage.write(
        key: _tokenExpiryKey,
        value: expiryTime.toIso8601String(),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Resolves the set of calendar IDs to include in a freebusy query.
  ///
  /// Calls the Calendar List API to pick up the user's primary and secondary
  /// calendars. Any failure (network, permission, API unavailable) is
  /// swallowed and falls back to `['primary']` so a degraded list call can
  /// never block the core freebusy sync.
  Future<List<String>> _resolveCalendarIds(
      calendar.CalendarApi calendarApi) async {
    try {
      final listResponse = await calendarApi.calendarList.list();
      final items = listResponse.items;
      if (items == null || items.isEmpty) {
        return const ['primary'];
      }
      final ids = <String>[];
      for (final entry in items) {
        final id = entry.id;
        if (id != null && id.isNotEmpty) {
          ids.add(id);
        }
      }
      return ids.isEmpty ? const ['primary'] : ids;
    } catch (_) {
      // List call is best-effort: fall back to primary calendar only.
      return const ['primary'];
    }
  }

  /// Fetches freebusy intervals from Google Calendar for the next 14 days.
  /// Returns a list of busy time intervals (start and end times in UTC).
  /// Privacy-first: NEVER fetches or stores event titles.
  Future<List<({DateTime start, DateTime end})>> fetchFreebusy() async {
    final accessToken = await getAccessToken();
    if (accessToken == null) {
      throw const CalendarException(
        code: 'not-connected',
        message: 'Google Calendar is not connected. Please connect first.',
      );
    }

    // Create a short-lived HTTP client owned by this call; closed in finally.
    final rawClient = http.Client();
    try {
      final httpClient = _AuthenticatedClient(
        rawClient,
        auth.AccessToken(
          'Bearer',
          accessToken,
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      final calendarApi = calendar.CalendarApi(httpClient);

      // Calculate time range: now to 14 days ahead
      final now = DateTime.now().toUtc();
      final timeMax = now.add(const Duration(days: 14));

      // Build the list of calendar IDs to query. Prefer the user's full
      // calendar list (so secondary calendars are included); fall back to
      // ['primary'] if the list call is unavailable or returns nothing.
      final List<String> calendarIds = await _resolveCalendarIds(calendarApi);

      // Build freebusy request
      final request = calendar.FreeBusyRequest(
        timeMin: now,
        timeMax: timeMax,
        items: calendarIds
            .map((id) => calendar.FreeBusyRequestItem(id: id))
            .toList(growable: false),
      );

      // Execute freebusy query with exponential backoff on 429/503.
      final response =
          await withBackoff(() => calendarApi.freebusy.query(request));

      // Extract busy intervals from response across ALL queried calendars
      // (not just 'primary'), so secondary calendars contribute too.
      final busyIntervals = <({DateTime start, DateTime end})>[];

      final calendars = response.calendars;
      if (calendars != null) {
        for (final entry in calendars.entries) {
          final busy = entry.value.busy;
          if (busy == null) continue;
          for (final period in busy) {
            final start = period.start;
            final end = period.end;
            if (start != null && end != null) {
              busyIntervals.add((
                start: start,
                end: end,
              ));
            }
          }
        }
      }

      return busyIntervals;
    } on CalendarException {
      rethrow;
    } catch (e) {
      throw CalendarException(
        code: 'freebusy-failed',
        message: 'Failed to fetch calendar availability: ${_getUserFriendlyError(e)}',
      );
    } finally {
      rawClient.close();
    }
  }

  /// Converts freebusy intervals to TimeBlocks.
  /// Privacy-first: Uses generic title "Busy" - never includes event details.
  List<TimeBlock> convertToTimeBlocks(
    List<({DateTime start, DateTime end})> busyIntervals, {
    required String userId,
    required String timezone,
  }) {
    return busyIntervals.map((interval) {
      return TimeBlock(
        userId: userId,
        title: 'Busy', // Privacy-first: generic title, no event details
        type: TimeBlockType.busy,
        category: TimeBlockCategory.other,
        startUtc: interval.start.millisecondsSinceEpoch,
        endUtc: interval.end.millisecondsSinceEpoch,
        timezone: timezone,
        source: TimeBlockSource.google,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: DateTime.now(),
      );
    }).toList();
  }

  /// Gets the last sync time.
  /// Returns null if never synced.
  Future<DateTime?> getLastSyncTime() async {
    try {
      final syncTimeStr = await _secureStorage.read(key: _lastSyncKey);
      if (syncTimeStr == null || syncTimeStr.isEmpty) {
        return null;
      }
      return DateTime.parse(syncTimeStr);
    } catch (e) {
      return null;
    }
  }

  /// Updates the last sync time to now.
  Future<void> updateLastSyncTime() async {
    try {
      await _secureStorage.write(
        key: _lastSyncKey,
        value: DateTime.now().toIso8601String(),
      );
    } catch (e) {
      // Silently fail - not critical
    }
  }

  /// Checks if auto-sync should run (last sync was > 1 hour ago).
  Future<bool> shouldAutoSync() async {
    final lastSync = await getLastSyncTime();
    if (lastSync == null) {
      return true; // Never synced, should sync
    }
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    return lastSync.isBefore(oneHourAgo);
  }

  /// Converts error to user-friendly message.
  String _getUserFriendlyError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network error. Please check your connection and try again.';
    }
    if (errorString.contains('cancelled')) {
      return 'Connection was cancelled.';
    }
    if (errorString.contains('permission') || errorString.contains('denied')) {
      return 'Permission denied. Please allow calendar access to continue.';
    }
    
    return 'An unexpected error occurred. Please try again.';
  }
}

/// Authenticated HTTP client for Google API calls.
class _AuthenticatedClient extends http.BaseClient {
  final http.Client _client;
  final auth.AccessToken _accessToken;

  _AuthenticatedClient(this._client, this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] = '${_accessToken.type} ${_accessToken.data}';
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}

/// Exception for calendar-related errors with user-friendly messages.
class CalendarException implements Exception {
  final String code;
  final String message;

  const CalendarException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'CalendarException($code): $message';
}

/// Runs [operation] with exponential backoff, retrying on transient
/// Google Calendar quota/availability errors (429 / 503 / rate / unavailable).
///
/// Delays: 1s, 2s, 4s (`500 * (1 << attempt)` ms for attempts 1..3).
/// Up to [maxAttempts] total calls (4 by default) — i.e. 1 initial call
/// plus 3 retries. Extracted as a top-level generic so the retry policy is
/// unit-testable without a live Calendar API.
Future<T> withBackoff<T>(
  Future<T> Function() operation, {
  int maxAttempts = 4,
}) async {
  int attempt = 0;
  while (true) {
    try {
      return await operation();
    } catch (e) {
      final s = e.toString().toLowerCase();
      final retriable = s.contains('429') ||
          s.contains('503') ||
          s.contains('rate') ||
          s.contains('unavailable');
      attempt++;
      if (!retriable || attempt >= maxAttempts) rethrow;
      await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
    }
  }
}
