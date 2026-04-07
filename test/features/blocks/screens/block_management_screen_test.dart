import 'dart:async';

import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/core/router/routes.dart';
import 'package:couple_sync/features/blocks/screens/block_management_screen.dart';
import 'package:couple_sync/services/auth_service.dart';
import 'package:couple_sync/services/firestore_service.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:couple_sync/services/providers/firestore_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'block_management_screen_test.mocks.dart';

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

/// Helper to create a TimeBlock for tests.
TimeBlock _makeBlock({
  String userId = 'user-123',
  String title = 'Test Block',
  TimeBlockType type = TimeBlockType.busy,
  TimeBlockCategory category = TimeBlockCategory.work,
  int? startUtc,
  int? endUtc,
  String timezone = 'America/New_York',
  String? recurrenceRule,
  TimeBlockSource source = TimeBlockSource.manual,
  TimeBlockVisibility visibility = TimeBlockVisibility.bothPartners,
}) {
  final now = DateTime.utc(2025, 6, 15, 10, 0);
  return TimeBlock(
    userId: userId,
    title: title,
    type: type,
    category: category,
    startUtc: startUtc ?? now.millisecondsSinceEpoch,
    endUtc: endUtc ?? now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
    timezone: timezone,
    recurrenceRule: recurrenceRule,
    source: source,
    visibility: visibility,
    createdAt: DateTime(2024, 1, 1),
  );
}

