import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_sync/core/models/models.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/firestore_service.dart';
import '../../services/providers/auth_state_provider.dart';
import '../../services/providers/firestore_provider.dart';

/// Per-partner inputs needed to compute an overlap. Mirrors the fields used by
/// [computeOverlap] and [computeOverlapInputHash] for one partner.
class PartnerInput {
  final String timezone;
  final bool showLateNightWindows;
  const PartnerInput({
    required this.timezone,
    required this.showLateNightWindows,
  });
}

/// Computes inputHash over all overlap inputs (blocks + tz + prefs + algo +
/// nowBucket). Copies the block lists before sorting so callers' lists are
/// not mutated.
///
/// `inputHash = sha256(blocksA ‖ blocksB ‖ tzA ‖ tzB ‖ prefsA ‖ prefsB ‖
/// kAlgoVersion ‖ nowBucket).slice(0,16)`. Both devices in the same hour
/// produce the same hash, so the two-writer race in [FirestoreService
/// .writeOverlapTransaction] is benign.
String computeOverlapInputHash({
  required List<TimeBlock> blocksA,
  required List<TimeBlock> blocksB,
  required String tzA,
  required String tzB,
  required PartnerPrefs prefsA,
  required PartnerPrefs prefsB,
  required int nowBucket,
}) {
  final sortedA = [...blocksA]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  final sortedB = [...blocksB]..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  final a = sortedA
      .map((b) =>
          '${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type.name}')
      .join('|');
  final b = sortedB
      .map((b) =>
          '${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type.name}')
      .join('|');
  final str = '$a#$b#$tzA#$tzB#${prefsA.showLateNightWindows}#'
      '${prefsB.showLateNightWindows}#$kAlgoVersion#$nowBucket';
  return sha256.convert(utf8.encode(str)).toString().substring(0, 16);
}

/// Floor `ms` (UTC milliseconds since epoch) down to the start of its hour.
/// Used to bucket both devices into the same compute window when they fire
/// within the same wall-clock hour.
int floorToHour(int ms) => (ms ~/ (60 * 60 * 1000)) * (60 * 60 * 1000);

/// Riverpod controller that recomputes the overlap whenever either partner's
/// blocks or profile change, then writes the result via a Firestore
/// transaction. The transaction skips the write if the stored `inputHash`
/// already matches, so the two-writer race between devices is benign.
///
/// The pure helpers ([computeOverlapInputHash], [floorToHour]) are unit-tested
/// in `test/core/overlap/overlap_controller_test.dart`. The stream wiring here
/// is integration code covered end-to-end by the A11 smoke test.
class OverlapController extends FamilyAsyncNotifier<OverlapResult, String> {
  Timer? _debounce;
  StreamSubscription<List<TimeBlock>>? _blocksSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userASub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userBSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _coupleSub;

  /// Latest blocks + prefs snapshot. Updated by each stream callback; the
  /// debounced compute reads from here so a flurry of events collapses to one
  /// recomputation.
  List<TimeBlock> _blocksA = const [];
  List<TimeBlock> _blocksB = const [];
  PartnerInput? _inputA;
  PartnerInput? _inputB;
  String? _userAUid;
  String? _userBUid;

  /// Last `inputHash` written by this controller. Skips a redundant
  /// transaction write when the inputs have not changed.
  String? _lastWrittenHash;

  static const Duration _debounceDelay = Duration(milliseconds: 500);

  @override
  Future<OverlapResult> build(String coupleId) {
    ref.onDispose(() {
      _debounce?.cancel();
      _blocksSub?.cancel();
      _userASub?.cancel();
      _userBSub?.cancel();
      _coupleSub?.cancel();
    });

    final firestore = ref.watch(firestoreServiceProvider);
    final myUid = ref.watch(currentUserIdProvider);

    // Watch the couple doc to resolve userAUid/userBUid and re-subscribe to
    // each partner's profile when membership changes.
    _coupleSub = firestore
        .getCoupleStream(coupleId)
        .listen((snap) => _onCoupleDoc(firestore, coupleId, snap, myUid));

    // Watch all blocks for the couple; partition by userId before computing.
    _blocksSub = firestore.watchBlocks(coupleId).listen((blocks) {
      final a = _userAUid;
      final b = _userBUid;
      _blocksA = a == null ? const [] : blocks.where((bl) => bl.userId == a).toList();
      _blocksB = b == null ? const [] : blocks.where((bl) => bl.userId == b).toList();
      _scheduleCompute(firestore, coupleId, myUid);
    });

    // Initial idle state — real value arrives once streams fire.
    return Future.value(OverlapResult(
      windows: const [],
      computedAt: DateTime.now().toUtc(),
      inputHash: '',
    ));
  }

