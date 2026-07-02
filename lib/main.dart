import 'dart:ui';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/utils/timezone_helper.dart';
import 'firebase_options.dart';

/// Top-level background message handler for FCM.
/// Must be a top-level function (not a class method) and registered before runApp.
/// The OS invokes this in a separate isolate when the app is in the background.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are displayed as system notifications by the OS automatically.
  // No additional handling needed — the notification is shown by FCM infrastructure.
  debugPrint('FCM background message: ${message.messageId}');
}

void main() async {
  // Ensure Flutter bindings are initialized before any Firebase operations
  WidgetsFlutterBinding.ensureInitialized();

  // Set the default locale for intl formatters (DateFormat, NumberFormat, etc.)
  // so locale-aware skeletons like jm() respect the device locale.
  Intl.defaultLocale = PlatformDispatcher.instance.locale.toString();

  // Initialize Firebase with error handling
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    _handleInitializationError(
      'Firebase initialization failed: ${e.message ?? e.code}',
    );
    return;
  } catch (e) {
    _handleInitializationError('Unexpected error during initialization: $e');
    return;
  }

  // Activate Firebase App Check. Debug providers are used in debug builds
  // (incl. emulator sessions) so local dev stays frictionless; release builds
  // use the platform-native attestation providers (DeviceCheck on iOS, Play
  // Integrity on Android). Enforcement on Firestore writes + callables is
  // configured in the Firebase Console (see docs/MANUAL_STEPS.md).
  if (kDebugMode) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );
  }

  // ponytail: point Firebase Auth at the local emulator when the
  // USE_FIREBASE_EMULATOR dart-define is set. Opt-in via --dart-define so
  // prod/release builds are untouched. iOS sim uses 'localhost' (Android
  // would need 10.0.2.2, but we're targeting iOS sim for the demo).
  // Firestore/Cloud Functions emulators are gone (V7 dropped them); data
  // now flows through SyncService → self-host backend. Point the backend
  // at a local tunnel via --dart-define=SYNC_BASE_URL=... instead.
  const useEmulator =
      bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);
  if (useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }

  // Hive is the offline block cache backing SyncService. Must be initialised
  // before any SyncService is constructed (the provider is first read once
  // the app starts running).
  await Hive.initFlutter();

  // Initialize timezone database before any TZDateTime operations
  await TimezoneHelper.initialize();

  // Register FCM background message handler before runApp.
  // Must be called after Firebase.initializeApp().
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

/// Handles initialization errors by showing a user-friendly error screen.
/// This function ensures the app crashes gracefully with meaningful feedback.
void _handleInitializationError(String error) {
  debugPrint('CRITICAL: $error');
  // Run a minimal error app that shows the user something went wrong
  runApp(ErrorApp(errorMessage: error));
}

/// A minimal error screen shown when Firebase initialization fails.
/// Provides user-friendly feedback without exposing sensitive details.
class ErrorApp extends StatelessWidget {
  final String errorMessage;

  const ErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
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
                const Text(
                  'Unable to Start App',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'We encountered a problem while initializing the app. '
                  'Please try again later or contact support if the issue persists.',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Show detailed error in debug mode only
                if (bool.fromEnvironment('dart.vm.product') == false)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Debug: $errorMessage',
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// MyApp and MyHomePage moved to lib/app.dart
// Theme and routing configuration now in lib/core/theme/ and lib/app.dart
