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
import '../theme/app_theme.dart';

/// The app's [GoRouter] instance, rebuilt whenever the auth state changes.
///
/// Unauthenticated users are redirected to `/auth`; authenticated users
/// landing on `/auth` are redirected to `/home`.
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
      bottomNavigationBar: _BottomNav(
        currentIndex: currentIndex,
        onTap: (i) => context.go(_tabs[i]),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.lavender.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.calendar_month_rounded,
                label: 'Calendar',
                selected: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.access_time_rounded,
                label: 'Free time',
                selected: currentIndex == 2,
                onTap: () => onTap(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? AppColors.roseLight.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => (selected
                        ? AppColors.heroGradient
                        : const LinearGradient(
                            colors: [
                              AppColors.onSurfaceMuted,
                              AppColors.onSurfaceMuted,
                            ],
                          ))
                    .createShader(bounds),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected ? AppColors.roseDark : AppColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
