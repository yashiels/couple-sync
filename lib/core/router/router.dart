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

/// A [ChangeNotifier] that listens to [firebaseAuthStateProvider] and notifies
/// GoRouter to re-evaluate its redirect whenever the auth state changes.
/// This avoids recreating the entire [GoRouter] on every auth event.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    _sub = ref.listen<AsyncValue<User?>>(firebaseAuthStateProvider, (_, _) {
      notifyListeners();
    });
  }

  late final ProviderSubscription<AsyncValue<User?>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

// ── Router provider (created once) ────────────────────────────────────────────

/// The app's [GoRouter] instance, created once and kept alive for the lifetime
/// of the app.  Auth/onboarding state changes trigger a redirect re-evaluation
/// through [GoRouter.refreshListenable] rather than rebuilding the router.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthChangeNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/auth',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final loggedIn =
          ref.read(firebaseAuthStateProvider).valueOrNull != null;
      final loc = state.matchedLocation;

      // Unauthenticated users can only visit /auth and /onboarding.
      const publicRoutes = {'/auth', '/onboarding'};
      if (!loggedIn) {
        return publicRoutes.contains(loc) ? null : '/auth';
      }

      // Authenticated — check onboarding completion.
      final user = ref.read(currentUserProvider);
      final couple = ref.read(currentCoupleProvider);

      // If coming from /auth, redirect into the onboarding funnel or home.
      if (loc == '/auth') {
        if (user == null) return '/home'; // still hydrating — let it settle
        final tz = user.timezone;
        if (tz.isEmpty || !tz.contains('/')) return '/timezone-setup';
        if (user.coupleId == null && couple == null) return '/pairing';
        return '/home';
      }

      // Allow onboarding/setup routes while logged in.
      const onboardingRoutes = {'/onboarding', '/timezone-setup', '/pairing'};
      if (onboardingRoutes.contains(loc)) return null;

      // Already on an authenticated route — allow.
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
});

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
