import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';

/// Handles Firebase Auth operations and keeps the `users` Firestore collection
/// in sync with authenticated users.
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  // GoogleSignIn is only used on mobile. On web we use Firebase Auth's
  // signInWithPopup which handles OAuth natively without needing a
  // separate web client ID.
  final GoogleSignIn? _googleSignIn;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = kIsWeb ? null : (googleSignIn ?? GoogleSignIn());

  /// Stream of Firebase [User] auth-state changes (null when signed out).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// The currently signed-in Firebase [User], or `null` if not authenticated.
  User? get currentUser => _auth.currentUser;

  // --- Google ---

  /// Initiates the Google OAuth flow and signs in the resulting user.
  ///
  /// On web, uses Firebase Auth's `signInWithPopup` (no separate OAuth client
  /// needed). On mobile, uses the `google_sign_in` package.
  Future<UserModel> signInWithGoogle() async {
    if (kIsWeb) {
      return _signInWithGoogleWeb();
    }
    return _signInWithGoogleMobile();
  }

  Future<UserModel> _signInWithGoogleWeb() async {
    final provider = GoogleAuthProvider();
    final userCred = await _auth.signInWithPopup(provider);
    return _fetchOrCreateUser(userCred.user!);
  }

  Future<UserModel> _signInWithGoogleMobile() async {
    final googleUser = await _googleSignIn!.signIn();
    if (googleUser == null) throw Exception('Google sign-in cancelled');
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCred = await _auth.signInWithCredential(credential);
    return _fetchOrCreateUser(userCred.user!);
  }

  // --- Apple ---

  /// Initiates Apple Sign-In via Firebase Auth's provider flow.
  Future<UserModel> signInWithApple() async {
    final appleProvider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final userCred = await _auth.signInWithProvider(appleProvider);
    return _fetchOrCreateUser(userCred.user!);
  }

  // --- Helpers ---

  Future<UserModel> _fetchOrCreateUser(User user) async {
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) return UserModel.fromFirestore(doc);
    return _createUserDocument(user);
  }

  Future<UserModel> _createUserDocument(
    User user, {
    String? displayName,
  }) async {
    final model = UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: displayName ?? user.displayName ?? user.email?.split('@').first ?? 'User',
      photoUrl: user.photoURL,
      timezone: DateTime.now().timeZoneName,
      createdAt: DateTime.now().toUtc(),
    );
    await _firestore.collection('users').doc(user.uid).set(model.toFirestore());
    return model;
  }

  /// Persists a new IANA [timezone] string for the given [uid].
  Future<void> updateTimezone(String uid, String timezone) async {
    await _firestore.collection('users').doc(uid).update({'timezone': timezone});
  }

  /// Signs the user out of Firebase Auth and Google Sign-In.
  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      await _googleSignIn?.signOut();
    }
  }
}
