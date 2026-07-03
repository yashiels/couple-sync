import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/onboarding/widgets/share_code_tab.dart';
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

@GenerateMocks([FirebaseAuth, SyncService, AuthService, User])
import 'share_code_tab_test.mocks.dart';

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
  User? user,
  UserModel? profile,
}) {
  final notifier = _TestAuthStateNotifier(
    auth: auth,
    authService: authService,
    fetchProfile: (_) async => null,
  );
  notifier.setTestState(
    AuthState(firebaseUser: user, userProfile: profile, isLoading: false),
  );
  return notifier;
}

Future<void> _pumpWidget(
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
      child: const MaterialApp(home: Scaffold(body: ShareCodeTab())),
    ),
  );
  await tester.pump();
}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockSyncService mockSyncService;
  late MockAuthService mockAuthService;
  late MockUser mockUser;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockSyncService = MockSyncService();
    mockAuthService = MockAuthService();
    mockUser = MockUser();

    when(mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
    when(mockUser.uid).thenReturn('test-uid');
  });

  group('ShareCodeTab', () {
    testWidgets('renders title text', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.text('Share Your Code'), findsOneWidget);
    });

    testWidgets('renders subtitle text', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(
        find.text('Generate a code to share with your partner'),
        findsOneWidget,
      );
    });

    testWidgets('renders people icon', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.byIcon(Icons.people_outline), findsOneWidget);
    });

    testWidgets('shows Generate Code button initially', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.text('Generate Code'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('does not show code display initially', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.text('Your Invite Code'), findsNothing);
      expect(find.text('Copy Code'), findsNothing);
      expect(find.text('Share Code'), findsNothing);
    });

    testWidgets('shows code after successful generation', (tester) async {
      when(mockSyncService.createInvite(any)).thenAnswer((_) async => 'ABC123');

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      expect(find.text('Your Invite Code'), findsOneWidget);
      expect(find.text('ABC123'), findsOneWidget);
      expect(find.text('Copy Code'), findsOneWidget);
      expect(find.text('Share Code'), findsOneWidget);
    });

    testWidgets('hides Generate Code button after code is generated', (
      tester,
    ) async {
      when(mockSyncService.createInvite(any)).thenAnswer((_) async => 'ABC123');

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      expect(find.text('Generate Code'), findsNothing);
    });

    testWidgets('shows error when code generation fails', (tester) async {
      when(
        mockSyncService.createInvite(any),
      ).thenThrow(Exception('Network error'));

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      expect(
        find.text('Failed to generate code. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('shows error when not authenticated', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        // No user - not authenticated
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      expect(
        find.text('Failed to generate code. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('createInvite is called with the user uid', (tester) async {
      when(mockSyncService.createInvite(any)).thenAnswer((_) async => 'ABC123');

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      verify(mockSyncService.createInvite('test-uid')).called(1);
    });

    testWidgets('shows copy and share icons after generation', (tester) async {
      when(mockSyncService.createInvite(any)).thenAnswer((_) async => 'ABC123');

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
    });
  });
}