/// Pumps BlockManagementScreen wrapped in GoRouter + ProviderScope.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required AuthStateNotifier notifier,
  required MockFirestoreService firestoreService,
}) async {
  final router = GoRouter(
    initialLocation: '/blocks',
    routes: [
      GoRoute(
        path: '/blocks',
        builder: (context, state) => const BlockManagementScreen(),
      ),
      GoRoute(
        path: AppRoutes.blockForm,
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Block Form')),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((_) => notifier),
        firestoreServiceProvider.overrideWithValue(firestoreService),
      ],
      child: MaterialApp.router(
        routerConfig: router,
      ),
    ),
  );
  // Let initState _loadBlocks complete
  await tester.pumpAndSettle();
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

  group('BlockManagementScreen rendering', () {
    testWidgets('displays AppBar with title "Block Management"',
        (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => []);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.text('Block Management'), findsOneWidget);
    });

    testWidgets('displays filter and refresh action buttons', (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => []);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.byIcon(Icons.filter_list), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('displays FAB with add icon', (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => []);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('BlockManagementScreen loading state', () {
    testWidgets('shows CircularProgressIndicator while loading',
        (tester) async {
      final completer = Completer<List<TimeBlock>>();
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) => completer.future);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      final router = GoRouter(
        initialLocation: '/blocks',
        routes: [
          GoRoute(
            path: '/blocks',
            builder: (context, state) => const BlockManagementScreen(),
          ),
          GoRoute(
            path: AppRoutes.blockForm,
            builder: (context, state) => const Scaffold(
              body: Center(child: Text('Block Form')),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((_) => notifier),
            firestoreServiceProvider.overrideWithValue(mockFirestoreService),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      // Only pump once — don't settle, so loading state is visible
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete to avoid pending timers
      completer.complete([]);
      await tester.pumpAndSettle();
    });
  });

  group('BlockManagementScreen empty state', () {
    testWidgets('shows empty state message when no blocks', (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => []);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.byIcon(Icons.event_busy), findsOneWidget);
      expect(find.textContaining('No blocks yet'), findsOneWidget);
      expect(find.textContaining('Tap + to create your first block'),
          findsOneWidget);
    });
  });

  group('BlockManagementScreen error state', () {
    testWidgets('shows error message when not authenticated', (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        // No user or profile
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Not authenticated or not in a couple'), findsOneWidget);
    });

    testWidgets('shows error message when profile has no coupleId',
        (tester) async {
      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(coupleId: null),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.text('Not authenticated or not in a couple'), findsOneWidget);
    });

    testWidgets('shows error when getBlocks throws', (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenThrow(Exception('Network error'));

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Failed to load blocks'), findsOneWidget);
    });

    testWidgets('shows Retry button on error', (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenThrow(Exception('Network error'));

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Retry button reloads blocks', (tester) async {
      // First call throws, second succeeds
      var callCount = 0;
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw Exception('Network error');
        }
        return [_makeBlock(title: 'Loaded Block')];
      });

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      // Verify error state
      expect(find.text('Retry'), findsOneWidget);

      // Tap retry
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Should now show the loaded block
      expect(find.text('Loaded Block'), findsOneWidget);
    });
  });

  group('BlockManagementScreen with blocks', () {
    testWidgets('displays blocks from firestore', (tester) async {
      final blocks = [
        _makeBlock(title: 'Morning Meeting', category: TimeBlockCategory.work),
        _makeBlock(
          title: 'Gym Session',
          category: TimeBlockCategory.exercise,
          startUtc: DateTime.utc(2025, 6, 15, 14, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2025, 6, 15, 15, 0).millisecondsSinceEpoch,
        ),
      ];

      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => blocks);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.text('Morning Meeting'), findsOneWidget);
      expect(find.text('Gym Session'), findsOneWidget);
    });

    testWidgets('displays blocks sorted by start time', (tester) async {
      final blocks = [
        _makeBlock(
          title: 'Later Block',
          startUtc: DateTime.utc(2025, 6, 15, 14, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2025, 6, 15, 15, 0).millisecondsSinceEpoch,
        ),
        _makeBlock(
          title: 'Earlier Block',
          startUtc: DateTime.utc(2025, 6, 15, 8, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2025, 6, 15, 9, 0).millisecondsSinceEpoch,
        ),
      ];

      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => blocks);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      // Both blocks visible
      expect(find.text('Earlier Block'), findsOneWidget);
      expect(find.text('Later Block'), findsOneWidget);

      // Earlier block should appear before Later block in the list
      final earlierPos = tester.getTopLeft(find.text('Earlier Block'));
      final laterPos = tester.getTopLeft(find.text('Later Block'));
      expect(earlierPos.dy, lessThan(laterPos.dy));
    });

    testWidgets('shows owner label "You" for current user blocks',
        (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async =>
              [_makeBlock(title: 'My Block', userId: 'user-123')]);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('shows owner label "Partner" for partner blocks',
        (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async =>
              [_makeBlock(title: 'Partner Block', userId: 'partner-456')]);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.text('Partner'), findsOneWidget);
    });
  });

  group('BlockManagementScreen block tap', () {
    testWidgets('tapping a block shows read-only dialog', (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => [
                _makeBlock(
                  title: 'Work Meeting',
                  source: TimeBlockSource.google,
                  category: TimeBlockCategory.work,
                  type: TimeBlockType.busy,
                  visibility: TimeBlockVisibility.bothPartners,
                ),
              ]);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      // Tap the block
      await tester.tap(find.text('Work Meeting'));
      await tester.pumpAndSettle();

      // Dialog should show details
      expect(find.text('Work Meeting'), findsNWidgets(2)); // list + dialog
      expect(find.text('Google'), findsAtLeastNWidgets(1));
      expect(find.text('Work'), findsAtLeastNWidgets(1));
      expect(find.text('Busy'), findsOneWidget);
      expect(find.text('Both Partners'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('google-sourced block dialog has no Edit button',
        (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => [
                _makeBlock(
                    title: 'Synced Event', source: TimeBlockSource.google),
              ]);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      await tester.tap(find.text('Synced Event'));
      await tester.pumpAndSettle();

      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('manual block dialog has Edit button', (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => [
                _makeBlock(
                    title: 'Manual Block', source: TimeBlockSource.manual),
              ]);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      // Tap block - this triggers both navigation and dialog
      await tester.tap(find.text('Manual Block'));
      await tester.pump(); // Process tap and dialog show
      await tester.pump(); // Let dialog animation start

      // Edit button should be in the dialog actions
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('recurring block dialog shows recurrence info',
        (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => [
                _makeBlock(
                  title: 'Weekly Standup',
                  recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO',
                  source: TimeBlockSource.google, // Use google so no GoRouter needed
                ),
              ]);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      await tester.tap(find.text('Weekly Standup'));
      await tester.pumpAndSettle();

      // _buildDetailRow renders '$label:' so it's 'Recurs:'
      expect(find.text('Recurs:'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
    });

    testWidgets('Close button dismisses dialog', (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => [
                _makeBlock(
                    title: 'Test Block', source: TimeBlockSource.google),
              ]);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      await tester.tap(find.text('Test Block'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('BlockManagementScreen filter sheet', () {
    testWidgets('tapping filter icon opens bottom sheet', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => []);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      expect(find.text('Filter Blocks'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Apply Filters'), findsOneWidget);
    });

    testWidgets('filter sheet shows source filter chips', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => []);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Source filter chips: All, Manual, Google
      expect(find.widgetWithText(FilterChip, 'All'), findsAtLeastNWidgets(1));
      expect(
          find.widgetWithText(FilterChip, 'Manual'), findsAtLeastNWidgets(1));
      expect(
          find.widgetWithText(FilterChip, 'Google'), findsAtLeastNWidgets(1));
    });

    testWidgets('filter sheet shows category filter chips', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => []);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // All category chips present
      expect(find.widgetWithText(FilterChip, 'Work'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Study'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Sleep'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Exercise'), findsOneWidget);
    });

    testWidgets('selecting source filter filters blocks', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blocks = [
        _makeBlock(title: 'Manual Block', source: TimeBlockSource.manual),
        _makeBlock(
          title: 'Google Block',
          source: TimeBlockSource.google,
          startUtc: DateTime.utc(2025, 6, 15, 12, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2025, 6, 15, 13, 0).millisecondsSinceEpoch,
        ),
      ];

      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => blocks);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      // Both blocks visible initially
      expect(find.text('Manual Block'), findsOneWidget);
      expect(find.text('Google Block'), findsOneWidget);

      // Open filter sheet
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Select "Manual" source filter
      await tester.tap(find.widgetWithText(FilterChip, 'Manual'));
      await tester.pumpAndSettle();

      // Apply
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Only manual block should be visible
      expect(find.text('Manual Block'), findsOneWidget);
      expect(find.text('Google Block'), findsNothing);
    });

    testWidgets('selecting category filter filters blocks', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blocks = [
        _makeBlock(
            title: 'Work Block', category: TimeBlockCategory.work),
        _makeBlock(
          title: 'Exercise Block',
          category: TimeBlockCategory.exercise,
          startUtc: DateTime.utc(2025, 6, 15, 12, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2025, 6, 15, 13, 0).millisecondsSinceEpoch,
        ),
      ];

      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => blocks);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      // Open filter sheet
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Select "Work" category filter
      await tester.tap(find.widgetWithText(FilterChip, 'Work'));
      await tester.pumpAndSettle();

      // Apply
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Only work block visible
      expect(find.text('Work Block'), findsOneWidget);
      expect(find.text('Exercise Block'), findsNothing);
    });
  });

  group('BlockManagementScreen filter indicator', () {
    testWidgets('shows filter indicator when filters are active',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blocks = [
        _makeBlock(title: 'Block 1', source: TimeBlockSource.manual),
        _makeBlock(
          title: 'Block 2',
          source: TimeBlockSource.google,
          startUtc: DateTime.utc(2025, 6, 15, 12, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2025, 6, 15, 13, 0).millisecondsSinceEpoch,
        ),
      ];

      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => blocks);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      // Apply a filter
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Manual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Should show filter indicator with count
      expect(find.textContaining('Filters active'), findsOneWidget);
      expect(find.textContaining('1 of 2 blocks'), findsOneWidget);
    });

    testWidgets('Clear button removes all filters', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blocks = [
        _makeBlock(title: 'Block A', source: TimeBlockSource.manual),
        _makeBlock(
          title: 'Block B',
          source: TimeBlockSource.google,
          startUtc: DateTime.utc(2025, 6, 15, 12, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2025, 6, 15, 13, 0).millisecondsSinceEpoch,
        ),
      ];

      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => blocks);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      // Apply a filter
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Manual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      // Only Block A visible
      expect(find.text('Block B'), findsNothing);

      // Tap Clear
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      // Both blocks visible again
      expect(find.text('Block A'), findsOneWidget);
      expect(find.text('Block B'), findsOneWidget);
      expect(find.textContaining('Filters active'), findsNothing);
    });

    testWidgets('shows "No blocks match your filters" when filter yields empty',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blocks = [
        _makeBlock(title: 'Only Manual', source: TimeBlockSource.manual),
      ];

      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => blocks);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      // Apply Google filter (no google blocks exist)
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(find.text('No blocks match your filters'), findsOneWidget);
    });
  });

  group('BlockManagementScreen refresh', () {
    testWidgets('tapping refresh button reloads blocks', (tester) async {
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => [_makeBlock(title: 'Initial Block')]);

      final notifier = _createNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
        user: mockUser,
        profile: _testProfile(),
      );

      await _pumpScreen(tester,
          notifier: notifier, firestoreService: mockFirestoreService);

      expect(find.text('Initial Block'), findsOneWidget);

      // Change mock to return updated data
      when(mockFirestoreService.getBlocks('couple-123', 'user-123'))
          .thenAnswer((_) async => [_makeBlock(title: 'Updated Block')]);

      // Tap refresh
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(find.text('Updated Block'), findsOneWidget);
    });
  });
}
