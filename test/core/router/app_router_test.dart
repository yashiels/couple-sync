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

    test('stays on /auth to allow sign-out', () {
      expect(computeRedirect(noTimezoneState, AppRoutes.auth), isNull);
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

    test('redirects to /routine-setup from /home', () {
      expect(
        computeRedirect(noCoupleState, AppRoutes.home),
        AppRoutes.routineSetup,
      );
    });

    test('stays on /routine-setup', () {
      expect(computeRedirect(noCoupleState, AppRoutes.routineSetup), isNull);
    });

    test('stays on /pairing', () {
      expect(computeRedirect(noCoupleState, AppRoutes.pairing), isNull);
    });

    test('stays on /timezone-setup to allow going back', () {
      expect(computeRedirect(noCoupleState, AppRoutes.timezoneSetup), isNull);
    });

    test('stays on /auth to allow sign-out', () {
      expect(computeRedirect(noCoupleState, AppRoutes.auth), isNull);
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

  group('AuthStateListenable', () {
    test('hasListeners returns true by default', () {
      final authState = makeAuthState();
      final listenable = AuthStateListenable(authState);
      expect(listenable.hasListeners, isTrue);
    });

    test('can be constructed with loading state', () {
      final authState = makeAuthState(isLoading: true);
      expect(() => AuthStateListenable(authState), returnsNormally);
    });

    test('can be constructed with unauthenticated state', () {
      final authState = makeAuthState(isAuthenticated: false);
      expect(() => AuthStateListenable(authState), returnsNormally);
    });
  });
}
