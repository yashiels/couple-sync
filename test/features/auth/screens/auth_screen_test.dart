import 'dart:async';

import 'package:couple_sync/features/auth/screens/auth_screen.dart';
import 'package:couple_sync/services/auth_service.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:couple_sync/services/providers/sync_provider.dart';
import 'package:couple_sync/services/sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([FirebaseAuth, AuthService, SyncService, User])
import 'auth_screen_test.mocks.dart';

/// Creates an AuthStateNotifier with injectable mocks. V7 constructor:
/// `(auth, authService, fetchProfile)` — `firestore` was removed when the
/// data layer moved to [SyncService]; `fetchProfile` delegates to
/// [SyncService.getUser].
AuthStateNotifier _createNotifier({
  required MockFirebaseAuth auth,
  required MockAuthService authService,
  required MockSyncService syncService,
}) {
  return AuthStateNotifier(
    auth: auth,
    authService: authService,
    profileRetryDelay: Duration.zero,
    fetchProfile: (uid) => syncService.getUser(uid),
  );
}

/// Sets up common mock behavior for FirebaseAuth to emit no auth changes.
void _setupAuthMocks(MockFirebaseAuth mockAuth) {
  when(mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
}

/// Pumps the AuthScreen wrapped in MaterialApp and ProviderScope.
Future<void> _pumpAuthScreen(
  WidgetTester tester, {
  required AuthStateNotifier notifier,
  required MockSyncService syncService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => notifier),
        syncServiceProvider.overrideWithValue(syncService),
      ],
      child: const MaterialApp(home: AuthScreen()),
    ),
  );
  // Let post-frame callbacks (clearError) execute
  await tester.pump();
}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockAuthService mockAuthService;
  late MockSyncService mockSyncService;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockAuthService = MockAuthService();
    mockSyncService = MockSyncService();

    _setupAuthMocks(mockAuth);
    // fetchProfile fallback — authStateChanges is empty so this is never
    // invoked, but stubbed to avoid MissingStubError.
    when(mockSyncService.getUser(any)).thenAnswer((_) async => null);
  });

  group('AuthScreen rendering', () {
    testWidgets('displays app name and tagline', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.text('Couple Sync'), findsOneWidget);
      expect(
        find.text('Find time together, no matter the distance'),
        findsOneWidget,
      );
    });

    testWidgets('displays heart icon', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('displays Google and Apple sign-in buttons', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Apple'), findsOneWidget);
    });

    testWidgets('displays terms and privacy text', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(
        find.text(
          'By signing in, you agree to our Terms of Service\n'
          'and Privacy Policy',
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays Apple icon on Apple button', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.byIcon(Icons.apple), findsOneWidget);
    });

    testWidgets('does not display error message initially', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('AuthScreen sign-in behavior', () {
    testWidgets('tapping Google button calls signInWithGoogle', (tester) async {
      when(
        mockAuthService.signInWithGoogle(),
      ).thenAnswer((_) async => MockUser());

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();

      verify(mockAuthService.signInWithGoogle()).called(1);
    });

    testWidgets('tapping Apple button calls signInWithApple', (tester) async {
      when(
        mockAuthService.signInWithApple(),
      ).thenAnswer((_) async => MockUser());

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Continue with Apple'));
      await tester.pump();

      verify(mockAuthService.signInWithApple()).called(1);
    });

    testWidgets('shows error message when Google sign-in fails', (
      tester,
    ) async {
      when(mockAuthService.signInWithGoogle()).thenThrow(
        AuthException(code: 'test', message: 'Google sign-in failed'),
      );

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();

      expect(find.text('Google sign-in failed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows error message when Apple sign-in fails', (tester) async {
      when(
        mockAuthService.signInWithApple(),
      ).thenThrow(AuthException(code: 'test', message: 'Apple sign-in failed'));

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Continue with Apple'));
      await tester.pump();

      expect(find.text('Apple sign-in failed'), findsOneWidget);
    });

    testWidgets('dismiss button clears error message', (tester) async {
      when(
        mockAuthService.signInWithGoogle(),
      ).thenThrow(AuthException(code: 'test', message: 'Sign-in error'));

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      // Trigger error
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      expect(find.text('Sign-in error'), findsOneWidget);

      // Dismiss error
      await tester.tap(find.byTooltip('Dismiss error'));
      await tester.pump();

      expect(find.text('Sign-in error'), findsNothing);
    });

    testWidgets('shows loading indicator during Google sign-in', (
      tester,
    ) async {
      final completer = Completer<User>();
      when(
        mockAuthService.signInWithGoogle(),
      ).thenAnswer((_) => completer.future);

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete to avoid pending futures
      completer.completeError(
        AuthException(code: 'test', message: 'cancelled'),
      );
      await tester.pump();
    });

    testWidgets('shows loading indicator during Apple sign-in', (tester) async {
      final completer = Completer<User>();
      when(
        mockAuthService.signInWithApple(),
      ).thenAnswer((_) => completer.future);

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Continue with Apple'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete to avoid pending futures
      completer.completeError(
        AuthException(code: 'test', message: 'cancelled'),
      );
      await tester.pump();
    });

    testWidgets('prevents double-tap on Google button while loading', (
      tester,
    ) async {
      final completer = Completer<User>();
      when(
        mockAuthService.signInWithGoogle(),
      ).thenAnswer((_) => completer.future);

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      // First tap
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();

      // Second tap while loading
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();

      // signInWithGoogle should only be called once
      verify(mockAuthService.signInWithGoogle()).called(1);

      // Complete to avoid pending futures
      completer.completeError(
        AuthException(code: 'test', message: 'cancelled'),
      );
      await tester.pump();
    });

    testWidgets('prevents tapping Apple button while Google is loading', (
      tester,
    ) async {
      final completer = Completer<User>();
      when(
        mockAuthService.signInWithGoogle(),
      ).thenAnswer((_) => completer.future);

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
      );

      await _pumpAuthScreen(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      // Tap Google first
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();

      // Try tapping Apple while Google is loading
      await tester.tap(find.text('Continue with Apple'));
      await tester.pump();

      verify(mockAuthService.signInWithGoogle()).called(1);
      verifyNever(mockAuthService.signInWithApple());

      // Complete to avoid pending futures
      completer.completeError(
        AuthException(code: 'test', message: 'cancelled'),
      );
      await tester.pump();
    });
  });
}
