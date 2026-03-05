import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calendar/providers/google_calendar_provider.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'pairing_providers.dart';

/// Singleton [AuthService] instance available throughout the widget tree.
///
/// Uses the shared [GoogleSignIn] instance from [sharedGoogleSignInProvider]
/// so that both auth and calendar services operate on the same OAuth session,
/// avoiding scope mismatch (Bug 12).
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    googleSignIn: ref.watch(sharedGoogleSignInProvider),
  );
});

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
  final Ref _ref;

  AuthNotifier(this._service, this._userController, this._ref)
      : super(AuthStatus.initial);

  /// Initiates the Google OAuth flow and signs in the resulting user.
  ///
  /// After a successful sign-in, automatically adds the Google email as a
  /// calendar connection (if not already present) so the user doesn't have
  /// to manually add it in Settings.
  Future<void> signInWithGoogle() async {
    state = AuthStatus.loading;
    try {
      final user = await _service.signInWithGoogle();
      _userController.state = user;
      state = AuthStatus.authenticated;

      // Auto-add the Google sign-in email as a calendar connection.
      if (user.email.isNotEmpty) {
        try {
          await _ref
              .read(googleCalendarConnectionsProvider.notifier)
              .ensureConnection(userId: user.uid, email: user.email);
        } catch (_) {
          // Non-fatal: the user can still add it manually from Settings.
        }
      }
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

  /// Allows external callers (e.g. session hydration) to update the auth
  /// status without going through a full sign-in flow.
  void setStatus(AuthStatus newStatus) {
    state = newStatus;
  }

  /// Signs out of Firebase Auth and clears local user and couple state.
  Future<void> signOut() async {
    await _service.signOut();
    _userController.state = null;
    _ref.read(currentCoupleProvider.notifier).state = null;
    state = AuthStatus.unauthenticated;
  }
}

/// Provider that exposes [AuthNotifier] and its [AuthStatus].
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthStatus>((ref) {
  return AuthNotifier(
    ref.watch(authServiceProvider),
    ref.read(currentUserProvider.notifier),
    ref,
  );
});
