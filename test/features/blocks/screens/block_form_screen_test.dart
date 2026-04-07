import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/blocks/screens/block_form_screen.dart';
import 'package:couple_sync/core/router/routes.dart';
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
  MockSpec<DocumentSnapshot<Map<String, dynamic>>>(
    as: #MockDocumentSnapshotMap,
  ),
])
import 'block_form_screen_test.mocks.dart';

/// Creates a UserModel for testing.
UserModel _testProfile({
  String timezone = 'America/New_York',
  String? coupleId = 'couple-123',
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

/// A test-only AuthStateNotifier subclass that exposes state setting.
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

/// Creates an AuthStateNotifier pre-loaded with the given state.
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

/// Pumps BlockFormScreen wrapped in MaterialApp + ProviderScope.
Future<void> _pumpBlockFormScreen(
  WidgetTester tester, {
  required AuthStateNotifier notifier,
  MockFirestoreService? firestoreService,
  BlockFormArgs? args,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => notifier),
        if (firestoreService != null)
          firestoreServiceProvider.overrideWithValue(firestoreService),
      ],
      child: MaterialApp(
        home: BlockFormScreen(args: args),
      ),
    ),
  );
  // Let post-frame callbacks (timezone setting) execute
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
    when(mockUser.uid).thenReturn('user-123');
  });

  group('BlockFormScreen rendering (new block)', () {
    testWidgets('displays "New Block" title in AppBar', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.text('New Block'), findsOneWidget);
    });

    testWidgets('displays title text field with label', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.text('Title *'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('displays Type dropdown with default Busy', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.text('Type'), findsOneWidget);
      expect(find.text('Busy'), findsOneWidget);
    });

    testWidgets('displays Category dropdown with default Other',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('displays Visibility dropdown with default Both Partners',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.text('Visibility'), findsOneWidget);
      expect(find.text('Both Partners'), findsOneWidget);
    });

    testWidgets('displays Start and End labels', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.text('Start'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
    });

    testWidgets('displays date and time picker buttons', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      // 2 date buttons + 2 time buttons
      expect(find.byIcon(Icons.calendar_today), findsNWidgets(2));
      expect(find.byIcon(Icons.access_time), findsNWidgets(2));
    });

    testWidgets('displays timezone from user profile', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(timezone: 'Europe/London'),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.text('Timezone: Europe/London'), findsOneWidget);
    });

    testWidgets('displays Recurrence section', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.text('Recurrence'), findsOneWidget);
      expect(find.text('Does not repeat'), findsOneWidget);
    });

    testWidgets('displays "Create Block" button for new block',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.text('Create Block'), findsOneWidget);
    });

    testWidgets('does not show delete button for new block', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      expect(find.byIcon(Icons.delete), findsNothing);
    });
  });

  group('BlockFormScreen rendering (edit mode)', () {
    testWidgets('displays "Edit Block" title when blockId provided',
        (tester) async {
      // Setup Firestore mock for _loadBlock
      final mockTimeBlocksCollection = MockCollectionReferenceMap();
      final mockCoupleDoc = MockDocumentReferenceMap();
      final mockBlocksCollection = MockCollectionReferenceMap();
      final mockBlockDoc = MockDocumentReferenceMap();
      final mockBlockSnapshot = MockDocumentSnapshotMap();

      when(mockFirestore.collection('timeblocks'))
          .thenReturn(mockTimeBlocksCollection);
      when(mockTimeBlocksCollection.doc('couple-123'))
          .thenReturn(mockCoupleDoc);
      when(mockCoupleDoc.collection('blocks'))
          .thenReturn(mockBlocksCollection);
      when(mockBlocksCollection.doc('block-456')).thenReturn(mockBlockDoc);
      when(mockBlockDoc.get()).thenAnswer((_) async => mockBlockSnapshot);
      when(mockBlockSnapshot.exists).thenReturn(false);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        args: const BlockFormArgs(blockId: 'block-456'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Block'), findsOneWidget);
    });

    testWidgets('shows delete button in edit mode', (tester) async {
      final mockTimeBlocksCollection = MockCollectionReferenceMap();
      final mockCoupleDoc = MockDocumentReferenceMap();
      final mockBlocksCollection = MockCollectionReferenceMap();
      final mockBlockDoc = MockDocumentReferenceMap();
      final mockBlockSnapshot = MockDocumentSnapshotMap();

      when(mockFirestore.collection('timeblocks'))
          .thenReturn(mockTimeBlocksCollection);
      when(mockTimeBlocksCollection.doc('couple-123'))
          .thenReturn(mockCoupleDoc);
      when(mockCoupleDoc.collection('blocks'))
          .thenReturn(mockBlocksCollection);
      when(mockBlocksCollection.doc('block-456')).thenReturn(mockBlockDoc);
      when(mockBlockDoc.get()).thenAnswer((_) async => mockBlockSnapshot);
      when(mockBlockSnapshot.exists).thenReturn(false);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        args: const BlockFormArgs(blockId: 'block-456'),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('displays "Update Block" button in edit mode', (tester) async {
      final mockTimeBlocksCollection = MockCollectionReferenceMap();
      final mockCoupleDoc = MockDocumentReferenceMap();
      final mockBlocksCollection = MockCollectionReferenceMap();
      final mockBlockDoc = MockDocumentReferenceMap();
      final mockBlockSnapshot = MockDocumentSnapshotMap();

      when(mockFirestore.collection('timeblocks'))
          .thenReturn(mockTimeBlocksCollection);
      when(mockTimeBlocksCollection.doc('couple-123'))
          .thenReturn(mockCoupleDoc);
      when(mockCoupleDoc.collection('blocks'))
          .thenReturn(mockBlocksCollection);
      when(mockBlocksCollection.doc('block-456')).thenReturn(mockBlockDoc);
      when(mockBlockDoc.get()).thenAnswer((_) async => mockBlockSnapshot);
      when(mockBlockSnapshot.exists).thenReturn(false);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        args: const BlockFormArgs(blockId: 'block-456'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update Block'), findsOneWidget);
    });
  });

  group('BlockFormScreen form validation', () {
    testWidgets('shows error when title is empty and save tapped',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      // Scroll to make Create Block button visible, then tap
      await tester.ensureVisible(find.text('Create Block'));
      await tester.pump();
      await tester.tap(find.text('Create Block'));
      await tester.pump();

      expect(find.text('Title is required'), findsOneWidget);
    });

    testWidgets('no validation error when title is provided', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      // Enter title
      await tester.enterText(find.byType(TextFormField), 'My Block');
      await tester.pump();

      // Scroll to make Create Block button visible, then tap
      await tester.ensureVisible(find.text('Create Block'));
      await tester.pump();
      await tester.tap(find.text('Create Block'));
      await tester.pump();

      expect(find.text('Title is required'), findsNothing);
    });

    testWidgets('shows error when title is only whitespace', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      // Enter whitespace-only title
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.pump();

      await tester.ensureVisible(find.text('Create Block'));
      await tester.pump();
      await tester.tap(find.text('Create Block'));
      await tester.pump();

      expect(find.text('Title is required'), findsOneWidget);
    });
  });

  group('BlockFormScreen save behavior', () {
    testWidgets('calls createBlock on firestoreService when saving new block',
        (tester) async {
      when(mockFirestoreService.createBlock(any, any))
          .thenAnswer((_) async => 'new-block-id');

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      // Enter title
      await tester.enterText(find.byType(TextFormField), 'Work Meeting');
      await tester.pump();

      // Scroll to and tap save
      await tester.ensureVisible(find.text('Create Block'));
      await tester.pump();
      await tester.tap(find.text('Create Block'));
      await tester.pumpAndSettle();

      verify(mockFirestoreService.createBlock('couple-123', any)).called(1);
    });

    testWidgets('shows error when user has no coupleId', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(coupleId: null),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      // Enter title
      await tester.enterText(find.byType(TextFormField), 'Work Meeting');
      await tester.pump();

      // Scroll to and tap save
      await tester.ensureVisible(find.text('Create Block'));
      await tester.pump();
      await tester.tap(find.text('Create Block'));
      await tester.pump();

      expect(
        find.text('Not authenticated or not in a couple'),
        findsOneWidget,
      );
    });

    testWidgets('shows error when createBlock throws', (tester) async {
      when(mockFirestoreService.createBlock(any, any))
          .thenThrow(Exception('Firestore error'));

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        firestoreService: mockFirestoreService,
      );

      // Enter title
      await tester.enterText(find.byType(TextFormField), 'Work Meeting');
      await tester.pump();

      // Scroll to and tap save
      await tester.ensureVisible(find.text('Create Block'));
      await tester.pump();
      await tester.tap(find.text('Create Block'));
      await tester.pump();

      expect(find.textContaining('Failed to save block'), findsOneWidget);
    });
  });

  group('BlockFormScreen with initialDate', () {
    testWidgets('uses provided initialDate for start date', (tester) async {
      final initialDate = DateTime(2025, 6, 15, 10, 30);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(
        tester,
        notifier: notifier,
        args: BlockFormArgs(initialDate: initialDate),
      );

      // Should show the initial date formatted as d/m/y for both start and end (same day)
      expect(find.text('15/6/2025'), findsNWidgets(2));
    });
  });

  group('BlockFormScreen dropdown interactions', () {
    testWidgets('can select different block type', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      // Open Type dropdown
      await tester.tap(find.text('Busy'));
      await tester.pumpAndSettle();

      // Select Free
      await tester.tap(find.text('Free').last);
      await tester.pumpAndSettle();

      expect(find.text('Free'), findsOneWidget);
    });

    testWidgets('can select different category', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      // Open Category dropdown
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();

      // Select Work
      await tester.tap(find.text('Work').last);
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('can select different visibility', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpBlockFormScreen(tester, notifier: notifier);

      // Open Visibility dropdown
      await tester.tap(find.text('Both Partners'));
      await tester.pumpAndSettle();

      // Select Only Me
      await tester.tap(find.text('Only Me').last);
      await tester.pumpAndSettle();

      expect(find.text('Only Me'), findsOneWidget);
    });
  });
}
