import 'package:flutter_test/flutter_test.dart';

/// Unit tests for router redirect logic.
///
/// These test the decision matrix in isolation (without GoRouter or Riverpod)
/// by extracting the redirect logic into a pure function.
///
/// The actual router uses Riverpod providers; these tests verify the
/// logical branches are correct.

// Extracted redirect logic (mirrors router.dart redirect callback)
String? computeRedirect({
  required bool loggedIn,
  required bool hydrated,
  required String location,
  required String? userTimezone,
  required String? coupleId,
  required bool hasCoupleInState,
}) {
  const publicRoutes = {'/auth', '/onboarding'};

  // Unauthenticated
  if (!loggedIn) {
    return publicRoutes.contains(location) ? null : '/auth';
  }

  // Authenticated but not hydrated
  if (!hydrated) {
    return null; // stay put, don't flash wrong screen
  }

  // Authenticated & hydrated, coming from /auth
  if (location == '/auth') {
    if (userTimezone == null) return '/auth'; // no user doc
    if (userTimezone.isEmpty || !userTimezone.contains('/')) {
      return '/timezone-setup';
    }
    if (coupleId == null && !hasCoupleInState) return '/pairing';
    return '/home';
  }

  // Onboarding routes — allow
  const onboardingRoutes = {'/onboarding', '/timezone-setup', '/pairing'};
  if (onboardingRoutes.contains(location)) return null;

  // Authenticated route — allow
  return null;
}

void main() {
  group('Router redirect logic', () {
    test('unauthenticated user on /auth stays', () {
      expect(
        computeRedirect(
          loggedIn: false,
          hydrated: false,
          location: '/auth',
          userTimezone: null,
          coupleId: null,
          hasCoupleInState: false,
        ),
        isNull,
      );
    });

    test('unauthenticated user on /home redirects to /auth', () {
      expect(
        computeRedirect(
          loggedIn: false,
          hydrated: false,
          location: '/home',
          userTimezone: null,
          coupleId: null,
          hasCoupleInState: false,
        ),
        '/auth',
      );
    });

    test('authenticated but not hydrated stays on current route', () {
      expect(
        computeRedirect(
          loggedIn: true,
          hydrated: false,
          location: '/auth',
          userTimezone: null,
          coupleId: null,
          hasCoupleInState: false,
        ),
        isNull,
      );
    });

    test('hydrated user without timezone redirects to /timezone-setup', () {
      expect(
        computeRedirect(
          loggedIn: true,
          hydrated: true,
          location: '/auth',
          userTimezone: '',
          coupleId: null,
          hasCoupleInState: false,
        ),
        '/timezone-setup',
      );
    });

    test('hydrated user with bad timezone (no slash) redirects to /timezone-setup', () {
      expect(
        computeRedirect(
          loggedIn: true,
          hydrated: true,
          location: '/auth',
          userTimezone: 'UTC',
          coupleId: null,
          hasCoupleInState: false,
        ),
        '/timezone-setup',
      );
    });

    test('hydrated user with timezone but no couple redirects to /pairing', () {
      expect(
        computeRedirect(
          loggedIn: true,
          hydrated: true,
          location: '/auth',
          userTimezone: 'America/New_York',
          coupleId: null,
          hasCoupleInState: false,
        ),
        '/pairing',
      );
    });

    test('fully setup user redirects from /auth to /home', () {
      expect(
        computeRedirect(
          loggedIn: true,
          hydrated: true,
          location: '/auth',
          userTimezone: 'America/New_York',
          coupleId: 'couple123',
          hasCoupleInState: true,
        ),
        '/home',
      );
    });

    test('authenticated user on /home is allowed', () {
      expect(
        computeRedirect(
          loggedIn: true,
          hydrated: true,
          location: '/home',
          userTimezone: 'America/New_York',
          coupleId: 'couple123',
          hasCoupleInState: true,
        ),
        isNull,
      );
    });

    test('authenticated user on /timezone-setup is allowed', () {
      expect(
        computeRedirect(
          loggedIn: true,
          hydrated: true,
          location: '/timezone-setup',
          userTimezone: '',
          coupleId: null,
          hasCoupleInState: false,
        ),
        isNull,
      );
    });

    test('authenticated user on /calendar is allowed', () {
      expect(
        computeRedirect(
          loggedIn: true,
          hydrated: true,
          location: '/calendar',
          userTimezone: 'Europe/London',
          coupleId: 'couple456',
          hasCoupleInState: true,
        ),
        isNull,
      );
    });

    test('user with couple in state but no coupleId on user goes to /home', () {
      expect(
        computeRedirect(
          loggedIn: true,
          hydrated: true,
          location: '/auth',
          userTimezone: 'Africa/Johannesburg',
          coupleId: null,
          hasCoupleInState: true,
        ),
        '/home',
      );
    });
  });
}
