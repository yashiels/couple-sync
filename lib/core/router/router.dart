import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/timezone_setup_screen.dart';
import '../../features/pairing/pairing_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/blocks/blocks_screen.dart';
import '../../features/blocks/block_form_screen.dart';
import '../../features/overlap/overlap_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/pairing_providers.dart';
import '../theme/app_theme.dart';

// ── Auth-aware refresh notifier ───────────────────────────────────────────────

/// A [ChangeNotifier] that listens to auth and hydration state changes via
/// [ProviderContainer] and notifies GoRouter to re-evaluate its redirect.
/// Created in [main] outside the widget tree to avoid Riverpod marking
/// ProviderScope dirty during its own mount.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(ProviderContainer container) {
    _authSub = container.listen<AsyncValue<User?>>(
      firebaseAuthStateProvider,
      (prev, next) => notifyListeners(),
    );
    _hydrationSub = container.listen<bool>(
      hydrationCompleteProvider,
      (prev, next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<User?>> _authSub;
  late final ProviderSubscription<bool> _hydrationSub;

  @override
  void dispose() {
    _authSub.close();
    _hydrationSub.close();
    super.dispose();
  }
}

// ── Router factory (created once in main) ─────────────────────────────────────

/// Creates the app's [GoRouter], reading provider state from [container].
/// Called from [main] before the widget tree mounts so that no provider
/// creation or state change can occur during ProviderScope's first build.
GoRouter createAppRouter(ProviderContainer container) {
  final refreshNotifier = _AuthChangeNotifier(container);

  return GoRouter(
    initialLocation: '/auth',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final loggedIn =
          container.read(firebaseAuthStateProvider).valueOrNull != null;
      final loc = state.matchedLocation;

      // Unauthenticated users can only visit /auth and /onboarding.
      const publicRoutes = {'/auth', '/onboarding'};
      if (!loggedIn) {
        return publicRoutes.contains(loc) ? null : '/auth';
      }

      // Wait for session hydration to complete before making routing
      // decisions.  While hydrating, keep the user on /auth (which shows
      // a loading indicator) so we don't flash wrong screens.
      final hydrated = container.read(hydrationCompleteProvider);
      if (!hydrated) {
        return null; // stay wherever we are until hydration completes
      }

      // Authenticated & hydrated — check onboarding completion.
      final user = container.read(currentUserProvider);
      final couple = container.read(currentCoupleProvider);

      // If on /auth after hydration, redirect into the onboarding
      // funnel or straight to home.
      if (loc == '/auth') {
        if (user == null) return '/auth'; // no user doc yet — stay
        final tz = user.timezone;
        if (tz.isEmpty || !tz.contains('/')) return '/timezone-setup';
        if (user.coupleId == null && couple == null) return '/pairing';
        return '/home';
      }

      // Allow onboarding/setup routes while logged in.
      const onboardingRoutes = {'/onboarding', '/timezone-setup', '/pairing'};
      if (onboardingRoutes.contains(loc)) return null;

      // Authenticated user on an authenticated route — allow.
      return null;
    },
    routes: [
      // Public routes (outside ShellRoute — no bottom nav)
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

      // Main app routes wrapped in ShellRoute with bottom navigation
      ShellRoute(
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
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
            path: '/overlap',
            name: 'overlap',
            builder: (context, state) => const OverlapScreen(),
          ),
        ],
      ),

      // Standalone routes (outside ShellRoute — no bottom nav)
      GoRoute(
        path: '/blocks',
        name: 'blocks',
        builder: (context, state) => const BlocksScreen(),
        routes: [
          GoRoute(
            path: 'add',
            name: 'blocks-add',
            builder: (context, state) => const BlockFormScreen(),
          ),
          GoRoute(
            path: 'edit/:id',
            name: 'blocks-edit',
            builder: (context, state) =>
                BlockFormScreen(editingBlockId: state.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

// ── Shell with bottom navigation ────────────────────────────────────────────

class _AppShell extends StatelessWidget {
  const _AppShell({required this.child});
  final Widget child;

  static const _tabs = ['/home', '/calendar', '/overlap'];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex =
        _tabs.indexWhere((t) => location.startsWith(t)).clamp(0, 2);

    return Scaffold(
      body: child,
      extendBody: true,
      bottomNavigationBar: _IOSTabBar(
        currentIndex: currentIndex,
        onTap: (i) => context.go(_tabs[i]),
      ),
    );
  }
}

/// Translucent frosted-glass tab bar mimicking iOS UITabBar.
class _IOSTabBar extends StatelessWidget {
  const _IOSTabBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xD9FFFFFF), // white at ~85% opacity
            border: Border(
              top: BorderSide(color: AppColors.separator, width: 0.33),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                children: [
                  _TabItem(
                    activeIcon: Icons.house_rounded,
                    inactiveIcon: Icons.house_outlined,
                    label: 'Home',
                    selected: currentIndex == 0,
                    onTap: () => onTap(0),
                  ),
                  _TabItem(
                    activeIcon: Icons.calendar_month,
                    inactiveIcon: Icons.calendar_month_outlined,
                    label: 'Calendar',
                    selected: currentIndex == 1,
                    onTap: () => onTap(1),
                  ),
                  _TabItem(
                    activeIcon: Icons.access_time_filled,
                    inactiveIcon: Icons.access_time,
                    label: 'Free Time',
                    selected: currentIndex == 2,
                    onTap: () => onTap(2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single tab item with outlined/filled icon toggle and always-visible label.
class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.onSurfaceMuted;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? activeIcon : inactiveIcon,
                size: 24,
                color: color,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: color,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
