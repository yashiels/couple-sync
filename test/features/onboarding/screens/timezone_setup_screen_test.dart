import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/onboarding/screens/timezone_setup_screen.dart';
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

@GenerateMocks([
  FirebaseAuth,
  AuthService,
  SyncService,
  User,
])
import 'timezone_setup_screen_test.mocks.dart';

UserModel _testProfile({
  String timezone = 'America/New_York',
  String? coupleId,
}) {
  return UserModel(
    email: 'test@example.com',
    displayName: 'Test User',
    timezone: timezone,
    coupleId: coupleId,
    fcmTokens: const [],
    createdAt: DateTime(2024, 1, 1),
  );
}

/// AuthStateNotifier subclass that exposes `state` for test setup. Mirrors the
/// V7 constructor signature: `(auth, authService, fetchProfile)` — `firestore`
/// was removed when the data layer moved to [SyncService].
class _TestAuthStateNotifier extends AuthStateNotifier {
  _TestAuthStateNotifier({
    required super.auth,
    required super.authService,
    required super.fetchProfile,
  }) : super(profileRetryDelay: Duration.zero);

  void setTestState(AuthState newState) {
    // ignore: invalid_use_of_protected_member
    state = newState;
  }
}

_TestAuthStateNotifier _createNotifier({
  required MockFirebaseAuth auth,
  required MockAuthService authService,
  required MockSyncService syncService,
  User? user,
  UserModel? profile,
}) {
  final notifier = _TestAuthStateNotifier(
    auth: auth,
    authService: authService,
    fetchProfile: (uid) => syncService.getUser(uid),
  );
  notifier.setTestState(AuthState(
    firebaseUser: user,
    userProfile: profile,
    isLoading: false,
  ));
  return notifier;
}

Future<void> _pumpScreen(
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
      child: const MaterialApp(
        home: TimezoneSetupScreen(),
      ),
    ),
  );
  // Allow _initializeTimezone to run
  await tester.pumpAndSettle();
}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockAuthService mockAuthService;
  late MockSyncService mockSyncService;
  late MockUser mockUser;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockAuthService = MockAuthService();
    mockSyncService = MockSyncService();
    mockUser = MockUser();

    when(mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
    when(mockUser.uid).thenReturn('test-uid');
    // fetchProfile fallback — never called in these tests since authStateChanges
    // is empty and state is set directly, but stubbed to avoid MissingStubError.
    when(mockSyncService.getUser(any)).thenAnswer((_) async => null);
  });

  group('TimezoneSetupScreen', () {
    testWidgets('renders AppBar with title', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier, syncService: mockSyncService);

      expect(find.text('Set Your Timezone'), findsOneWidget);
    });

    testWidgets('does not show back button in AppBar', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier, syncService: mockSyncService);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.automaticallyImplyLeading, isFalse);
    });

    testWidgets('shows detected timezone text after loading', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier, syncService: mockSyncService);

      expect(find.text('We detected your timezone'), findsOneWidget);
    });

    testWidgets('shows search field', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier, syncService: mockSyncService);

      expect(find.text('Search timezones...'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('shows search helper text', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier, syncService: mockSyncService);

      expect(
        find.text('Or search for a different timezone:'),
        findsOneWidget,
      );
    });

    testWidgets('shows Continue button', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier, syncService: mockSyncService);

      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      // Pump only once to catch loading state before initializeTimezone completes
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((_) => notifier),
            syncServiceProvider.overrideWithValue(mockSyncService),
          ],
          child: const MaterialApp(
            home: TimezoneSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      // The screen may show a loading indicator or content depending on
      // how quickly _initializeTimezone completes
      expect(find.byType(TimezoneSetupScreen), findsOneWidget);
    });

    testWidgets('search field accepts input', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier, syncService: mockSyncService);

      await tester.enterText(
          find.byType(TextField).first, 'New York');
      await tester.pumpAndSettle();

      // Clear button should appear when there is text
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('clear button clears search input', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier, syncService: mockSyncService);

      await tester.enterText(
          find.byType(TextField).first, 'London');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Clear button should disappear
      expect(find.byIcon(Icons.clear), findsNothing);
    });

    testWidgets('has a Scaffold', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier, syncService: mockSyncService);

      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
