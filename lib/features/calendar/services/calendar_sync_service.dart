import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../shared/models/time_block_model.dart';
import 'google_calendar_service.dart';

/// Result of a calendar sync operation.
class SyncResult {
  final int blocksWritten;
  final List<String> errors;
  final DateTime syncedAt;

  const SyncResult({
    required this.blocksWritten,
    required this.errors,
    required this.syncedAt,
  });

  /// `true` when [errors] is non-empty.
  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() =>
      'SyncResult(blocks: $blocksWritten, errors: ${errors.length})';
}

/// Unified sync orchestrator that fetches from connected calendar sources,
/// deduplicates blocks, and writes them to Firestore.
///
/// Call [sync] after the user connects a calendar, on app resume, or on a
/// background timer. Each source's last-sync timestamp is tracked in the
/// user's Firestore document.
class CalendarSyncService {
  CalendarSyncService({
    required GoogleCalendarService googleService,
    FirebaseFirestore? firestore,
  })  : _google = googleService,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final GoogleCalendarService _google;
  final FirebaseFirestore _firestore;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Syncs all connected calendar sources for [userId] in couple [coupleId].
  ///
  /// Pass [syncGoogle] as false to skip Google Calendar.
  /// Returns a [SyncResult] describing what was written and any errors.
  Future<SyncResult> sync({
    required String userId,
    required String coupleId,
    bool syncGoogle = true,
  }) async {
    final allBlocks = <TimeBlock>[];
    final errors = <String>[];

    if (syncGoogle && _google.isConnected) {
      try {
        final blocks = await _google.fetchBusyPeriods(
          userId: userId,
          coupleId: coupleId,
        );
        allBlocks.addAll(blocks);
        await _persistLastSync(userId, BlockSource.google);
        debugPrint('CalendarSyncService: fetched ${blocks.length} Google blocks');
      } catch (e, st) {
        debugPrint('CalendarSyncService Google error: $e\n$st');
        errors.add('Google Calendar: $e');
      }
    }

    final deduplicated = _deduplicate(allBlocks);
    await _writeToFirestore(
      userId: userId,
      coupleId: coupleId,
      blocks: deduplicated,
    );

    return SyncResult(
      blocksWritten: deduplicated.length,
      errors: errors,
      syncedAt: DateTime.now().toUtc(),
    );
  }

  // ── Deduplication ─────────────────────────────────────────────────────────

  /// Removes duplicates by keying on (source, startMs, endMs).
  /// Preserves insertion order, keeping the first occurrence.
  List<TimeBlock> _deduplicate(List<TimeBlock> blocks) {
    final seen = <String>{};
    return blocks.where((b) {
      final key =
          '${b.source.name}_${b.startUtc.millisecondsSinceEpoch}_'
          '${b.endUtc.millisecondsSinceEpoch}';
      return seen.add(key);
    }).toList();
  }

  // ── Firestore write ───────────────────────────────────────────────────────

  Future<void> _writeToFirestore({
    required String userId,
    required String coupleId,
    required List<TimeBlock> blocks,
  }) async {
    final blocksRef = _firestore
        .collection('timeblocks')
        .doc(coupleId)
        .collection('blocks');

    // Firestore batches support up to 500 operations. Delete old calendar
    // blocks and re-insert fresh ones. Split into chunks if needed.
    final stale = await blocksRef
        .where('userId', isEqualTo: userId)
        .where('source', whereIn: [BlockSource.google.name, BlockSource.microsoft.name])
        .get();

    final toDelete = stale.docs.map((d) => d.reference).toList();
    final toWrite = blocks.map((b) {
      return MapEntry(blocksRef.doc(), b.toFirestore());
    }).toList();

    // Chunk deletions + insertions into batches of 400 (safe margin).
    final allOps = [
      ...toDelete.map((ref) => _BatchOp.delete(ref)),
      ...toWrite.map((e) => _BatchOp.set(e.key, e.value)),
    ];

    for (var i = 0; i < allOps.length; i += 400) {
      final chunk = allOps.sublist(
        i,
        (i + 400).clamp(0, allOps.length),
      );
      final batch = _firestore.batch();
      for (final op in chunk) {
        if (op.isDelete) {
          batch.delete(op.ref!);
        } else {
          batch.set(op.ref!, op.data!);
        }
      }
      await batch.commit();
    }
  }

  Future<void> _persistLastSync(String userId, BlockSource source) async {
    await _firestore.collection('users').doc(userId).set(
      {
        'calendarSources': {
          source.name: {
            'provider': source.name,
            'connected': true,
            'lastSync': FieldValue.serverTimestamp(),
          }
        }
      },
      SetOptions(merge: true),
    );
  }
}

/// Internal helper to represent a batch operation uniformly.
class _BatchOp {
  _BatchOp.delete(this.ref)
      : data = null,
        isDelete = true;

  _BatchOp.set(this.ref, this.data)
      : isDelete = false;

  final DocumentReference? ref;
  final Map<String, dynamic>? data;
  final bool isDelete;
}
