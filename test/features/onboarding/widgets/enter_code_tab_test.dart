import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/onboarding/widgets/enter_code_tab.dart';
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

Future<void> _pumpWidget(
  WidgetTester tester, {
  required AuthStateNotifier notifier,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => notifier),
      ],
      child: const MaterialApp(
        home: Scaffold(body: EnterCodeTab()),
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

  group('EnterCodeTab', () {
    testWidgets('renders title text', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      expect(find.text("Enter Partner's Code"), findsOneWidget);
    });

    testWidgets('renders subtitle text', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      expect(
        find.text('Enter the code your partner shared with you'),
        findsOneWidget,
      );
    });

    testWidgets('renders key icon', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      expect(find.byIcon(Icons.vpn_key_outlined), findsOneWidget);
    });

    testWidgets('renders code input field with hint', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('XXXXXX'), findsOneWidget);
    });

    testWidgets('renders Redeem Code button', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      expect(find.text('Redeem Code'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('converts input to uppercase', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      await tester.enterText(find.byType(TextField), 'abcdef');
      await tester.pump();

      expect(find.text('ABCDEF'), findsOneWidget);
    });

    testWidgets('shows error when code is less than 6 characters',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      await tester.enterText(find.byType(TextField), 'ABC');
      await tester.pump();

      await tester.tap(find.text('Redeem Code'));
      await tester.pump();

      expect(find.text('Code must be 6 characters'), findsOneWidget);
    });

    testWidgets('shows error icon with validation error', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      await tester.enterText(find.byType(TextField), 'AB');
      await tester.pump();

      await tester.tap(find.text('Redeem Code'));
      await tester.pump();

      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('input field has max length of 6', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLength, 6);
    });

    testWidgets('input field has text capitalization set to characters',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.textCapitalization, TextCapitalization.characters);
    });

    testWidgets('does not show success or error initially', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      // Only one check_circle icon exists (the button's icon), no success message icon
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.error), findsNothing);
    });
  });
}
