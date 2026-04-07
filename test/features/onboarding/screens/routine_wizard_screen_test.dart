import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/onboarding/screens/routine_wizard_screen.dart';
import 'package:couple_sync/features/onboarding/widgets/routine_step_widget.dart';
import 'package:couple_sync/services/auth_service.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([
  FirebaseAuth,
  FirebaseFirestore,
  AuthService,
  User,
], customMocks: [
  MockSpec<CollectionReference<Map<String, dynamic>>>(
    as: #MockCollectionReferenceMap,
  ),
  MockSpec<DocumentReference<Map<String, dynamic>>>(
    as: #MockDocumentReferenceMap,
  ),
])
import 'routine_wizard_screen_test.mocks.dart';

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
    required super.firestore,
    required super.authService,
  });

  void setTestState(AuthState newState) {
    // ignore: invalid_use_of_protected_member
    state = newState;
  }
}

_TestAuthStateNotifier _createNotifier({
  required MockFirebaseAuth auth,
  required MockFirebaseFirestore firestore,
  required MockAuthService authService,
  User? user,
  UserModel? profile,
}) {
  final notifier = _TestAuthStateNotifier(
    auth: auth,
    firestore: firestore,
    authService: authService,
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => notifier),
      ],
      child: const MaterialApp(
        home: RoutineWizardScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockFirebaseFirestore mockFirestore;
  late MockAuthService mockAuthService;
  late MockUser mockUser;
  late MockCollectionReferenceMap mockCollection;
  late MockDocumentReferenceMap mockDocRef;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockFirestore = MockFirebaseFirestore();
    mockAuthService = MockAuthService();
    mockUser = MockUser();
    mockCollection = MockCollectionReferenceMap();
    mockDocRef = MockDocumentReferenceMap();

    when(mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
    when(mockFirestore.collection('users')).thenReturn(mockCollection);
    when(mockCollection.doc(any)).thenReturn(mockDocRef);
    when(mockUser.uid).thenReturn('test-uid');
  });

  group('RoutineWizardScreen', () {
    testWidgets('renders AppBar with step 1 of 3', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      expect(find.text('Set Up Your Routine (1/3)'), findsOneWidget);
    });

    testWidgets('shows linear progress indicator', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Sleep Schedule step initially', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      expect(find.text('Sleep Schedule'), findsOneWidget);
      expect(find.byIcon(Icons.bedtime), findsOneWidget);
    });

    testWidgets('shows Skip and Next buttons on first step', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      // No Back button on first step
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('does not show back button in AppBar', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.automaticallyImplyLeading, isFalse);
    });

    testWidgets('renders Bedtime and Wake up time pickers', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      expect(find.text('Bedtime'), findsOneWidget);
      expect(find.text('Wake up time'), findsOneWidget);
    });

    testWidgets('renders day-of-week selector on sleep step', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      expect(find.byType(DayOfWeekSelector), findsOneWidget);
    });

    testWidgets('navigates to step 2 when Next is tapped', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Set Up Your Routine (2/3)'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('navigates to step 2 when Skip is tapped', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Set Up Your Routine (2/3)'), findsOneWidget);
    });

    testWidgets('step 2 shows Work/Study Hours content', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      // Go to step 2
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Work/Study Hours'), findsOneWidget);
      expect(find.byIcon(Icons.work), findsOneWidget);
      expect(find.text('Start time'), findsOneWidget);
      expect(find.text('End time'), findsOneWidget);
    });

    testWidgets('Back button navigates from step 2 to step 1', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      // Go to step 2
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Go back to step 1
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Set Up Your Routine (1/3)'), findsOneWidget);
      expect(find.text('Sleep Schedule'), findsOneWidget);
    });

    testWidgets('step 3 shows Commute Time content', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      // Navigate to step 3
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Set Up Your Routine (3/3)'), findsOneWidget);
      expect(find.text('Commute Time'), findsOneWidget);
      expect(find.byIcon(Icons.directions_car), findsOneWidget);
    });

    testWidgets('step 3 shows Finish button instead of Next/Skip',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      // Navigate to step 3
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('step 3 shows commute direction selector', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      // Navigate to step 3
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.byType(CommuteDirectionSelector), findsOneWidget);
      expect(find.text('To Work'), findsOneWidget);
      expect(find.text('From Work'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
    });

    testWidgets('step 3 shows duration picker', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      // Navigate to step 3
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.byType(DurationPickerField), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget); // default duration
    });

    testWidgets('renders PageView with NeverScrollableScrollPhysics',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester, notifier: notifier);

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.physics, isA<NeverScrollableScrollPhysics>());
    });
  });
}
