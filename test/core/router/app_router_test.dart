import 'package:couple_sync/core/router/app_router.dart';
import 'package:couple_sync/core/router/routes.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an [AuthState] with the given flags. Defaults to fully-loaded,
/// authenticated, with timezone, and paired.
AuthState makeAuthState({
  bool isLoading = false,
  bool isAuthenticated = true,
  bool hasTimezone = true,
  bool hasCouple = true,
}) {
  // AuthState derives booleans from firebaseUser / userProfile, so we drive
  // it through the copyWith/internal path instead of subclassing. Because
  // the class exposes those booleans only via getters that check real objects,
  // we use a thin test subclass below.
  return _TestAuthState(
    loading: isLoading,
    authenticated: isAuthenticated,
    timezone: hasTimezone,
    couple: hasCouple,
  );
}

/// Test-only subclass that overrides the computed boolean getters, allowing
/// tests to specify desired state without constructing Firebase objects.
class _TestAuthState extends AuthState {
  final bool _isAuthenticated;
  final bool _hasTimezone;
  final bool _hasCouple;

  const _TestAuthState({
    required bool loading,
    required bool authenticated,
    required bool timezone,
    required bool couple,
  })  : _isAuthenticated = authenticated,
        _hasTimezone = timezone,
        _hasCouple = couple,
        super(isLoading: loading);

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  bool get hasTimezone => _hasTimezone;

  @override
  bool get hasCouple => _hasCouple;
}

