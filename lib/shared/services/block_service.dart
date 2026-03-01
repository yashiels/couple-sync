import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/time_block_model.dart';

/// Firestore path: `timeblocks/{coupleId}/blocks/{blockId}`
class BlockService {
  final FirebaseFirestore _db;

  BlockService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _blocksRef(String coupleId) =>
      _db.collection('timeblocks').doc(coupleId).collection('blocks');

  // --- CRUD ---

  Future<TimeBlock> createBlock({
    required String coupleId,
    required String userId,
    required String title,
    required BlockType type,
    required DateTime startUtc,
    required DateTime endUtc,
    required String timezone,
    required BlockCategory category,
    TimeBlockVisibility visibility = TimeBlockVisibility.bothPartners,
    String? recurrenceRule,
  }) async {
    final id = const Uuid().v4();
    final block = TimeBlock(
      id: id,
      userId: userId,
      coupleId: coupleId,
      type: type,
      title: title,
      startUtc: startUtc.toUtc(),
      endUtc: endUtc.toUtc(),
      timezone: timezone,
      recurrenceRule: recurrenceRule,
      source: CalendarSource.manual,
      visibility: visibility,
      category: category,
      createdAt: DateTime.now().toUtc(),
    );
    await _blocksRef(coupleId).doc(id).set(block.toFirestore());
    return block;
  }

  Future<void> updateBlock(String coupleId, TimeBlock block) async {
    await _blocksRef(coupleId).doc(block.id).update(block.toFirestore());
  }

  Future<void> deleteBlock(String coupleId, String blockId) async {
    await _blocksRef(coupleId).doc(blockId).delete();
  }

  // --- Queries ---

  /// Streams all blocks for a couple in a given UTC date range.
  Stream<List<TimeBlock>> watchBlocksInRange({
    required String coupleId,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) {
    return _blocksRef(coupleId)
        .where('startUtc', isGreaterThanOrEqualTo: Timestamp.fromDate(fromUtc))
        .where('startUtc', isLessThan: Timestamp.fromDate(toUtc))
        .orderBy('startUtc')
        .snapshots()
        .map((snap) => snap.docs.map(TimeBlock.fromFirestore).toList());
  }

  /// Streams all blocks for a specific user.
  Stream<List<TimeBlock>> watchUserBlocks(String coupleId, String userId) {
    return _blocksRef(coupleId)
        .where('userId', isEqualTo: userId)
        .orderBy('startUtc')
        .snapshots()
        .map((snap) => snap.docs.map(TimeBlock.fromFirestore).toList());
  }

  /// One-shot fetch for a single block.
  Future<TimeBlock?> getBlock(String coupleId, String blockId) async {
    final doc = await _blocksRef(coupleId).doc(blockId).get();
    if (!doc.exists) return null;
    return TimeBlock.fromFirestore(doc);
  }
}
