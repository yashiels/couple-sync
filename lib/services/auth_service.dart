import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Service for handling Firebase Authentication with Google and Apple Sign-In.
/// Manages user creation and profile synchronization with Firestore.
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    required GoogleSignIn googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn;

  /// Stream of authentication state changes from Firebase.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Current authenticated user, or null if not signed in.
  User? get currentUser => _auth.currentUser;

  /// Whether a user is currently signed in.
  bool get isAuthenticated => _auth.currentUser != null;

  /// Signs in with Google OAuth.
  /// Creates a user document in Firestore if this is the first sign-in.
  ///
  /// Returns the signed-in user.
  /// Throws [AuthException] with a user-friendly message on failure.
  Future<User> signInWithGoogle() async {
    try {
      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        throw AuthException(
          code: 'sign-in-cancelled',
          message: 'Sign in was cancelled. Please try again.',
        );
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) {
        throw AuthException(
          code: 'sign-in-failed',
          message: 'Failed to sign in with Google. Please try again.',
        );
      }

      // Store calendar access token so CalendarService is auto-connected
      if (googleAuth.accessToken != null) {
        try {
          const storage = FlutterSecureStorage();
          await storage.write(
            key: 'google_calendar_access_token',
            value: googleAuth.accessToken,
          );
        } catch (_) {
          // Non-critical — calendar can be connected manually later
        }
      }

      // Create or update user document in Firestore
      await _createOrUpdateUserDocument(user);

      return user;
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthException(
        code: e.code,
        message: _getFirebaseAuthErrorMessage(e),
      );
    } catch (e) {
      throw AuthException(
        code: 'unknown-error',
        message: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  /// Signs in with Apple.
  /// Creates a user document in Firestore if this is the first sign-in.
  ///
  /// Returns the signed-in user.
  /// Throws [AuthException] with a user-friendly message on failure.
  Future<User> signInWithApple() async {
    try {
      // Request Apple credential
      final AuthorizationCredentialAppleID appleCredential =
          await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Create an OAuthCredential from the Apple credential
      final OAuthCredential credential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Sign in to Firebase with the Apple credential
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) {
        throw AuthException(
          code: 'sign-in-failed',
          message: 'Failed to sign in with Apple. Please try again.',
        );
      }

      // For Apple Sign-In, the display name might be in the additionalUserInfo
      // We need to update the Firebase profile if we got name info
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        final givenName = appleCredential.givenName;
        final familyName = appleCredential.familyName;

        if (givenName != null || familyName != null) {
          final displayName = [givenName, familyName]
              .where((n) => n != null && n.isNotEmpty)
              .join(' ');

          if (displayName.isNotEmpty) {
            await user.updateDisplayName(displayName);
            // Reload to get the updated profile
            await user.reload();
          }
        }
      }

      // Create or update user document in Firestore
      await _createOrUpdateUserDocument(_auth.currentUser ?? user);

      return _auth.currentUser ?? user;
    } on AuthException {
      rethrow;
    } on SignInWithAppleAuthorizationException catch (e) {
      throw AuthException(
        code: e.code.toString(),
        message: _getAppleSignInErrorMessage(e),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(
        code: e.code,
        message: _getFirebaseAuthErrorMessage(e),
      );
    } catch (e) {
      throw AuthException(
        code: 'unknown-error',
        message: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  /// Signs out the current user from Firebase and all auth providers.
  ///
  /// Throws [AuthException] with a user-friendly message on failure.
  Future<void> signOut() async {
    try {
      // Sign out from Google (clears cached account)
      await _googleSignIn.signOut();

      // Sign out from Firebase
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthException(
        code: e.code,
        message: _getFirebaseAuthErrorMessage(e),
      );
    } catch (e) {
      throw AuthException(
        code: 'unknown-error',
        message: 'An unexpected error occurred during sign out. Please try again.',
      );
    }
  }

  /// Creates or updates the user document in Firestore.
  /// On first sign-in, creates a new document with email, displayName, and photoUrl.
  /// On subsequent sign-ins, updates the profile info if changed.
  Future<void> _createOrUpdateUserDocument(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);

    try {
      final docSnapshot = await userRef.get();

      final String? displayName = user.displayName;
      final String? photoUrl = user.photoURL;
      final String email = user.email ?? '';

      if (!docSnapshot.exists) {
        // First sign-in: create new user document
        await userRef.set({
          'email': email,
          'displayName': displayName ?? '',
          'photoUrl': photoUrl,
          'timezone': '', // Will be set during onboarding
          'coupleId': null, // Will be set when paired
          'fcmTokens': <String>[],
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Existing user: update profile info if changed
        final data = docSnapshot.data() as Map<String, dynamic>;

        final updates = <String, dynamic>{};

        // Update email if changed
        if (email.isNotEmpty && data['email'] != email) {
          updates['email'] = email;
        }

        // Update displayName if changed
        if (displayName != null && displayName.isNotEmpty && data['displayName'] != displayName) {
          updates['displayName'] = displayName;
        }

        // Update photoUrl if changed
        if (photoUrl != data['photoUrl']) {
          updates['photoUrl'] = photoUrl;
        }

        // Only update if there are changes
        if (updates.isNotEmpty) {
          await userRef.update(updates);
        }
      }
    } catch (e) {
      // Log but don't throw - the user is still authenticated
      // Profile sync can be retried later
      // In production, this would be logged to a monitoring service
    }
  }

  /// Converts FirebaseAuthException codes to user-friendly messages.
  String _getFirebaseAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      case 'invalid-credential':
        return 'Invalid credentials. Please try again.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with a different sign-in method. '
            'Please use the original sign-in method.';
      default:
        return 'Sign in failed. Please try again.';
    }
  }

  /// Converts SignInWithAppleAuthorizationException to user-friendly messages.
  String _getAppleSignInErrorMessage(SignInWithAppleAuthorizationException e) {
    switch (e.code) {
      case AuthorizationErrorCode.canceled:
        return 'Sign in was cancelled. Please try again.';
      case AuthorizationErrorCode.failed:
        return 'Apple Sign-In failed. Please try again.';
      case AuthorizationErrorCode.invalidResponse:
        return 'Invalid response from Apple. Please try again.';
      case AuthorizationErrorCode.notHandled:
        return 'Sign in could not be completed. Please try again.';
      case AuthorizationErrorCode.unknown:
        return 'An unknown error occurred with Apple Sign-In. Please try again.';
      default:
        return 'An error occurred with Apple Sign-In. Please try again.';
    }
  }
}

/// Exception for authentication errors with user-friendly messages.
class AuthException implements Exception {
  final String code;
  final String message;

  const AuthException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'AuthException($code): $message';
}
