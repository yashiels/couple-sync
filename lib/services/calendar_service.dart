import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;

/// Service for handling Google Calendar OAuth and API operations.
/// Manages secure token storage and calendar access with calendar.readonly scope.
class CalendarService {
  static const String _accessTokenKey = 'google_calendar_access_token';
  static const String _refreshTokenKey = 'google_calendar_refresh_token';
  static const String _tokenExpiryKey = 'google_calendar_token_expiry';
  static const List<String> _calendarScopes = [
    'https://www.googleapis.com/auth/calendar.readonly',
  ];

  final GoogleSignIn _googleSignIn;
  final FlutterSecureStorage _secureStorage;

  CalendarService({
    GoogleSignIn? googleSignIn,
    FlutterSecureStorage? secureStorage,
  })  : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: _calendarScopes),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Stream of calendar connection state changes.
  Stream<bool> get connectionStateChanges async* {
    yield await isConnected;
    await for (final _ in Stream.periodic(const Duration(seconds: 1))) {
      yield await isConnected;
    }
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
        DateTime.now().add(const Duration(hours: 1)),
      ),
    );

    return calendar.CalendarApi(httpClient);
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
