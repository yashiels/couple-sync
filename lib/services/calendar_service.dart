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
  static const String _refreshTokenKey = 'google_calendar_refresh_token';
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
      // Sign out first to force fresh OAuth consent with calendar scope
      await _googleSignIn.signOut();

      // Trigger the Google Sign-In flow with calendar scope
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
      await _secureStorage.delete(key: _refreshTokenKey);
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
        // Silent sign-in failed, need user interaction
        await disconnect();
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

  /// Gets the Google Calendar API client.
  /// Returns null if not connected or token refresh failed.
  Future<calendar.CalendarApi?> getCalendarApi() async {
    final accessToken = await getAccessToken();
    if (accessToken == null) {
      return null;
    }

    // Create an authenticated HTTP client
    final httpClient = _AuthenticatedClient(
      http.Client(),
      auth.AccessToken(
        'Bearer',
        accessToken,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
    );

    return calendar.CalendarApi(httpClient);
  }

  /// Fetches freebusy intervals from Google Calendar for the next 14 days.
  /// Returns a list of busy time intervals (start and end times in UTC).
  /// Privacy-first: NEVER fetches or stores event titles.
  Future<List<({DateTime start, DateTime end})>> fetchFreebusy() async {
    try {
      final calendarApi = await getCalendarApi();
      if (calendarApi == null) {
        throw const CalendarException(
          code: 'not-connected',
          message: 'Google Calendar is not connected. Please connect first.',
        );
      }

      // Calculate time range: now to 14 days ahead
      final now = DateTime.now().toUtc();
      final timeMax = now.add(const Duration(days: 14));

      // Build freebusy request
      final request = calendar.FreeBusyRequest(
        timeMin: now,
        timeMax: timeMax,
        items: [
          calendar.FreeBusyRequestItem(
            id: 'primary', // Use primary calendar
          ),
        ],
      );

      // Execute freebusy query
      final response = await calendarApi.freebusy.query(request);

      // Extract busy intervals from response
      final busyIntervals = <({DateTime start, DateTime end})>[];

      final calendars = response.calendars;
      if (calendars != null) {
        final primaryCalendar = calendars['primary'];
        if (primaryCalendar != null) {
          final busy = primaryCalendar.busy;
          if (busy != null) {
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
      }

      return busyIntervals;
    } on CalendarException {
      rethrow;
    } catch (e) {
      throw CalendarException(
        code: 'freebusy-failed',
        message: 'Failed to fetch calendar availability: ${_getUserFriendlyError(e)}',
      );
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
