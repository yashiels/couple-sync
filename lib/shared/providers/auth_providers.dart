import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';

/// Singleton [AuthService] instance available throughout the widget tree.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Raw Firebase auth-state stream (emits `null` when signed out).
final firebaseAuthStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// `true` when a Firebase user is currently signed in.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(firebaseAuthStateProvider).valueOrNull != null;
});

/// The signed-in user's [UserModel] from Firestore, or `null` when logged out.
final currentUserProvider = StateProvider<UserModel?>((ref) => null);

/// Possible states of the authentication flow.
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

/// Manages sign-in and sign-out operations, driving [AuthStatus].
class AuthNotifier extends StateNotifier<AuthStatus> {
  final AuthService _service;
  final StateController<UserModel?> _userController;

  AuthNotifier(this._service, this._userController) : super(AuthStatus.initial);

  /// Initiates the Google OAuth flow and signs in the resulting user.
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

  /// Initiates Apple Sign-In via Firebase Auth's provider flow.
  Future<void> signInWithApple() async {
    state = AuthStatus.loading;
    try {
      final user = await _service.signInWithApple();
      _userController.state = user;
      state = AuthStatus.authenticated;
    } catch (_) {
      state = AuthStatus.error;
      rethrow;
    }
  }

  /// Signs out of Firebase Auth and clears local user state.
  Future<void> signOut() async {
    await _service.signOut();
    _userController.state = null;
    state = AuthStatus.unauthenticated;
  }
}

/// Provider that exposes [AuthNotifier] and its [AuthStatus].
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthStatus>((ref) {
  return AuthNotifier(
    ref.watch(authServiceProvider),
    ref.read(currentUserProvider.notifier),
  );
});
