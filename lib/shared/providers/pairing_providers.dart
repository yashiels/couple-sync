import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/couple_model.dart';
import '../services/pairing_service.dart';

final pairingServiceProvider = Provider<PairingService>((ref) => PairingService());

// Current couple model
final currentCoupleProvider = StateProvider<CoupleModel?>((ref) => null);

// Active invite code for the current user
final activeInviteCodeProvider = FutureProvider.family<String?, String>((ref, uid) async {
  final service = ref.watch(pairingServiceProvider);
  final invite = await service.getActiveInviteForUser(uid);
  return invite?.code;
});

// Pairing operation state
enum PairingStatus { idle, loading, success, error }

class PairingNotifier extends StateNotifier<PairingStatus> {
  final PairingService _service;
  final StateController<CoupleModel?> _coupleController;

  PairingNotifier(this._service, this._coupleController) : super(PairingStatus.idle);

  String? lastError;
  CoupleModel? lastCouple;

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

  Future<CoupleModel> redeemCode({
    required String code,
    required String redeemerUid,
  }) async {
    state = PairingStatus.loading;
    try {
      final couple = await _service.redeemInviteCode(code: code, redeemerUid: redeemerUid);
      _coupleController.state = couple;
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

final pairingNotifierProvider = StateNotifierProvider<PairingNotifier, PairingStatus>((ref) {
  return PairingNotifier(
    ref.watch(pairingServiceProvider),
    ref.read(currentCoupleProvider.notifier),
  );
});
