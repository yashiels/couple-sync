import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';

// AuthService singleton
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

// Raw Firebase auth state
final firebaseAuthStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

// Whether the user is logged in
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(firebaseAuthStateProvider).valueOrNull != null;
});

// Current UserModel from Firestore (null when not logged in)
final currentUserProvider = StateProvider<UserModel?>((ref) => null);

// Auth flow state
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthNotifier extends StateNotifier<AuthStatus> {
  final AuthService _service;
  final StateController<UserModel?> _userController;

  AuthNotifier(this._service, this._userController) : super(AuthStatus.initial);

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String timezone,
  }) async {
    state = AuthStatus.loading;
    try {
      final user = await _service.signUpWithEmail(
        email: email,
        password: password,
        displayName: displayName,
        timezone: timezone,
      );
      _userController.state = user;
      state = AuthStatus.authenticated;
    } catch (_) {
      state = AuthStatus.error;
      rethrow;
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = AuthStatus.loading;
    try {
      final user = await _service.signInWithEmail(email: email, password: password);
      _userController.state = user;
      state = AuthStatus.authenticated;
    } catch (_) {
      state = AuthStatus.error;
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    state = AuthStatus.loading;
    try {
      final user = await _service.signInWithGoogle();
      _userController.state = user;
      state = AuthStatus.authenticated;
    } catch (_) {
      state = AuthStatus.error;
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _service.signOut();
    _userController.state = null;
    state = AuthStatus.unauthenticated;
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthStatus>((ref) {
  return AuthNotifier(
    ref.watch(authServiceProvider),
    ref.read(currentUserProvider.notifier),
  );
});
