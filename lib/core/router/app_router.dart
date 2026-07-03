import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'main_shell.dart';
import 'routes.dart';
import '../../services/providers/auth_state_provider.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/onboarding/screens/timezone_setup_screen.dart';
import '../../features/onboarding/screens/pairing_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/calendar/screens/calendar_screen.dart';
import '../../features/blocks/screens/block_management_screen.dart';
import '../../features/blocks/screens/block_form_screen.dart';
import '../../features/overlap/screens/overlap_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

/// Pure redirect logic extracted for testability.
///
/// [currentPath] is the matched route path (no query string).
/// [queryParams] are the query parameters for the current navigation state.
///
/// Returns the path to redirect to, or null if no redirect is needed.
String? computeRedirect(
  AuthState authState,
  String currentPath, {
  Map<String, String> queryParams = const {},
}) {
  // While loading auth state, don't redirect
  if (authState.isLoading) {
    return null;
  }

  // Guard 1: Not authenticated → redirect to /auth
  // Allow access to auth screen when not authenticated.
  // Also allow /invite/* to pass through so the route-level redirect can
  // forward to /pairing; the auth guard there will fire on subsequent navigation.
  if (!authState.isAuthenticated) {
    if (currentPath == AppRoutes.auth) {
      return null; // Stay on auth screen
    }
    if (currentPath.startsWith(AppRoutes.inviteBase)) {
      return null; // Let the GoRoute redirect handle the invite path
    }
    // If the destination is /pairing with an invite code, preserve the code
    // through auth so the user lands on a pre-filled EnterCodeTab after sign-in.
    if (currentPath == AppRoutes.pairing) {
      final code = queryParams['code'];
      if (code != null && code.isNotEmpty) {
        return '${AppRoutes.auth}?pendingInvite=${Uri.encodeComponent(code)}';
      }
    }
    return AppRoutes.auth;
  }

  // Guard 1b: Authenticated and on /auth with a pendingInvite → consume it
  // This fires after sign-in when the router re-evaluates redirects.
  if (currentPath == AppRoutes.auth) {
    final code = queryParams['pendingInvite'];
    if (code != null && code.isNotEmpty) {
      return '${AppRoutes.pairing}?code=${Uri.encodeComponent(code)}';
    }
  }

  // Guard 2: Authenticated but no timezone → redirect to /timezone-setup
  if (!authState.hasTimezone) {
    if (currentPath == AppRoutes.timezoneSetup) {
      return null; // Stay on timezone setup
    }
    return AppRoutes.timezoneSetup;
  }

  // Guard 3: Has timezone but no coupleId → redirect to /pairing
  // Note: the timezoneSetup carve-out was removed — if hasTimezone is true,
  // Guard 2 never fires, so reaching here means timezone is done. Allowing
  // the user to revisit /timezone-setup from this state was dead and misleading.
  if (!authState.hasCouple) {
    if (currentPath == AppRoutes.pairing) {
      return null; // Stay on pairing screen
    }
    return AppRoutes.pairing;
  }

  // Guard 4: Has coupleId → redirect away from /auth or /pairing to /home.
  // The outer hasCouple check is omitted: reaching here proves hasCouple is
  // true (Guard 3 above would have redirected otherwise).
  if (currentPath == AppRoutes.auth || currentPath == AppRoutes.pairing) {
    return AppRoutes.home;
  }

  // No redirect needed
  return null;
}

/// GoRouter configuration provider.
/// Exposes the router via Riverpod for use in app.dart.
final routerProvider = Provider<GoRouter>((ref) {
  // Use a listenable that bridges Riverpod state changes to GoRouter refreshes.
  final refreshNotifier = RouterRefreshNotifier();

  // Dispose the notifier when this provider is disposed (e.g. hot-restart) so
  // listeners registered via ChangeNotifier are cleaned up and don't leak.
  ref.onDispose(refreshNotifier.dispose);

  // Eagerly read to ensure the provider is initialized and the auth listener starts.
  ref.read(authStateProvider);

  // Listen to auth state changes and notify the router to re-evaluate redirects.
  ref.listen<AuthState>(authStateProvider, (prev, next) {
    refreshNotifier.notify();
  });

  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: true,

    // Redirect guards based on auth state — reads current state at redirect time
    redirect: (context, state) {
      // Access the container's current auth state directly
      final authState = ref.read(authStateProvider);
      return computeRedirect(
        authState,
        state.matchedLocation,
        queryParams: state.uri.queryParameters,
      );
    },

    // Refresh router when auth state changes
    refreshListenable: refreshNotifier,

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
        path: AppRoutes.pairing,
        name: RouteNames.pairing,
        builder: (context, state) => PairingScreen(
          // Pass invite code from query parameter so EnterCodeTab is pre-filled
          // when the user arrives via a deep link (e.g. /invite/:code flow).
          initialCode: state.uri.queryParameters['code'],
        ),
      ),

      // Universal Link / App Link handler
      // iOS: https://coupleschedule.app/invite/<code>  (Associated Domains)
      // Android: https://coupleschedule.app/invite/<code>  (App Links / autoVerify)
      // go_router matches this path when the OS hands the HTTPS URL to the app.
      // Unauthenticated users are redirected to /auth by computeRedirect; the
      // code is passed through so the pairing screen can pre-fill it.
      GoRoute(
        path: '${AppRoutes.inviteBase}/:code',
        name: RouteNames.invite,
        redirect: (context, state) {
          final code = state.pathParameters['code'] ?? '';
          // Hand off to /pairing with the invite code as a query parameter so
          // EnterCodeTab can auto-populate the field.
          return '${AppRoutes.pairing}?code=${Uri.encodeComponent(code)}';
        },
      ),

      // Main App — wrapped in bottom navigation shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          // Tab 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: RouteNames.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Tab 1: Calendar
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.calendar,
                name: RouteNames.calendar,
                builder: (context, state) => const CalendarScreen(),
              ),
            ],
          ),
          // Tab 2: Overlap
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.overlap,
                name: RouteNames.overlap,
                builder: (context, state) => const OverlapScreen(),
              ),
            ],
          ),
          // Tab 3: Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                name: RouteNames.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // Standalone routes (pushed on top of shell)
      GoRoute(
        path: AppRoutes.blocks,
        name: RouteNames.blocks,
        builder: (context, state) => const BlockManagementScreen(),
      ),
      GoRoute(
        path: AppRoutes.blockForm,
        name: RouteNames.blockForm,
        builder: (context, state) {
          final args = state.extra as BlockFormArgs?;
          return BlockFormScreen(args: args);
        },
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
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
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

/// Bridges Riverpod state changes to GoRouter's refreshListenable.
/// Call [notify] whenever the router should re-evaluate its redirects.
class RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
