import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/timezone_setup_screen.dart';
import '../../features/pairing/pairing_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/blocks/blocks_screen.dart';
import '../../features/overlap/overlap_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../shared/providers/auth_providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(firebaseAuthStateProvider);
  final isLoggedIn = authState.valueOrNull != null;

  return GoRouter(
    initialLocation: isLoggedIn ? '/home' : '/auth',
    redirect: (context, state) {
      final loggedIn = authState.valueOrNull != null;
      final onPublicRoute = state.matchedLocation == '/auth' ||
          state.matchedLocation == '/onboarding' ||
          state.matchedLocation == '/timezone-setup';

      if (!loggedIn && !onPublicRoute) return '/auth';
      if (loggedIn && state.matchedLocation == '/auth') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        name: 'auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/timezone-setup',
        name: 'timezone-setup',
        builder: (context, state) => const TimezoneSetupScreen(),
      ),
      GoRoute(
        path: '/pairing',
        name: 'pairing',
        builder: (context, state) => const PairingScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/calendar',
        name: 'calendar',
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: '/blocks',
        name: 'blocks',
        builder: (context, state) => const BlocksScreen(),
      ),
      GoRoute(
        path: '/overlap',
        name: 'overlap',
        builder: (context, state) => const OverlapScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
