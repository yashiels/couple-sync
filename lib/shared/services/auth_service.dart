import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  // --- Email / Password ---

  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String timezone,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user!.updateDisplayName(displayName);
    return _createUserDocument(credential.user!, displayName: displayName, timezone: timezone);
  }

  Future<UserModel> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _fetchOrCreateUser(credential.user!);
  }

  // --- Google ---

  Future<UserModel> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
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
  // Apple sign-in handled via firebase_auth's signInWithProvider on real devices.

  // --- Helpers ---

  Future<UserModel> _fetchOrCreateUser(User user) async {
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) return UserModel.fromFirestore(doc);
    return _createUserDocument(user);
  }

  Future<UserModel> _createUserDocument(
    User user, {
    String? displayName,
    String? timezone,
  }) async {
    final model = UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: displayName ?? user.displayName ?? user.email?.split('@').first ?? 'User',
      photoUrl: user.photoURL,
      timezone: timezone ?? 'UTC',
      createdAt: DateTime.now().toUtc(),
    );
    await _firestore.collection('users').doc(user.uid).set(model.toFirestore());
    return model;
  }

  Future<void> updateTimezone(String uid, String timezone) async {
    await _firestore.collection('users').doc(uid).update({'timezone': timezone});
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email);
}
