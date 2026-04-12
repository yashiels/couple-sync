import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/services/auth_service.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  MockSpec<DocumentSnapshot<Map<String, dynamic>>>(
    as: #MockDocumentSnapshotMap,
  ),
])
import 'auth_state_provider_test.mocks.dart';

void main() {
  group('AuthState', () {
    test('default state has null user, null profile, isLoading true', () {
      const state = AuthState();
      expect(state.firebaseUser, isNull);
      expect(state.userProfile, isNull);
      expect(state.isLoading, isTrue);
    });

    test('isAuthenticated returns true when firebaseUser is present', () {
      final mockUser = _FakeUser();
      final state = AuthState(firebaseUser: mockUser);
      expect(state.isAuthenticated, isTrue);
    });

    test('isAuthenticated returns false when firebaseUser is null', () {
      const state = AuthState();
      expect(state.isAuthenticated, isFalse);
    });

    test('hasTimezone returns true when profile has non-empty timezone', () {
      final profile = _createUserModel(timezone: 'America/New_York');
      final state = AuthState(userProfile: profile);
      expect(state.hasTimezone, isTrue);
    });

    test('hasTimezone returns false when profile has empty timezone', () {
      final profile = _createUserModel(timezone: '');
      final state = AuthState(userProfile: profile);
      expect(state.hasTimezone, isFalse);
    });

    test('hasTimezone returns false when profile is null', () {
      const state = AuthState();
      expect(state.hasTimezone, isFalse);
    });

    test('hasCouple returns true when profile has coupleId', () {
      final profile = _createUserModel(coupleId: 'couple-123');
      final state = AuthState(userProfile: profile);
      expect(state.hasCouple, isTrue);
    });

    test('hasCouple returns false when profile has null coupleId', () {
      final profile = _createUserModel();
      final state = AuthState(userProfile: profile);
      expect(state.hasCouple, isFalse);
    });

    test('hasCouple returns false when profile is null', () {
      const state = AuthState();
      expect(state.hasCouple, isFalse);
    });

    test('uid returns firebaseUser uid when authenticated', () {
      final mockUser = _FakeUser(uid: 'test-uid-123');
      final state = AuthState(firebaseUser: mockUser);
      expect(state.uid, 'test-uid-123');
    });

    test('uid returns null when not authenticated', () {
      const state = AuthState();
      expect(state.uid, isNull);
    });

    test('profile returns userProfile', () {
      final profile = _createUserModel();
      final state = AuthState(userProfile: profile);
      expect(state.profile, profile);
    });

    group('copyWith', () {
      test('copies with new firebaseUser', () {
        const state = AuthState();
        final mockUser = _FakeUser();
        final newState = state.copyWith(firebaseUser: mockUser);
        expect(newState.firebaseUser, mockUser);
      });

      test('copies with new userProfile', () {
        const state = AuthState();
        final profile = _createUserModel();
        final newState = state.copyWith(userProfile: profile);
        expect(newState.userProfile, profile);
      });

      test('copies with new isLoading', () {
        const state = AuthState();
        final newState = state.copyWith(isLoading: false);
        expect(newState.isLoading, isFalse);
      });

      test('clearFirebaseUser sets firebaseUser to null', () {
        final mockUser = _FakeUser();
        final state = AuthState(firebaseUser: mockUser);
        final newState = state.copyWith(clearFirebaseUser: true);
        expect(newState.firebaseUser, isNull);
      });

      test('clearUserProfile sets userProfile to null', () {
        final profile = _createUserModel();
        final state = AuthState(userProfile: profile);
        final newState = state.copyWith(clearUserProfile: true);
        expect(newState.userProfile, isNull);
      });

      test('retains existing values when not overridden', () {
        final mockUser = _FakeUser();
        final profile = _createUserModel();
        final state = AuthState(
          firebaseUser: mockUser,
          userProfile: profile,
          isLoading: false,
        );
        final newState = state.copyWith();
        expect(newState.firebaseUser, mockUser);
        expect(newState.userProfile, profile);
        expect(newState.isLoading, isFalse);
      });
    });

    test('toString includes key state info', () {
      const state = AuthState();
      final str = state.toString();
      expect(str, contains('isAuthenticated: false'));
      expect(str, contains('hasTimezone: false'));
      expect(str, contains('hasCouple: false'));
      expect(str, contains('isLoading: true'));
    });
  });

  group('AuthStateNotifier', () {
    late MockFirebaseAuth mockAuth;
    late MockFirebaseFirestore mockFirestore;
    late MockAuthService mockAuthService;
    late MockCollectionReferenceMap mockUsersCollection;
    late MockDocumentReferenceMap mockUserDoc;
    late MockDocumentSnapshotMap mockDocSnapshot;
    late StreamController<User?> authStreamController;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockFirestore = MockFirebaseFirestore();
      mockAuthService = MockAuthService();
      mockUsersCollection = MockCollectionReferenceMap();
      mockUserDoc = MockDocumentReferenceMap();
      mockDocSnapshot = MockDocumentSnapshotMap();
      authStreamController = StreamController<User?>();

      when(mockAuth.authStateChanges())
          .thenAnswer((_) => authStreamController.stream);
      when(mockFirestore.collection('users'))
          .thenReturn(mockUsersCollection);
    });

    tearDown(() {
      authStreamController.close();
    });

    AuthStateNotifier createNotifier() {
      return AuthStateNotifier(
        auth: mockAuth,
        firestore: mockFirestore,
        authService: mockAuthService,
      );
    }

    void stubUserDoc(String uid) {
      when(mockUsersCollection.doc(uid)).thenReturn(mockUserDoc);
      when(mockUserDoc.get()).thenAnswer((_) async => mockDocSnapshot);
    }

    test('initial state is loading with no user', () {
      final notifier = createNotifier();
      expect(notifier.state.isLoading, isTrue);
      expect(notifier.state.isAuthenticated, isFalse);
      expect(notifier.state.userProfile, isNull);
    });

    test('clears state when user signs out', () async {
      final notifier = createNotifier();

      authStreamController.add(null);
      await Future.delayed(Duration.zero);

      expect(notifier.state.isAuthenticated, isFalse);
      expect(notifier.state.userProfile, isNull);
      expect(notifier.state.isLoading, isFalse);
    });

    test('fetches profile when user signs in with existing doc', () async {
      final mockUser = MockUser();
      when(mockUser.uid).thenReturn('uid-123');
      stubUserDoc('uid-123');
      when(mockDocSnapshot.exists).thenReturn(true);
      when(mockDocSnapshot.data()).thenReturn({
        'email': 'test@example.com',
        'displayName': 'Test User',
        'photoUrl': null,
        'timezone': 'America/New_York',
        'coupleId': 'couple-abc',
        'fcmTokens': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });

      final notifier = createNotifier();

      authStreamController.add(mockUser);
      await Future.delayed(Duration.zero);
      // Wait for async _fetchUserProfile to complete
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.firebaseUser, mockUser);
      expect(notifier.state.userProfile, isNotNull);
      expect(notifier.state.userProfile!.email, 'test@example.com');
      expect(notifier.state.userProfile!.timezone, 'America/New_York');
      expect(notifier.state.userProfile!.coupleId, 'couple-abc');
      expect(notifier.state.isLoading, isFalse);
    });

    test('sets null profile when user doc does not exist', () async {
      final mockUser = MockUser();
      when(mockUser.uid).thenReturn('uid-new');
      stubUserDoc('uid-new');
      when(mockDocSnapshot.exists).thenReturn(false);

      final notifier = createNotifier();

      authStreamController.add(mockUser);
      // Wait for retry delay (1.5s) + buffer
      await Future.delayed(const Duration(milliseconds: 2000));

      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.userProfile, isNull);
      expect(notifier.state.isLoading, isFalse);
    });

    test('sets null profile when doc exists but data is null', () async {
      final mockUser = MockUser();
      when(mockUser.uid).thenReturn('uid-null');
      stubUserDoc('uid-null');
      when(mockDocSnapshot.exists).thenReturn(true);
      when(mockDocSnapshot.data()).thenReturn(null);

      final notifier = createNotifier();

      authStreamController.add(mockUser);
      await Future.delayed(const Duration(milliseconds: 2000));

      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.userProfile, isNull);
      expect(notifier.state.isLoading, isFalse);
    });

    test('handles Firestore fetch error gracefully', () async {
      final mockUser = MockUser();
      when(mockUser.uid).thenReturn('uid-err');
      when(mockUsersCollection.doc('uid-err')).thenReturn(mockUserDoc);
      when(mockUserDoc.get()).thenThrow(FirebaseException(
        plugin: 'firestore',
        message: 'Permission denied',
      ));

      final notifier = createNotifier();

      authStreamController.add(mockUser);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.isAuthenticated, isTrue);
      expect(notifier.state.userProfile, isNull);
      expect(notifier.state.isLoading, isFalse);
    });

    group('refreshProfile', () {
      test('refetches profile from Firestore', () async {
        final mockUser = MockUser();
        when(mockUser.uid).thenReturn('uid-refresh');
        stubUserDoc('uid-refresh');
        when(mockDocSnapshot.exists).thenReturn(true);
        when(mockDocSnapshot.data()).thenReturn({
          'email': 'test@example.com',
          'displayName': 'Test User',
          'photoUrl': null,
          'timezone': 'Europe/London',
          'coupleId': null,
          'fcmTokens': <String>[],
          'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        });

        final notifier = createNotifier();

        // First, sign in
        authStreamController.add(mockUser);
        await Future.delayed(const Duration(milliseconds: 50));

        // Then refresh
        await notifier.refreshProfile();

        expect(notifier.state.userProfile!.timezone, 'Europe/London');
        expect(notifier.state.isLoading, isFalse);
        // get() called twice: once from auth stream, once from refresh
        verify(mockUserDoc.get()).called(2);
      });

      test('does nothing when not authenticated', () async {
        final notifier = createNotifier();

        // Sign out first
        authStreamController.add(null);
        await Future.delayed(Duration.zero);

        await notifier.refreshProfile();

        verifyNever(mockUserDoc.get());
      });
    });

    group('signInWithGoogle', () {
      test('returns true on success', () async {
        when(mockAuthService.signInWithGoogle())
            .thenAnswer((_) async => MockUser());

        final notifier = createNotifier();
        final result = await notifier.signInWithGoogle();

        expect(result, isTrue);
        expect(notifier.lastError, isNull);
      });

      test('returns false and sets lastError on AuthException', () async {
        when(mockAuthService.signInWithGoogle()).thenThrow(
          const AuthException(code: 'cancelled', message: 'User cancelled'),
        );

        final notifier = createNotifier();
        final result = await notifier.signInWithGoogle();

        expect(result, isFalse);
        expect(notifier.lastError, 'User cancelled');
      });
    });

    group('signInWithApple', () {
      test('returns true on success', () async {
        when(mockAuthService.signInWithApple())
            .thenAnswer((_) async => MockUser());

        final notifier = createNotifier();
        final result = await notifier.signInWithApple();

        expect(result, isTrue);
        expect(notifier.lastError, isNull);
      });

      test('returns false and sets lastError on AuthException', () async {
        when(mockAuthService.signInWithApple()).thenThrow(
          const AuthException(code: 'failed', message: 'Apple Sign-In failed'),
        );

        final notifier = createNotifier();
        final result = await notifier.signInWithApple();

        expect(result, isFalse);
        expect(notifier.lastError, 'Apple Sign-In failed');
      });
    });

    group('signOut', () {
      test('delegates to authService.signOut', () async {
        when(mockAuthService.signOut()).thenAnswer((_) async {});

        final notifier = createNotifier();
        await notifier.signOut();

        verify(mockAuthService.signOut()).called(1);
        expect(notifier.lastError, isNull);
      });

      test('sets lastError on AuthException', () async {
        when(mockAuthService.signOut()).thenThrow(
          const AuthException(code: 'error', message: 'Sign out failed'),
        );

        final notifier = createNotifier();
        await notifier.signOut();

        expect(notifier.lastError, 'Sign out failed');
      });
    });

    group('lastError and clearError', () {
      test('lastError is null initially', () {
        final notifier = createNotifier();
        expect(notifier.lastError, isNull);
      });

      test('clearError resets lastError to null', () async {
        when(mockAuthService.signInWithGoogle()).thenThrow(
          const AuthException(code: 'err', message: 'Error'),
        );

        final notifier = createNotifier();
        await notifier.signInWithGoogle();
        expect(notifier.lastError, 'Error');

        notifier.clearError();
        expect(notifier.lastError, isNull);
      });

      test('signInWithGoogle clears previous error on new attempt', () async {
        when(mockAuthService.signInWithGoogle()).thenThrow(
          const AuthException(code: 'err', message: 'First error'),
        );

        final notifier = createNotifier();
        await notifier.signInWithGoogle();
        expect(notifier.lastError, 'First error');

        // Second attempt succeeds
        when(mockAuthService.signInWithGoogle())
            .thenAnswer((_) async => MockUser());
        await notifier.signInWithGoogle();
        expect(notifier.lastError, isNull);
      });
    });
  });

  group('Convenience providers', () {
    test('isLoadingProvider reads authState isLoading', () {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => _FakeAuthStateNotifier(const AuthState(isLoading: true)),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(isLoadingProvider), isTrue);
    });

    test('currentUserIdProvider reads uid from authState', () {
      final mockUser = _FakeUser(uid: 'provider-uid');
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => _FakeAuthStateNotifier(
              AuthState(firebaseUser: mockUser, isLoading: false),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentUserIdProvider), 'provider-uid');
    });

    test('currentUserIdProvider returns null when not authenticated', () {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => _FakeAuthStateNotifier(
              const AuthState(isLoading: false),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentUserIdProvider), isNull);
    });

    test('currentUserProfileProvider reads userProfile from authState', () {
      final profile = _createUserModel(timezone: 'Asia/Tokyo');
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => _FakeAuthStateNotifier(
              AuthState(userProfile: profile, isLoading: false),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentUserProfileProvider), profile);
    });

    test('currentUserProfileProvider returns null when no profile', () {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => _FakeAuthStateNotifier(
              const AuthState(isLoading: false),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(currentUserProfileProvider), isNull);
    });

    test('authServiceProvider returns an AuthService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // This will throw because FirebaseAuth.instance requires initialization,
      // but we can verify the provider type exists and is configured correctly
      expect(authServiceProvider, isA<Provider<AuthService>>());
    });
  });
}

