import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'routes.dart';
import '../services/providers/auth_state_provider.dart';
import '../features/auth/screens/auth_screen.dart';
import '../features/onboarding/screens/timezone_setup_screen.dart';
import '../features/onboarding/screens/routine_setup_screen.dart';
import '../features/onboarding/screens/pairing_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/calendar/screens/calendar_screen.dart';
import '../features/blocks/screens/blocks_screen.dart';
import '../features/blocks/screens/block_form_screen.dart';
import '../features/overlap/screens/overlap_screen.dart';
import '../features/settings/screens/settings_screen.dart';

/// GoRouter configuration provider.
/// Exposes the router via Riverpod for use in app.dart.
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: true,
    
    // Redirect guards based on auth state
    redirect: (context, state) {
      final isLoading = authState.isLoading;
      final isAuthenticated = authState.isAuthenticated;
      final hasTimezone = authState.hasTimezone;
      final hasCouple = authState.hasCouple;
      final currentPath = state.matchedLocation;

      // While loading auth state, don't redirect
      if (isLoading) {
        return null;
      }

      // Guard 1: Not authenticated → redirect to /auth
      // Allow access to auth screen when not authenticated
      if (!isAuthenticated) {
        if (currentPath == AppRoutes.auth) {
          return null; // Stay on auth screen
        }
        return AppRoutes.auth;
      }

      // Guard 2: Authenticated but no timezone → redirect to /timezone-setup
      if (!hasTimezone) {
        if (currentPath == AppRoutes.timezoneSetup) {
          return null; // Stay on timezone setup
        }
        // Allow auth screen to show sign-out option
        if (currentPath == AppRoutes.auth) {
          return null;
        }
        return AppRoutes.timezoneSetup;
      }

      // Guard 3: Has timezone but no coupleId → redirect to /pairing
      if (!hasCouple) {
        if (currentPath == AppRoutes.pairing) {
          return null; // Stay on pairing screen
        }
        if (currentPath == AppRoutes.timezoneSetup) {
          return null; // Allow going back to timezone setup
        }
        if (currentPath == AppRoutes.auth) {
          return null; // Allow sign out
        }
        return AppRoutes.pairing;
      }

      // Guard 4: Has coupleId and navigating to /auth or /pairing → redirect to /home
      if (hasCouple) {
        if (currentPath == AppRoutes.auth || currentPath == AppRoutes.pairing) {
          return AppRoutes.home;
        }
      }

      // No redirect needed
      return null;
    },

    // Refresh router when auth state changes
    refreshListenable: AuthStateListenable(authState),

    routes: [
      // Authentication
      GoRoute(
        path: AppRoutes.auth,
        name: RouteNames.auth,
        builder: (context, state) => const AuthScreen(),
      ),

      // Onboarding
      GoRoute(
        path: AppRoutes.timezoneSetup,
        name: RouteNames.timezoneSetup,
        builder: (context, state) => const TimezoneSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.routineSetup,
        name: RouteNames.routineSetup,
        builder: (context, state) => const RoutineSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.pairing,
        name: RouteNames.pairing,
        builder: (context, state) => const PairingScreen(),
      ),

      // Main App
      GoRoute(
        path: AppRoutes.home,
        name: RouteNames.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        name: RouteNames.calendar,
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: AppRoutes.blocks,
        name: RouteNames.blocks,
        builder: (context, state) => const BlocksScreen(),
      ),
      GoRoute(
        path: AppRoutes.blockForm,
        name: RouteNames.blockForm,
        builder: (context, state) {
          final args = state.extra as BlockFormArgs?;
          return BlockFormScreen(args: args);
        },
      ),
      GoRoute(
        path: AppRoutes.overlap,
        name: RouteNames.overlap,
        builder: (context, state) => const OverlapScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: RouteNames.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],

    // Error handling
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              Text(
                'Page Not Found',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'The page "${state.matchedLocation}" does not exist.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go(AppRoutes.home),
                icon: const Icon(Icons.home),
                label: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

/// Listenable that notifies when auth state changes.
/// Used by GoRouter to refresh routes on auth changes.
class AuthStateListenable extends ChangeNotifier {
  final AuthState _authState;
  
  AuthStateListenable(this._authState) {
    // Notify listeners when auth state changes
    // The router will re-evaluate redirects on change
  }

  /// Always return true to trigger refresh on every rebuild.
  /// The redirect logic handles the actual state checking.
  @override
  bool get hasListeners => true;
}
