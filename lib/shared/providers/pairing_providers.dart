import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/couple_model.dart';
import '../models/user_model.dart';
import '../services/pairing_service.dart';
import 'auth_providers.dart';

/// Singleton [PairingService] instance.
final pairingServiceProvider = Provider<PairingService>((ref) => PairingService());

/// The currently active [CoupleModel], or `null` before pairing.
final currentCoupleProvider = StateProvider<CoupleModel?>((ref) => null);

/// The active invite code for the given user UID, or `null` if none exists.
final activeInviteCodeProvider = FutureProvider.family<String?, String>((ref, uid) async {
  final service = ref.watch(pairingServiceProvider);
  final invite = await service.getActiveInviteForUser(uid);
  return invite?.code;
});

/// Possible states of a pairing operation.
enum PairingStatus { idle, loading, success, error }

/// Manages invite-code generation and redemption, exposing [PairingStatus].
class PairingNotifier extends StateNotifier<PairingStatus> {
  final PairingService _service;
  final StateController<CoupleModel?> _coupleController;
  final StateController<UserModel?> _userController;

  PairingNotifier(this._service, this._coupleController, this._userController)
      : super(PairingStatus.idle);

  /// The last error message, populated on [PairingStatus.error].
  String? lastError;

  /// The couple created after a successful code redemption.
  CoupleModel? lastCouple;

  /// Generates a new invite code for [uid] and returns it.
  Future<String> generateCode(String uid) async {
    state = PairingStatus.loading;
    try {
      final code = await _service.generateInviteCode(uid);
      state = PairingStatus.idle;
      return code;
    } catch (e) {
      lastError = e.toString();
      state = PairingStatus.error;
      rethrow;
    }
  }

  /// Redeems [code] for [redeemerUid] and updates the couple state on success.
  Future<CoupleModel> redeemCode({
    required String code,
    required String redeemerUid,
  }) async {
    state = PairingStatus.loading;
    try {
      final couple = await _service.redeemInviteCode(code: code, redeemerUid: redeemerUid);
      _coupleController.state = couple;
      // Also update currentUserProvider so the rest of the app sees the new coupleId.
      final currentUser = _userController.state;
      if (currentUser != null) {
        _userController.state = UserModel(
          uid: currentUser.uid,
          email: currentUser.email,
          displayName: currentUser.displayName,
          photoUrl: currentUser.photoUrl,
          timezone: currentUser.timezone,
          coupleId: couple.coupleId,
          createdAt: currentUser.createdAt,
          calendarConnections: currentUser.calendarConnections,
        );
      }
      lastCouple = couple;
      state = PairingStatus.success;
      return couple;
    } catch (e) {
      lastError = e.toString();
      state = PairingStatus.error;
      rethrow;
    }
  }
}

/// Provider that exposes [PairingNotifier] and its [PairingStatus].
final pairingNotifierProvider = StateNotifierProvider<PairingNotifier, PairingStatus>((ref) {
  return PairingNotifier(
    ref.watch(pairingServiceProvider),
    ref.read(currentCoupleProvider.notifier),
    ref.read(currentUserProvider.notifier),
  );
});
