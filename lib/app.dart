import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

/// Theme mode provider for managing light/dark theme.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Main application widget that provides the app shell.
/// Uses Riverpod for state management and GoRouter for navigation.
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      // App configuration
      title: 'Couple Sync',
      debugShowCheckedModeBanner: false,
      
      // Theme configuration
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      
      // Router configuration from Riverpod provider
      routerConfig: router,
      
      // Accessibility
      builder: (context, child) {
        // Ensure text scaling respects user preferences
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.4),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Extension to toggle theme mode.
/// Use via `ref.read(themeModeProvider.notifier).state = ...`
extension ThemeModeToggle on ThemeMode {
  ThemeMode toggle() {
    switch (this) {
      case ThemeMode.light:
        return ThemeMode.dark;
      case ThemeMode.dark:
        return ThemeMode.system;
      case ThemeMode.system:
        return ThemeMode.light;
    }
  }
}
