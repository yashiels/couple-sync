import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/onboarding/widgets/enter_code_tab.dart';
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
import 'enter_code_tab_test.mocks.dart';

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
      child: const MaterialApp(home: Scaffold(body: EnterCodeTab())),
    ),
  );
  await tester.pump();
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

  group('EnterCodeTab', () {
    testWidgets('renders title text', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.text("Enter Partner's Code"), findsOneWidget);
    });

    testWidgets('renders subtitle text', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(
        find.text('Enter the code your partner shared with you'),
        findsOneWidget,
      );
    });

    testWidgets('renders key icon', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.byIcon(Icons.vpn_key_outlined), findsOneWidget);
    });

    testWidgets('renders code input field with hint', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('XXXXXX'), findsOneWidget);
    });

    testWidgets('renders Redeem Code button', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      expect(find.text('Redeem Code'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('converts input to uppercase', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.enterText(find.byType(TextField), 'abcdef');
      await tester.pump();

      expect(find.text('ABCDEF'), findsOneWidget);
    });

    testWidgets('shows error when code is less than 6 characters', (
      tester,
    ) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.enterText(find.byType(TextField), 'ABC');
      await tester.pump();

      await tester.tap(find.text('Redeem Code'));
      await tester.pump();

      expect(find.text('Code must be 6 characters'), findsOneWidget);
    });

    testWidgets('shows error icon with validation error', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.enterText(find.byType(TextField), 'AB');
      await tester.pump();

      await tester.tap(find.text('Redeem Code'));
      await tester.pump();

      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('input field has max length of 6', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLength, 6);
    });

    testWidgets('input field has text capitalization set to characters', (
      tester,
    ) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.textCapitalization, TextCapitalization.characters);
    });

    testWidgets('does not show success or error initially', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      // Only one check_circle icon exists (the button's icon), no success message icon
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.error), findsNothing);
    });

    testWidgets('redeems successfully via SyncService.redeemInvite', (
      tester,
    ) async {
      when(
        mockSyncService.redeemInvite(any),
      ).thenAnswer((_) async => 'couple-123');
      // refreshProfile() is called after a successful redeem; stub getUser so
      // it resolves with a profile instead of null (which would schedule a
      // retry timer that outlives the test).
      when(
        mockSyncService.getUser(any),
      ).thenAnswer((_) async => _testProfile(coupleId: 'couple-123'));

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.enterText(find.byType(TextField), 'ABCDEF');
      await tester.pump();

      await tester.tap(find.text('Redeem Code'));
      await tester.pump();
      await tester.pumpAndSettle();

      verify(mockSyncService.redeemInvite('ABCDEF')).called(1);
      expect(
        find.text('Successfully paired with your partner!'),
        findsOneWidget,
      );
    });

    testWidgets('maps http-404 to invalid invite code message', (tester) async {
      when(
        mockSyncService.redeemInvite(any),
      ).thenThrow(const SyncException(code: 'http-404', message: 'not found'));

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.enterText(find.byType(TextField), 'ABCDEF');
      await tester.pump();

      await tester.tap(find.text('Redeem Code'));
      await tester.pump();

      expect(find.text('Invalid invite code'), findsOneWidget);
    });

    testWidgets('maps http-409 expired to expired message', (tester) async {
      when(mockSyncService.redeemInvite(any)).thenThrow(
        const SyncException(
          code: 'http-409',
          message: 'conflict',
          originalError: 'The invite code has expired',
        ),
      );

      final notifier = _createNotifier(
        auth: mockAuth,
        authService: mockAuthService,
        syncService: mockSyncService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(
        tester,
        notifier: notifier,
        syncService: mockSyncService,
      );

      await tester.enterText(find.byType(TextField), 'ABCDEF');
      await tester.pump();

      await tester.tap(find.text('Redeem Code'));
      await tester.pump();

      expect(find.text('This invite code has expired'), findsOneWidget);
    });
  });
}
