import 'package:couple_sync/services/calendar_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([
  GoogleSignIn,
  GoogleSignInAccount,
  GoogleSignInAuthentication,
])
import 'calendar_service_test.mocks.dart';

/// In-memory fake for FlutterSecureStorage to avoid complex mock parameter matching.
class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  bool shouldThrow = false;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('storage error');
    return _store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('storage error');
    if (value != null) _store[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (shouldThrow) throw Exception('storage error');
    _store.remove(key);
  }
}

void main() {
  late MockGoogleSignIn mockGoogleSignIn;
  late FakeSecureStorage fakeSecureStorage;
  late CalendarService calendarService;

  setUp(() {
    mockGoogleSignIn = MockGoogleSignIn();
    fakeSecureStorage = FakeSecureStorage();

    calendarService = CalendarService(
      googleSignIn: mockGoogleSignIn,
      secureStorage: fakeSecureStorage,
    );
  });

  group('CalendarService', () {
    group('isConnected', () {
      test('returns true when access token exists', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'some-token';

        expect(await calendarService.isConnected, isTrue);
      });

      test('returns false when access token is null', () async {
        expect(await calendarService.isConnected, isFalse);
      });

      test('returns false when access token is empty', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = '';

        expect(await calendarService.isConnected, isFalse);
      });
    });

    group('connect', () {
      test('connects successfully and stores tokens', () async {
        final mockAccount = MockGoogleSignInAccount();
        final mockAuth = MockGoogleSignInAuthentication();

        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
        when(mockGoogleSignIn.signIn())
            .thenAnswer((_) async => mockAccount);
        when(mockAccount.authentication)
            .thenAnswer((_) async => mockAuth);
        when(mockAuth.accessToken).thenReturn('test-access-token');

        final result = await calendarService.connect();

        expect(result, isTrue);
        verify(mockGoogleSignIn.signOut()).called(1);
        verify(mockGoogleSignIn.signIn()).called(1);
        expect(
          fakeSecureStorage._store['google_calendar_access_token'],
          'test-access-token',
        );
        expect(
          fakeSecureStorage._store['google_calendar_token_expiry'],
          isNotNull,
        );
      });

      test('throws CalendarException when user cancels sign-in', () async {
        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
        when(mockGoogleSignIn.signIn()).thenAnswer((_) async => null);

        expect(
          () => calendarService.connect(),
          throwsA(isA<CalendarException>().having(
            (e) => e.code,
            'code',
            'sign-in-cancelled',
          )),
        );
      });

      test('throws CalendarException when access token is null', () async {
        final mockAccount = MockGoogleSignInAccount();
        final mockAuth = MockGoogleSignInAuthentication();

        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
        when(mockGoogleSignIn.signIn())
            .thenAnswer((_) async => mockAccount);
        when(mockAccount.authentication)
            .thenAnswer((_) async => mockAuth);
        when(mockAuth.accessToken).thenReturn(null);

        expect(
          () => calendarService.connect(),
          throwsA(isA<CalendarException>().having(
            (e) => e.code,
            'code',
            'no-access-token',
          )),
        );
      });

      test('throws CalendarException with network error message', () async {
        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
        when(mockGoogleSignIn.signIn())
            .thenThrow(Exception('network error occurred'));

        expect(
          () => calendarService.connect(),
          throwsA(isA<CalendarException>().having(
            (e) => e.code,
            'code',
            'connection-failed',
          ).having(
            (e) => e.message,
            'message',
            contains('Network error'),
          )),
        );
      });

      test('throws CalendarException with cancelled error message', () async {
        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
        when(mockGoogleSignIn.signIn())
            .thenThrow(Exception('user cancelled'));

        expect(
          () => calendarService.connect(),
          throwsA(isA<CalendarException>().having(
            (e) => e.message,
            'message',
            contains('cancelled'),
          )),
        );
      });

      test('throws CalendarException with permission error message', () async {
        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
        when(mockGoogleSignIn.signIn())
            .thenThrow(Exception('permission denied'));

        expect(
          () => calendarService.connect(),
          throwsA(isA<CalendarException>().having(
            (e) => e.message,
            'message',
            contains('Permission denied'),
          )),
        );
      });

      test('throws CalendarException with generic error for unknown errors',
          () async {
        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
        when(mockGoogleSignIn.signIn())
            .thenThrow(Exception('something weird'));

        expect(
          () => calendarService.connect(),
          throwsA(isA<CalendarException>().having(
            (e) => e.message,
            'message',
            contains('unexpected error'),
          )),
        );
      });
    });

    group('disconnect', () {
      test('clears tokens and signs out', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'token';
        fakeSecureStorage._store['google_calendar_refresh_token'] = 'refresh';
        fakeSecureStorage._store['google_calendar_token_expiry'] = 'expiry';

        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);

        await calendarService.disconnect();

        expect(fakeSecureStorage._store, isEmpty);
        verify(mockGoogleSignIn.signOut()).called(1);
      });

      test('throws CalendarException on storage failure', () async {
        fakeSecureStorage.shouldThrow = true;

        expect(
          () => calendarService.disconnect(),
          throwsA(isA<CalendarException>().having(
            (e) => e.code,
            'code',
            'disconnect-failed',
          )),
        );
      });

      test('throws CalendarException on signOut failure', () async {
        when(mockGoogleSignIn.signOut()).thenThrow(Exception('sign out error'));

        // Storage deletes succeed but signOut throws, which still produces disconnect-failed
        // Actually, delete runs first. If signOut throws, the catch wraps it.
        // But delete succeeds (shouldThrow is false), so we get to signOut.
        expect(
          () => calendarService.disconnect(),
          throwsA(isA<CalendarException>().having(
            (e) => e.code,
            'code',
            'disconnect-failed',
          )),
        );
      });
    });

    group('getAccessToken', () {
      test('returns null when no token stored', () async {
        expect(await calendarService.getAccessToken(), isNull);
      });

      test('returns null when token is empty', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = '';

        expect(await calendarService.getAccessToken(), isNull);
      });

      test('returns token when not expired', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'valid-token';
        fakeSecureStorage._store['google_calendar_token_expiry'] =
            DateTime.now().add(const Duration(hours: 1)).toIso8601String();

        expect(await calendarService.getAccessToken(), 'valid-token');
      });

      test('returns token when no expiry stored', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'valid-token';

        expect(await calendarService.getAccessToken(), 'valid-token');
      });

      test('refreshes token when expired and returns new token', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'expired-token';
        fakeSecureStorage._store['google_calendar_token_expiry'] =
            DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();

        // Mock successful silent sign-in for refresh
        final mockAccount = MockGoogleSignInAccount();
        final mockAuth = MockGoogleSignInAuthentication();
        when(mockGoogleSignIn.signInSilently())
            .thenAnswer((_) async => mockAccount);
        when(mockAccount.authentication)
            .thenAnswer((_) async => mockAuth);
        when(mockAuth.accessToken).thenReturn('refreshed-token');

        final result = await calendarService.getAccessToken();

        // After refresh, the stored token is updated
        expect(result, 'refreshed-token');
        expect(
          fakeSecureStorage._store['google_calendar_access_token'],
          'refreshed-token',
        );
        verify(mockGoogleSignIn.signInSilently()).called(1);
      });

      test('returns null when token expired and silent sign-in fails', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'expired-token';
        fakeSecureStorage._store['google_calendar_token_expiry'] =
            DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();

        // Silent sign-in returns null
        when(mockGoogleSignIn.signInSilently())
            .thenAnswer((_) async => null);
        // disconnect is called internally, which needs signOut
        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);

        expect(await calendarService.getAccessToken(), isNull);
      });

      test('returns null when token expired and refresh has null access token',
          () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'expired-token';
        fakeSecureStorage._store['google_calendar_token_expiry'] =
            DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();

        final mockAccount = MockGoogleSignInAccount();
        final mockAuth = MockGoogleSignInAuthentication();
        when(mockGoogleSignIn.signInSilently())
            .thenAnswer((_) async => mockAccount);
        when(mockAccount.authentication)
            .thenAnswer((_) async => mockAuth);
        when(mockAuth.accessToken).thenReturn(null);

        expect(await calendarService.getAccessToken(), isNull);
      });

      test('returns null when refresh throws exception', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'expired-token';
        fakeSecureStorage._store['google_calendar_token_expiry'] =
            DateTime.now().subtract(const Duration(hours: 1)).toIso8601String();

        when(mockGoogleSignIn.signInSilently())
            .thenThrow(Exception('refresh error'));

        expect(await calendarService.getAccessToken(), isNull);
      });

      test('returns null on storage read exception', () async {
        fakeSecureStorage.shouldThrow = true;

        expect(await calendarService.getAccessToken(), isNull);
      });
    });

    group('getCalendarApi', () {
      test('returns null when not connected', () async {
        expect(await calendarService.getCalendarApi(), isNull);
      });

      test('returns CalendarApi when connected with valid token', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'valid-token';
        fakeSecureStorage._store['google_calendar_token_expiry'] =
            DateTime.now().add(const Duration(hours: 1)).toIso8601String();

        final api = await calendarService.getCalendarApi();

        expect(api, isNotNull);
      });
    });

    group('connectionStateChanges', () {
      test('emits true when connected', () async {
        fakeSecureStorage._store['google_calendar_access_token'] = 'some-token';

        final first = await calendarService.connectionStateChanges.first;

        expect(first, isTrue);
      });

      test('emits false when not connected', () async {
        final first = await calendarService.connectionStateChanges.first;

        expect(first, isFalse);
      });
    });

    group('CalendarException', () {
      test('stores code and message', () {
        const e = CalendarException(code: 'test-code', message: 'Test message');
        expect(e.code, 'test-code');
        expect(e.message, 'Test message');
      });

      test('toString includes code and message', () {
        const e = CalendarException(code: 'test-code', message: 'Test message');
        expect(e.toString(), 'CalendarException(test-code): Test message');
      });
    });
  });
}
