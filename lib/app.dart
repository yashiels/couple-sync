import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/router/routes.dart';
import 'core/theme/app_theme.dart';
import 'services/providers/notification_provider.dart';

/// Theme mode provider for managing light/dark theme.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Main application widget that provides the app shell.
/// Uses Riverpod for state management and GoRouter for navigation.
class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  StreamSubscription<RemoteMessage>? _messageOpenedSub;

  @override
  void initState() {
    super.initState();

    // Eagerly instantiate NotificationService so it registers FCM listeners and
    // calls initialize() as soon as an authenticated userId is available.
    ref.read(notificationServiceProvider);

    // Handle notification tap when app was in background (not terminated).
    // Tapping the system notification opens the app and navigates to /overlap.
    _messageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final router = ref.read(routerProvider);
      router.go(AppRoutes.overlap);
    });

    // Handle notification tap when app was terminated.
    // getInitialMessage() returns the message that launched the app if any.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null && mounted) {
        final router = ref.read(routerProvider);
        // Use addPostFrameCallback so the router is ready before navigating
        WidgetsBinding.instance.addPostFrameCallback((_) {
          router.go(AppRoutes.overlap);
        });
      }
    });
  }

  @override
  void dispose() {
    _messageOpenedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
