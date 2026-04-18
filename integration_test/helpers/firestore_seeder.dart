import 'package:cloud_firestore/cloud_firestore.dart';

/// Seed time blocks for a couple.
Future<List<String>> seedBlocks({
  required String coupleId,
  required String userId,
  required List<Map<String, dynamic>> blocks,
}) async {
  final ids = <String>[];
  final batch = FirebaseFirestore.instance.batch();

  for (final block in blocks) {
    final ref = FirebaseFirestore.instance
        .collection('timeblocks')
        .doc(coupleId)
        .collection('blocks')
        .doc();
    batch.set(ref, {
      ...block,
      'userId': userId,
    });
    ids.add(ref.id);
  }

  await batch.commit();
  return ids;
}

/// Create an invite document.
Future<void> seedInvite({
  required String code,
  required String createdByUid,
}) async {
  await FirebaseFirestore.instance.collection('invites').doc(code).set({
    'createdByUid': createdByUid,
    'status': 'pending',
    'createdAt': DateTime.now().millisecondsSinceEpoch,
    'expiresAt':
        DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
  });
}