  void _onCoupleDoc(
    FirestoreService firestore,
    String coupleId,
    DocumentSnapshot<Map<String, dynamic>> snap,
    String? myUid,
  ) {
    if (!snap.exists) return;
    final data = snap.data()!;
    final userAUid = data['userAUid'] as String?;
    final userBUid = data['userBUid'] as String?;
    if (userAUid == _userAUid && userBUid == _userBUid) return;
    _userAUid = userAUid;
    _userBUid = userBUid;

    _userASub?.cancel();
    _userBSub?.cancel();
    if (userAUid != null) {
      _userASub = firestore
          .getUserStream(userAUid)
          .listen((s) => _onUserDoc(0, s, myUid, firestore, coupleId));
    }
    if (userBUid != null) {
      _userBSub = firestore
          .getUserStream(userBUid)
          .listen((s) => _onUserDoc(1, s, myUid, firestore, coupleId));
    }
    _scheduleCompute(firestore, coupleId, myUid);
  }

  void _onUserDoc(
    int slot,
    DocumentSnapshot<Map<String, dynamic>> snap,
    String? myUid,
    FirestoreService firestore,
    String coupleId,
  ) {
    if (!snap.exists) return;
    final user = UserModel.fromJson(snap.data()!);
    final input = PartnerInput(
      timezone: user.timezone,
      showLateNightWindows: user.showLateNightWindows,
    );
    if (slot == 0) {
      _inputA = input;
    } else {
      _inputB = input;
    }
    _scheduleCompute(firestore, coupleId, myUid);
  }

  void _scheduleCompute(
    FirestoreService firestore,
    String coupleId,
    String? myUid,
  ) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _compute(firestore, coupleId, myUid));
  }

  Future<void> _compute(
    FirestoreService firestore,
    String coupleId,
    String? myUid,
  ) async {
    final a = _inputA;
    final b = _inputB;
    if (a == null || b == null) return; // wait for both profiles
    if (myUid == null) return;

    final nowBucket =
        floorToHour(DateTime.now().toUtc().millisecondsSinceEpoch);
    final windows = computeOverlap(
      _blocksA,
      _blocksB,
      a.timezone,
      b.timezone,
      nowBucket,
      PartnerPrefs(showLateNightWindows: a.showLateNightWindows),
      PartnerPrefs(showLateNightWindows: b.showLateNightWindows),
    );
    final hash = computeOverlapInputHash(
      blocksA: _blocksA,
      blocksB: _blocksB,
      tzA: a.timezone,
      tzB: b.timezone,
      prefsA: PartnerPrefs(showLateNightWindows: a.showLateNightWindows),
      prefsB: PartnerPrefs(showLateNightWindows: b.showLateNightWindows),
      nowBucket: nowBucket,
    );
    final result = OverlapResult(
      windows: windows,
      computedAt: DateTime.now().toUtc(),
      inputHash: hash,
    );
    state = AsyncData(result);

    // Skip the transaction if our locally-computed hash matches the last one
    // we wrote. The transaction itself also re-checks the stored hash, so a
    // race between the two devices is still safe even if both pass this guard.
    if (hash == _lastWrittenHash) return;
    try {
      final wrote = await firestore.writeOverlapTransaction(
        coupleId,
        result,
        myUid,
      );
      if (wrote) _lastWrittenHash = hash;
    } catch (_) {
      // Swallow write errors; the next debounce will retry. The state has
      // already been set to the freshly computed value.
    }
  }
}

/// Family provider: `ref.watch(overlapControllerProvider(coupleId))` returns
/// `AsyncValue<OverlapResult>` for the given couple.
final overlapControllerProvider =
    AsyncNotifierProviderFamily<OverlapController, OverlapResult, String>(
  OverlapController.new,
);
