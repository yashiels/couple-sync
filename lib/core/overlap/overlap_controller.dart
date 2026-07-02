import 'dart:async';
import 'dart:convert';

import 'package:couple_sync/core/models/models.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';
import 'package:couple_sync/services/sync_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers/auth_state_provider.dart';
import '../../services/providers/sync_provider.dart';

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
/// produce the same hash, so the two-writer race is benign — the server
/// dedups on `inputHash` in [SyncService.publishOverlap].
String computeOverlapInputHash({
  required List<TimeBlock> blocksA,
  required List<TimeBlock> blocksB,
  required String tzA,
  required String tzB,
  required PartnerPrefs prefsA,
  required PartnerPrefs prefsB,
  required int nowBucket,
}) {
  final sortedA = [...blocksA]
    ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  final sortedB = [...blocksB]
    ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
  final a = sortedA
      .map(
        (b) =>
            '${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type.name}',
      )
      .join('|');
  final b = sortedB
      .map(
        (b) =>
            '${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type.name}',
      )
      .join('|');
  final str =
      '$a#$b#$tzA#$tzB#${prefsA.showLateNightWindows}#'
      '${prefsB.showLateNightWindows}#$kAlgoVersion#$nowBucket';
  return sha256.convert(utf8.encode(str)).toString().substring(0, 16);
}

/// Floor `ms` (UTC milliseconds since epoch) down to the start of its hour.
/// Used to bucket both devices into the same compute window when they fire
/// within the same wall-clock hour.
int floorToHour(int ms) => (ms ~/ (60 * 60 * 1000)) * (60 * 60 * 1000);

/// Riverpod controller that recomputes the overlap whenever either partner's
/// blocks change, then publishes the result via [SyncService.publishOverlap]
/// (a WebSocket `overlap` message). The server dedups on `inputHash` and pushes
/// FCM to the offline partner, so the two-writer race between devices is
/// benign.
///
/// Partner profiles (tz + showLateNightWindows) are fetched on demand from the
/// backend via [SyncService.getUserByUid] when the couple is resolved. The pure
/// helpers ([computeOverlapInputHash], [floorToHour]) are unit-tested in
/// `test/core/overlap/overlap_controller_test.dart`.
class OverlapController
    extends AutoDisposeFamilyAsyncNotifier<OverlapResult, String> {
  Timer? _debounce;
  Timer? _profilePoll;
  StreamSubscription<List<TimeBlock>>? _blocksSub;

  /// Latest blocks + prefs snapshot. Updated by each stream callback; the
  /// debounced compute reads from here so a flurry of events collapses to one
  /// recomputation.
  List<TimeBlock> _blocksA = const [];
  List<TimeBlock> _blocksB = const [];
  PartnerInput? _inputA;
  PartnerInput? _inputB;
  String? _userAUid;
  String? _userBUid;

  /// Last `inputHash` published by this controller. Skips a redundant publish
  /// when the inputs have not changed.
  String? _lastWrittenHash;

  static const Duration _debounceDelay = Duration(milliseconds: 500);

  @override
  Future<OverlapResult> build(String coupleId) {
    ref.onDispose(() {
      _debounce?.cancel();
      _blocksSub?.cancel();
      _profilePoll?.cancel();
    });

    final sync = ref.watch(syncServiceProvider);
    final myUid = ref.watch(currentUserIdProvider);

    // Resolve the couple doc to learn userAUid/userBUid, then fetch each
    // partner's profile. Re-run on a short poll so a freshly-paired partner
    // is picked up without a full restart.
    _resolveCoupleAndProfiles(sync, coupleId, myUid);
    _profilePoll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _resolveCoupleAndProfiles(sync, coupleId, myUid),
    );

    // Watch all blocks for the couple; partition by userId before computing.
    _blocksSub = sync.watchBlocks(coupleId).listen((blocks) {
      final a = _userAUid;
      final b = _userBUid;
      _blocksA = a == null
          ? const []
          : blocks.where((bl) => bl.userId == a).toList();
      _blocksB = b == null
          ? const []
          : blocks.where((bl) => bl.userId == b).toList();
      _scheduleCompute(sync, coupleId, myUid);
    });

    // Initial idle state — real value arrives once streams fire.
    return Future.value(
      OverlapResult(
        windows: const [],
        computedAt: DateTime.now().toUtc(),
        inputHash: '',
      ),
    );
  }

  Future<void> _resolveCoupleAndProfiles(
    SyncService sync,
    String coupleId,
    String? myUid,
  ) async {
    try {
      final couple = await sync.getCouple(coupleId);
      if (couple == null) return;
      final userAUid = couple.userAUid;
      final userBUid = couple.userBUid;
      if (userAUid == _userAUid && userBUid == _userBUid) return;
      _userAUid = userAUid;
      _userBUid = userBUid;

      final futureA = sync.getUserByUid(userAUid);
      final futureB = sync.getUserByUid(userBUid);
      final results = await Future.wait([futureA, futureB]);
      if (results[0] != null) {
        _inputA = PartnerInput(
          timezone: results[0]!.timezone,
          showLateNightWindows: results[0]!.showLateNightWindows,
        );
      }
      if (results[1] != null) {
        _inputB = PartnerInput(
          timezone: results[1]!.timezone,
          showLateNightWindows: results[1]!.showLateNightWindows,
        );
      }
      _scheduleCompute(sync, coupleId, myUid);
    } catch (_) {
      // Couple/profile fetch failed — the blocks stream will still recompute
      // from the cache; the next poll will retry.
    }
  }

  void _scheduleCompute(SyncService sync, String coupleId, String? myUid) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _compute(sync, coupleId, myUid));
  }

  Future<void> _compute(
    SyncService sync,
    String coupleId,
    String? myUid,
  ) async {
    final a = _inputA;
    final b = _inputB;
    if (a == null || b == null) return; // wait for both profiles
    if (myUid == null) return;

    final nowBucket = floorToHour(
      DateTime.now().toUtc().millisecondsSinceEpoch,
    );
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
      computedBy: myUid,
    );
    state = AsyncData(result);

    // Skip the publish if our locally-computed hash matches the last one we
    // sent. The server also re-checks the stored hash, so a race between the
    // two devices is still safe even if both pass this guard.
    if (hash == _lastWrittenHash) return;
    try {
      await sync.publishOverlap(coupleId, result);
      _lastWrittenHash = hash;
    } catch (_) {
      // Swallow publish errors; the next debounce will retry. The state has
      // already been set to the freshly computed value.
    }
  }
}

/// Family provider: `ref.watch(overlapControllerProvider(coupleId))` returns
/// `AsyncValue<OverlapResult>` for the given couple. Auto-disposed so the
/// stream subscriptions are cancelled when no screen is watching.
final overlapControllerProvider =
    AutoDisposeAsyncNotifierProviderFamily<
      OverlapController,
      OverlapResult,
      String
    >(OverlapController.new);