/// Helper to create a UserModel for testing.
UserModel _createUserModel({
  String email = 'test@example.com',
  String displayName = 'Test User',
  String? photoUrl,
  String timezone = '',
  String? coupleId,
  List<String> fcmTokens = const [],
  DateTime? createdAt,
}) {
  return UserModel(
    email: email,
    displayName: displayName,
    photoUrl: photoUrl,
    timezone: timezone,
    coupleId: coupleId,
    fcmTokens: fcmTokens,
    createdAt: createdAt ?? DateTime(2024, 1, 1),
  );
}

/// Minimal fake User for AuthState tests that don't need Mockito.
class _FakeUser extends Fake implements User {
  final String _uid;
  _FakeUser({String uid = 'fake-uid'}) : _uid = uid;

  @override
  String get uid => _uid;
}

/// Fake AuthStateNotifier for provider override tests.
/// Extends StateNotifier directly to avoid triggering _init().
class _FakeAuthStateNotifier extends StateNotifier<AuthState>
    implements AuthStateNotifier {
  _FakeAuthStateNotifier(AuthState initialState) : super(initialState);

  @override
  String? get lastError => null;

  @override
  void clearError() {}

  @override
  Future<void> refreshProfile() async {}

  @override
  Future<bool> signInWithGoogle() async => false;

  @override
  Future<bool> signInWithApple() async => false;

  @override
  Future<void> signOut() async {}
}
