import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/models/user_model.dart';
import '../auth_service.dart';
import 'sync_provider.dart';

/// Authentication state that tracks user and profile data for routing decisions.
class AuthState {
  final User? firebaseUser;
  final UserModel? userProfile;
  final bool isLoading;

  const AuthState({this.firebaseUser, this.userProfile, this.isLoading = true});

  /// Whether the user is authenticated (has Firebase user)
  bool get isAuthenticated => firebaseUser != null;

  /// Whether the user has set their timezone
  bool get hasTimezone => userProfile?.timezone.isNotEmpty ?? false;

  /// Whether the user is paired with a couple
  bool get hasCouple => userProfile?.coupleId != null;

  /// User's UID or null if not authenticated
  String? get uid => firebaseUser?.uid;

  /// Convenience getter for the user profile
  UserModel? get profile => userProfile;

  AuthState copyWith({
    User? firebaseUser,
    UserModel? userProfile,
    bool? isLoading,
    bool clearFirebaseUser = false,
    bool clearUserProfile = false,
  }) {
    return AuthState(
      firebaseUser: clearFirebaseUser
          ? null
          : (firebaseUser ?? this.firebaseUser),
      userProfile: clearUserProfile ? null : (userProfile ?? this.userProfile),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  String toString() =>
      'AuthState(isAuthenticated: $isAuthenticated, '
      'hasTimezone: $hasTimezone, hasCouple: $hasCouple, isLoading: $isLoading)';
}

/// Notifier that manages authentication state by listening to Firebase Auth
/// and fetching user profile data from Firestore.
class AuthStateNotifier extends StateNotifier<AuthState> {
  final FirebaseAuth _auth;
  final AuthService _authService;
  final Future<UserModel?> Function(String uid) _fetchProfile;
  final Duration _profileRetryDelay;

  String? _lastError;
  StreamSubscription<User?>? _authStateSubscription;

  AuthStateNotifier({
    FirebaseAuth? auth,
    required AuthService authService,
    required Future<UserModel?> Function(String uid) fetchProfile,
    Duration profileRetryDelay = const Duration(milliseconds: 1500),
  }) : _auth = auth ?? FirebaseAuth.instance,
       _authService = authService,
       _fetchProfile = fetchProfile,
       _profileRetryDelay = profileRetryDelay,
       super(const AuthState()) {
    _init();
  }

  void _init() {
    // Listen to Firebase Auth state changes
    _authStateSubscription = _auth.authStateChanges().listen((user) async {
      if (user == null) {
        // User signed out - clear profile and reset state
        state = const AuthState(
          firebaseUser: null,
          userProfile: null,
          isLoading: false,
        );
        return;
      }

      // User signed in - update Firebase user and fetch profile
      state = state.copyWith(firebaseUser: user, isLoading: true);

      await _fetchUserProfile(user.uid);
    });
  }

  /// Fetches the user profile from the backend (GET /users/me via
  /// [SyncService]) and updates state. Retries once after a short delay if the
  /// profile is not yet present (handles the race with the /auth/verify upsert
  /// during initial sign-in).
  Future<void> _fetchUserProfile(String uid, {bool isRetry = false}) async {
    try {
      final profile = await _fetchProfile(uid);

      if (profile != null) {
        state = state.copyWith(userProfile: profile, isLoading: false);
      } else if (!isRetry) {
        // Profile may still be creating — retry once after a short delay.
        await Future.delayed(_profileRetryDelay);
        return _fetchUserProfile(uid, isRetry: true);
      } else {
        // No profile after retry - user needs onboarding.
        state = state.copyWith(userProfile: null, isLoading: false);
      }
    } catch (e) {
      // Error fetching profile - keep authenticated but no profile.
      state = state.copyWith(userProfile: null, isLoading: false);
    }
  }

  /// Manually refresh the user profile from the backend.
  Future<void> refreshProfile() async {
    final uid = state.uid;
    if (uid != null) {
      state = state.copyWith(isLoading: true);
      await _fetchUserProfile(uid);
    }
  }

  /// Sign in with Google.
  /// Returns true on success, false on failure.
  /// Check [lastError] for error message on failure.
  Future<bool> signInWithGoogle() async {
    try {
      _lastError = null;
      await _authService.signInWithGoogle();
      return true;
    } on AuthException catch (e) {
      _lastError = e.message;
      return false;
    }
  }

  /// Sign in with Apple.
  /// Returns true on success, false on failure.
  /// Check [lastError] for error message on failure.
  Future<bool> signInWithApple() async {
    try {
      _lastError = null;
      await _authService.signInWithApple();
      return true;
    } on AuthException catch (e) {
      _lastError = e.message;
      return false;
    }
  }

  /// Sign in (or create) a user with email + password. Dev-only path.
  /// Returns true on success, false on failure. Check [lastError].
  Future<bool> signInWithEmail(String email, String password) async {
    try {
      _lastError = null;
      await _authService.signInWithEmail(email, password);
      return true;
    } on AuthException catch (e) {
      _lastError = e.message;
      return false;
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    try {
      _lastError = null;
      await _authService.signOut();
    } on AuthException catch (e) {
      _lastError = e.message;
    }
  }

  /// Get the last error message, or null if no error.
  String? get lastError => _lastError;

  /// Clear the last error message.
  void clearError() {
    _lastError = null;
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}

/// Single shared [GoogleSignIn] instance used by both [AuthService] and
/// [CalendarService].  Sharing one instance prevents the platform-channel
/// collision that occurs when one service calls [signOut] and inadvertently
/// invalidates another service's session.
final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/calendar.readonly'],
  );
});

/// Provider for the AuthService.
/// Use this for direct access to auth operations.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    googleSignIn: ref.watch(googleSignInProvider),
    syncService: ref.watch(syncServiceProvider),
  );
});

/// Provider for authentication state.
/// Use this in guards and UI to check auth status, timezone, and couple pairing.
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  final sync = ref.watch(syncServiceProvider);
  return AuthStateNotifier(
    authService: ref.watch(authServiceProvider),
    fetchProfile: (uid) => sync.getUser(uid),
  );
});

/// Convenience provider to get current user ID.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).uid;
});

/// Convenience provider to get current user profile.
final currentUserProfileProvider = Provider<UserModel?>((ref) {
  return ref.watch(authStateProvider).userProfile;
});
