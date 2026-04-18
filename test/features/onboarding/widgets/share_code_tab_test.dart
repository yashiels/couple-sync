import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/onboarding/widgets/share_code_tab.dart';
import 'package:couple_sync/services/auth_service.dart';
import 'package:couple_sync/services/firestore_service.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:couple_sync/services/providers/firestore_provider.dart';
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
  FirestoreService,
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
  MockFirestoreService? firestoreService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => notifier),
        if (firestoreService != null)
          firestoreServiceProvider.overrideWithValue(firestoreService),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ShareCodeTab()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockFirebaseFirestore mockFirestore;
  late MockFirestoreService mockFirestoreService;
  late MockAuthService mockAuthService;
  late MockUser mockUser;
  late MockCollectionReferenceMap mockCollection;
  late MockDocumentReferenceMap mockDocRef;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockFirestore = MockFirebaseFirestore();
    mockFirestoreService = MockFirestoreService();
    mockAuthService = MockAuthService();
    mockUser = MockUser();
    mockCollection = MockCollectionReferenceMap();
    mockDocRef = MockDocumentReferenceMap();

    when(mockAuth.authStateChanges()).thenAnswer((_) => const Stream.empty());
    when(mockFirestore.collection('users')).thenReturn(mockCollection);
    when(mockCollection.doc(any)).thenReturn(mockDocRef);
    when(mockUser.uid).thenReturn('test-uid');
  });

  group('ShareCodeTab', () {
    testWidgets('renders title text', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      expect(find.text('Share Your Code'), findsOneWidget);
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
        find.text('Generate a code to share with your partner'),
        findsOneWidget,
      );
    });

    testWidgets('renders people icon', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      expect(find.byIcon(Icons.people_outline), findsOneWidget);
    });

    testWidgets('shows Generate Code button initially', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      expect(find.text('Generate Code'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('does not show code display initially', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpWidget(tester, notifier: notifier);

      expect(find.text('Your Invite Code'), findsNothing);
      expect(find.text('Copy Code'), findsNothing);
      expect(find.text('Share Code'), findsNothing);
    });

    testWidgets('shows code after successful generation', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      when(mockFirestoreService.createInvite(any, any))
          .thenAnswer((_) async {});

      await _pumpWidget(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      expect(find.text('Your Invite Code'), findsOneWidget);
      expect(find.text('Copy Code'), findsOneWidget);
      expect(find.text('Share Code'), findsOneWidget);
    });

    testWidgets('hides Generate Code button after code is generated',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      when(mockFirestoreService.createInvite(any, any))
          .thenAnswer((_) async {});

      await _pumpWidget(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      expect(find.text('Generate Code'), findsNothing);
    });

    testWidgets('shows error when code generation fails', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      when(mockFirestoreService.createInvite(any, any))
          .thenThrow(Exception('Network error'));

      await _pumpWidget(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
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
        firestore: mockFirestore,
        authService: mockAuthService,
        // No user - not authenticated
      );

      await _pumpWidget(tester, notifier: notifier);

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      expect(
        find.text('Failed to generate code. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('generated code has 6 characters', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      when(mockFirestoreService.createInvite(any, any))
          .thenAnswer((_) async {});

      await _pumpWidget(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      // Verify createInvite was called with a 6-char code
      final captured =
          verify(mockFirestoreService.createInvite(captureAny, any))
              .captured;
      expect((captured.first as String).length, 6);
    });

    testWidgets('shows copy and share icons after generation', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      when(mockFirestoreService.createInvite(any, any))
          .thenAnswer((_) async {});

      await _pumpWidget(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      await tester.tap(find.text('Generate Code'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.share), findsOneWidget);
    });
  });
}
