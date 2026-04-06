import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_model.dart';

/// Authentication state that tracks user and profile data for routing decisions.
class AuthState {
  final User? firebaseUser;
  final UserModel? userProfile;
  final bool isLoading;

  const AuthState({
    this.firebaseUser,
    this.userProfile,
    this.isLoading = true,
  });

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
      firebaseUser: clearFirebaseUser ? null : (firebaseUser ?? this.firebaseUser),
      userProfile: clearUserProfile ? null : (userProfile ?? this.userProfile),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  String toString() => 'AuthState(isAuthenticated: $isAuthenticated, '
      'hasTimezone: $hasTimezone, hasCouple: $hasCouple, isLoading: $isLoading)';
}

/// Notifier that manages authentication state by listening to Firebase Auth
/// and fetching user profile data from Firestore.
class AuthStateNotifier extends StateNotifier<AuthState> {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthStateNotifier({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        super(const AuthState()) {
    _init();
  }

  void _init() {
    // Listen to Firebase Auth state changes
    _auth.authStateChanges().listen((user) async {
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
      state = state.copyWith(
        firebaseUser: user,
        isLoading: true,
      );

      await _fetchUserProfile(user.uid);
    });
  }

  /// Fetches the user profile from Firestore and updates state.
  Future<void> _fetchUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (doc.exists && doc.data() != null) {
        final profile = UserModel.fromJson(doc.data()!);
        state = state.copyWith(
          userProfile: profile,
          isLoading: false,
        );
      } else {
        // No profile document yet - user is authenticated but needs onboarding
        state = state.copyWith(
          userProfile: null,
          isLoading: false,
        );
      }
    } catch (e) {
      // Error fetching profile - keep authenticated but no profile
      state = state.copyWith(
        userProfile: null,
        isLoading: false,
      );
    }
  }

  /// Manually refresh the user profile from Firestore.
  Future<void> refreshProfile() async {
    final uid = state.uid;
    if (uid != null) {
      state = state.copyWith(isLoading: true);
      await _fetchUserProfile(uid);
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _auth.signOut();
  }
}

/// Provider for authentication state.
/// Use this in guards and UI to check auth status, timezone, and couple pairing.
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  return AuthStateNotifier();
});

/// Convenience provider to check if app is loading auth state.
final isLoadingProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isLoading;
});

/// Convenience provider to get current user ID.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).uid;
});

/// Convenience provider to get current user profile.
final currentUserProfileProvider = Provider<UserModel?>((ref) {
  return ref.watch(authStateProvider).userProfile;
});
