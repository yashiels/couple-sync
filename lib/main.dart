import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'firebase_options.dart';

void main() async {
  // Ensure Flutter bindings are initialized before any Firebase operations
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with error handling
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    // Handle Firebase-specific initialization errors
    _handleInitializationError(
      'Firebase initialization failed: ${e.message ?? e.code}',
    );
    return;
  } catch (e) {
    // Handle any other unexpected errors
    _handleInitializationError('Unexpected error during initialization: $e');
    return;
  }

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