void main() {
  group('computeRedirect — loading state', () {
    test('returns null while auth is loading', () {
      final state = makeAuthState(isLoading: true, isAuthenticated: false);
      expect(computeRedirect(state, AppRoutes.home), isNull);
    });

    test('returns null even on non-existent path while loading', () {
      final state = makeAuthState(isLoading: true, isAuthenticated: false);
      expect(computeRedirect(state, '/some-deep-path'), isNull);
    });
  });

  group('computeRedirect — unauthenticated', () {
    late AuthState unauthState;

    setUp(() {
      unauthState = makeAuthState(
        isAuthenticated: false,
        hasTimezone: false,
        hasCouple: false,
      );
    });

    test('redirects to /auth from /home', () {
      expect(computeRedirect(unauthState, AppRoutes.home), AppRoutes.auth);
    });

    test('redirects to /auth from /settings', () {
      expect(computeRedirect(unauthState, AppRoutes.settings), AppRoutes.auth);
    });

    test('stays on /auth when already there', () {
      expect(computeRedirect(unauthState, AppRoutes.auth), isNull);
    });

    test('preserves invite code — redirects /pairing?code=ABC123 to /auth?pendingInvite=ABC123', () {
      final result = computeRedirect(
        unauthState,
        AppRoutes.pairing,
        queryParams: const {'code': 'ABC123'},
      );
      expect(result, '/auth?pendingInvite=ABC123');
    });

    test('redirects /pairing without code to plain /auth', () {
      expect(computeRedirect(unauthState, AppRoutes.pairing), AppRoutes.auth);
    });

    test('URI-encodes special characters in invite code', () {
      final result = computeRedirect(
        unauthState,
        AppRoutes.pairing,
        queryParams: const {'code': 'AB C12'},
      );
      expect(result, '/auth?pendingInvite=AB%20C12');
    });
  });

  group('computeRedirect — authenticated, consuming pendingInvite', () {
    late AuthState authNoTimezoneState;

    setUp(() {
      // Authenticated but timezone not yet set (first-time user after sign-in
      // via deep link). Guard 1b fires before Guard 2 so the pending invite is
      // consumed and the user is sent to /pairing with the code.
      authNoTimezoneState = makeAuthState(
        isAuthenticated: true,
        hasTimezone: false,
        hasCouple: false,
      );
    });

    test('redirects /auth?pendingInvite=ABC123 to /pairing?code=ABC123', () {
      final result = computeRedirect(
        authNoTimezoneState,
        AppRoutes.auth,
        queryParams: const {'pendingInvite': 'ABC123'},
      );
      expect(result, '/pairing?code=ABC123');
    });

    test('does not redirect /auth without pendingInvite (goes to timezone-setup instead)', () {
      // No pendingInvite — Guard 1b is skipped, Guard 2 fires
      final result = computeRedirect(authNoTimezoneState, AppRoutes.auth);
      expect(result, AppRoutes.timezoneSetup);
    });

    test('URI-encodes the code when building the redirect URL', () {
      // GoRouter decodes query param values before handing them to redirects,
      // so spaces arrive as spaces; we must re-encode when building the URL.
      final result = computeRedirect(
        authNoTimezoneState,
        AppRoutes.auth,
        queryParams: const {'pendingInvite': 'AB C12'},
      );
      expect(result, '/pairing?code=AB%20C12');
    });
  });

  group('computeRedirect — authenticated but no timezone', () {
    late AuthState noTimezoneState;

    setUp(() {
      noTimezoneState = makeAuthState(
        isAuthenticated: true,
        hasTimezone: false,
        hasCouple: false,
      );
    });

    test('redirects to /timezone-setup from /home', () {
      expect(
        computeRedirect(noTimezoneState, AppRoutes.home),
        AppRoutes.timezoneSetup,
      );
    });

    test('stays on /timezone-setup when already there', () {
      expect(computeRedirect(noTimezoneState, AppRoutes.timezoneSetup), isNull);
    });

    test('redirects /auth to /timezone-setup', () {
      expect(computeRedirect(noTimezoneState, AppRoutes.auth), AppRoutes.timezoneSetup);
    });

    test('redirects to /timezone-setup from /settings', () {
      expect(
        computeRedirect(noTimezoneState, AppRoutes.settings),
        AppRoutes.timezoneSetup,
      );
    });
  });

  group('computeRedirect — authenticated with timezone but no coupleId', () {
    late AuthState noCoupleState;

    setUp(() {
      noCoupleState = makeAuthState(
        isAuthenticated: true,
        hasTimezone: true,
        hasCouple: false,
      );
    });

    test('redirects to /pairing from /home', () {
      expect(
        computeRedirect(noCoupleState, AppRoutes.home),
        AppRoutes.pairing,
      );
    });

    test('stays on /pairing', () {
      expect(computeRedirect(noCoupleState, AppRoutes.pairing), isNull);
    });

    test('stays on /timezone-setup to allow going back', () {
      expect(computeRedirect(noCoupleState, AppRoutes.timezoneSetup), isNull);
    });

    test('redirects /auth to /pairing', () {
      expect(computeRedirect(noCoupleState, AppRoutes.auth), AppRoutes.pairing);
    });
  });

  group('computeRedirect — fully onboarded user', () {
    late AuthState fullState;

    setUp(() {
      fullState = makeAuthState(
        isAuthenticated: true,
        hasTimezone: true,
        hasCouple: true,
      );
    });

    test('no redirect from /home', () {
      expect(computeRedirect(fullState, AppRoutes.home), isNull);
    });

    test('no redirect from /settings', () {
      expect(computeRedirect(fullState, AppRoutes.settings), isNull);
    });

    test('no redirect from /calendar', () {
      expect(computeRedirect(fullState, AppRoutes.calendar), isNull);
    });

    test('redirects /auth to /home to prevent going back to login', () {
      expect(computeRedirect(fullState, AppRoutes.auth), AppRoutes.home);
    });

    test('redirects /pairing to /home when already paired', () {
      expect(computeRedirect(fullState, AppRoutes.pairing), AppRoutes.home);
    });
  });

  group('RouterRefreshNotifier', () {
    test('notify triggers listeners', () {
      final notifier = RouterRefreshNotifier();
      var notified = false;
      notifier.addListener(() => notified = true);
      notifier.notify();
      expect(notified, isTrue);
    });

    test('can be constructed', () {
      expect(() => RouterRefreshNotifier(), returnsNormally);
    });
  });
}
