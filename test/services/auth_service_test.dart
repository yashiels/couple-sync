import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_sync/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([
  FirebaseAuth,
  FirebaseFirestore,
  GoogleSignIn,
  GoogleSignInAccount,
  GoogleSignInAuthentication,
  User,
  UserCredential,
  AdditionalUserInfo,
  CollectionReference,
  DocumentReference,
  DocumentSnapshot,
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
import 'auth_service_test.mocks.dart';

void main() {
  late MockFirebaseAuth mockAuth;
  late MockFirebaseFirestore mockFirestore;
  late MockGoogleSignIn mockGoogleSignIn;
  late AuthService authService;

  late MockCollectionReferenceMap mockUsersCollection;
  late MockDocumentReferenceMap mockUserDoc;
  late MockDocumentSnapshotMap mockDocSnapshot;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockFirestore = MockFirebaseFirestore();
    mockGoogleSignIn = MockGoogleSignIn();

    mockUsersCollection = MockCollectionReferenceMap();
    mockUserDoc = MockDocumentReferenceMap();
    mockDocSnapshot = MockDocumentSnapshotMap();

    authService = AuthService(
      auth: mockAuth,
      firestore: mockFirestore,
      googleSignIn: mockGoogleSignIn,
    );
  });

  void stubFirestoreForNewUser(MockUser mockUser) {
    when(mockUser.uid).thenReturn('test-uid');
    when(mockUser.email).thenReturn('test@example.com');
    when(mockUser.displayName).thenReturn('Test User');
    when(mockUser.photoURL).thenReturn('https://photo.url/test.jpg');

    when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
    when(mockUsersCollection.doc('test-uid')).thenReturn(mockUserDoc);
    when(mockUserDoc.get()).thenAnswer((_) async => mockDocSnapshot);
    when(mockDocSnapshot.exists).thenReturn(false);
    when(mockUserDoc.set(any)).thenAnswer((_) async {});
  }

  void stubFirestoreForExistingUser(
    MockUser mockUser, {
    Map<String, dynamic>? existingData,
  }) {
    when(mockUser.uid).thenReturn('test-uid');
    when(mockUser.email).thenReturn('test@example.com');
    when(mockUser.displayName).thenReturn('Test User');
    when(mockUser.photoURL).thenReturn('https://photo.url/test.jpg');

    when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
    when(mockUsersCollection.doc('test-uid')).thenReturn(mockUserDoc);
    when(mockUserDoc.get()).thenAnswer((_) async => mockDocSnapshot);
    when(mockDocSnapshot.exists).thenReturn(true);
    when(mockDocSnapshot.data()).thenReturn(existingData ??
        {
          'email': 'test@example.com',
          'displayName': 'Test User',
          'photoUrl': 'https://photo.url/test.jpg',
        });
    when(mockUserDoc.update(any)).thenAnswer((_) async {});
  }

  group('AuthService', () {
    group('authStateChanges', () {
      test('delegates to FirebaseAuth.authStateChanges()', () {
        final mockStream = Stream<User?>.value(null);
        when(mockAuth.authStateChanges()).thenAnswer((_) => mockStream);

        expect(authService.authStateChanges, mockStream);
        verify(mockAuth.authStateChanges()).called(1);
      });
    });

    group('currentUser', () {
      test('returns null when no user is signed in', () {
        when(mockAuth.currentUser).thenReturn(null);
        expect(authService.currentUser, isNull);
      });

      test('returns the current user when signed in', () {
        final mockUser = MockUser();
        when(mockAuth.currentUser).thenReturn(mockUser);
        expect(authService.currentUser, mockUser);
      });
    });

    group('isAuthenticated', () {
      test('returns false when no user is signed in', () {
        when(mockAuth.currentUser).thenReturn(null);
        expect(authService.isAuthenticated, isFalse);
      });

      test('returns true when a user is signed in', () {
        final mockUser = MockUser();
        when(mockAuth.currentUser).thenReturn(mockUser);
        expect(authService.isAuthenticated, isTrue);
      });
    });

    group('signInWithGoogle', () {
      test('throws AuthException when user cancels sign-in', () async {
        when(mockGoogleSignIn.signIn()).thenAnswer((_) async => null);

        expect(
          () => authService.signInWithGoogle(),
          throwsA(isA<AuthException>().having(
            (e) => e.code,
            'code',
            'sign-in-cancelled',
          )),
        );
      });

      test('signs in successfully and creates new user doc', () async {
        final mockGoogleAccount = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();
        final mockUserCredential = MockUserCredential();
        final mockUser = MockUser();

        when(mockGoogleSignIn.signIn())
            .thenAnswer((_) async => mockGoogleAccount);
        when(mockGoogleAccount.authentication)
            .thenAnswer((_) async => mockGoogleAuth);
        when(mockGoogleAuth.accessToken).thenReturn('access-token');
        when(mockGoogleAuth.idToken).thenReturn('id-token');
        when(mockAuth.signInWithCredential(any))
            .thenAnswer((_) async => mockUserCredential);
        when(mockUserCredential.user).thenReturn(mockUser);

        stubFirestoreForNewUser(mockUser);

        final result = await authService.signInWithGoogle();

        expect(result, mockUser);
        verify(mockAuth.signInWithCredential(any)).called(1);
        verify(mockUserDoc.set(any)).called(1);
      });

      test('signs in and updates existing user doc when data changed',
          () async {
        final mockGoogleAccount = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();
        final mockUserCredential = MockUserCredential();
        final mockUser = MockUser();

        when(mockGoogleSignIn.signIn())
            .thenAnswer((_) async => mockGoogleAccount);
        when(mockGoogleAccount.authentication)
            .thenAnswer((_) async => mockGoogleAuth);
        when(mockGoogleAuth.accessToken).thenReturn('access-token');
        when(mockGoogleAuth.idToken).thenReturn('id-token');
        when(mockAuth.signInWithCredential(any))
            .thenAnswer((_) async => mockUserCredential);
        when(mockUserCredential.user).thenReturn(mockUser);

        stubFirestoreForExistingUser(mockUser, existingData: {
          'email': 'old@example.com',
          'displayName': 'Old Name',
          'photoUrl': 'https://old.url/photo.jpg',
        });

        final result = await authService.signInWithGoogle();

        expect(result, mockUser);
        verify(mockUserDoc.update(any)).called(1);
      });

      test('signs in and skips update when no data changed', () async {
        final mockGoogleAccount = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();
        final mockUserCredential = MockUserCredential();
        final mockUser = MockUser();

        when(mockGoogleSignIn.signIn())
            .thenAnswer((_) async => mockGoogleAccount);
        when(mockGoogleAccount.authentication)
            .thenAnswer((_) async => mockGoogleAuth);
        when(mockGoogleAuth.accessToken).thenReturn('access-token');
        when(mockGoogleAuth.idToken).thenReturn('id-token');
        when(mockAuth.signInWithCredential(any))
            .thenAnswer((_) async => mockUserCredential);
        when(mockUserCredential.user).thenReturn(mockUser);

        stubFirestoreForExistingUser(mockUser);

        await authService.signInWithGoogle();

        verifyNever(mockUserDoc.update(any));
      });

      test('throws AuthException when signInWithCredential returns null user',
          () async {
        final mockGoogleAccount = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();
        final mockUserCredential = MockUserCredential();

        when(mockGoogleSignIn.signIn())
            .thenAnswer((_) async => mockGoogleAccount);
        when(mockGoogleAccount.authentication)
            .thenAnswer((_) async => mockGoogleAuth);
        when(mockGoogleAuth.accessToken).thenReturn('access-token');
        when(mockGoogleAuth.idToken).thenReturn('id-token');
        when(mockAuth.signInWithCredential(any))
            .thenAnswer((_) async => mockUserCredential);
        when(mockUserCredential.user).thenReturn(null);

        expect(
          () => authService.signInWithGoogle(),
          throwsA(isA<AuthException>().having(
            (e) => e.code,
            'code',
            'sign-in-failed',
          )),
        );
      });

      test('wraps FirebaseAuthException as AuthException', () async {
        final mockGoogleAccount = MockGoogleSignInAccount();
        final mockGoogleAuth = MockGoogleSignInAuthentication();

        when(mockGoogleSignIn.signIn())
            .thenAnswer((_) async => mockGoogleAccount);
        when(mockGoogleAccount.authentication)
            .thenAnswer((_) async => mockGoogleAuth);
        when(mockGoogleAuth.accessToken).thenReturn('access-token');
        when(mockGoogleAuth.idToken).thenReturn('id-token');
        when(mockAuth.signInWithCredential(any))
            .thenThrow(FirebaseAuthException(
          code: 'network-request-failed',
          message: 'Network error',
        ));

        expect(
          () => authService.signInWithGoogle(),
          throwsA(isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Network error. Please check your connection and try again.',
          )),
        );
      });

      test('wraps unknown exceptions as AuthException', () async {
        when(mockGoogleSignIn.signIn()).thenThrow(Exception('unexpected'));

        expect(
          () => authService.signInWithGoogle(),
          throwsA(isA<AuthException>().having(
            (e) => e.code,
            'code',
            'unknown-error',
          )),
        );
      });
    });

    group('signOut', () {
      test('signs out from Google and Firebase', () async {
        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
        when(mockAuth.signOut()).thenAnswer((_) async {});

        await authService.signOut();

        verify(mockGoogleSignIn.signOut()).called(1);
        verify(mockAuth.signOut()).called(1);
      });

      test('wraps FirebaseAuthException as AuthException', () async {
        when(mockGoogleSignIn.signOut()).thenAnswer((_) async => null);
        when(mockAuth.signOut()).thenThrow(FirebaseAuthException(
          code: 'too-many-requests',
          message: 'Rate limited',
        ));

        expect(
          () => authService.signOut(),
          throwsA(isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Too many attempts. Please try again later.',
          )),
        );
      });

      test('wraps unknown exceptions as AuthException', () async {
        when(mockGoogleSignIn.signOut()).thenThrow(Exception('unexpected'));

        expect(
          () => authService.signOut(),
          throwsA(isA<AuthException>().having(
            (e) => e.code,
            'code',
            'unknown-error',
          )),
        );
      });
    });

    group('AuthException', () {
      test('stores code and message', () {
        const e = AuthException(code: 'test-code', message: 'Test message');
        expect(e.code, 'test-code');
        expect(e.message, 'Test message');
      });

      test('toString includes code and message', () {
        const e = AuthException(code: 'test-code', message: 'Test message');
        expect(e.toString(), 'AuthException(test-code): Test message');
      });
    });

    group('Firebase error message mapping', () {
      // Test all error codes by triggering sign-in failures
      final errorCases = {
        'user-disabled':
            'This account has been disabled. Please contact support.',
        'too-many-requests': 'Too many attempts. Please try again later.',
        'network-request-failed':
            'Network error. Please check your connection and try again.',
        'invalid-credential': 'Invalid credentials. Please try again.',
        'account-exists-with-different-credential':
            'An account already exists with a different sign-in method. '
                'Please use the original sign-in method.',
        'some-other-code': 'Sign in failed. Please try again.',
      };

      for (final entry in errorCases.entries) {
        test('maps "${entry.key}" to correct message', () async {
          final mockGoogleAccount = MockGoogleSignInAccount();
          final mockGoogleAuth = MockGoogleSignInAuthentication();

          when(mockGoogleSignIn.signIn())
              .thenAnswer((_) async => mockGoogleAccount);
          when(mockGoogleAccount.authentication)
              .thenAnswer((_) async => mockGoogleAuth);
          when(mockGoogleAuth.accessToken).thenReturn('access-token');
          when(mockGoogleAuth.idToken).thenReturn('id-token');
          when(mockAuth.signInWithCredential(any))
              .thenThrow(FirebaseAuthException(
            code: entry.key,
            message: 'original',
          ));

          expect(
            () => authService.signInWithGoogle(),
            throwsA(isA<AuthException>().having(
              (e) => e.message,
              'message',
              entry.value,
            )),
          );
        });
      }
    });
  });
}
