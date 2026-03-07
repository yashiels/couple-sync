import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/providers/auth_providers.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authNotifierProvider);
    final isLoading = status == AuthStatus.loading;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // App icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.favorite_rounded,
                    color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Couple Schedule', style: AppTypography.largeTitle),
              const SizedBox(height: 8),
              Text(
                'Sync your lives, find your moments.',
                style: AppTypography.subhead.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(flex: 3),

              // Google Sign In — white bg, 1px border, 50px height, 10px radius
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: isLoading
                      ? null
                      : () => _signInWithGoogle(context, ref),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    side: const BorderSide(color: AppColors.separator),
                    backgroundColor: AppColors.surfaceElevated,
                  ),
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                  label: Text('Continue with Google',
                      style: AppTypography.headline),
                ),
              ),

              // Apple Sign In — black bg, 50px height, 10px radius
              if (kIsWeb ||
                  defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => _signInWithApple(context, ref),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.apple_rounded, size: 28),
                    label: Text('Continue with Apple',
                        style: AppTypography.headline
                            .copyWith(color: Colors.white)),
                  ),
                ),
              ],

              const SizedBox(height: 32),
              if (isLoading) const CupertinoActivityIndicator(),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  /// Determines the first route the user should land on after sign-in,
  /// based on whether their profile and couple pairing are complete.
  String _postSignInRoute(WidgetRef ref) {
    final user = ref.read(currentUserProvider);
    if (user == null) return '/home';
    // Timezone still holds an abbreviation (e.g. "UTC", "EST") or is empty —
    // the user hasn't completed timezone setup yet.
    final tz = user.timezone;
    final needsTimezone = tz.isEmpty || !tz.contains('/');
    if (needsTimezone) return '/timezone-setup';
    if (user.coupleId == null) return '/pairing';
    return '/home';
  }

  Future<void> _signInWithGoogle(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      if (context.mounted) context.go(_postSignInRoute(ref));
    } catch (e, st) {
      debugPrint('Google sign-in error: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $e')),
        );
      }
    }
  }

  Future<void> _signInWithApple(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authNotifierProvider.notifier).signInWithApple();
      if (context.mounted) context.go(_postSignInRoute(ref));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple sign-in failed. Please try again.')),
        );
      }
    }
  }
}
