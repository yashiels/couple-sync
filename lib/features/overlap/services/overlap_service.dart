import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/overlap_window_model.dart';

/// Reads overlap windows from Firestore and provides mark-as-seen helpers.
///
/// Firestore path: `overlaps/{coupleId}/windows/latest`
class OverlapService {
  final FirebaseFirestore _firestore;

  const OverlapService(this._firestore);

  DocumentReference<Map<String, dynamic>> _latestDoc(String coupleId) => _firestore
      .collection('overlaps')
      .doc(coupleId)
      .collection('windows')
      .doc('latest');

  /// Real-time stream of the latest overlap windows document.
  Stream<OverlapWindowsDoc?> watchWindows(String coupleId) {
    return _latestDoc(coupleId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return OverlapWindowsDoc.fromSnapshot(snap);
    });
  }

  /// Fetch windows once (e.g. for background processing).
  Future<OverlapWindowsDoc?> fetchWindows(String coupleId) async {
    final snap = await _latestDoc(coupleId).get();
    if (!snap.exists) return null;
    return OverlapWindowsDoc.fromSnapshot(snap);
  }

  /// Mark all current windows as seen by patching the `seen` flag on each
  /// array element. We rewrite the full windows array to keep the operation
  /// atomic — Firestore does not support nested array-element updates.
  Future<void> markAllSeen(String coupleId) async {
    final doc = await fetchWindows(coupleId);
    if (doc == null || doc.windows.isEmpty) return;

    final updated = doc.windows.map((w) => w.copyWith(seen: true).toMap()).toList();
    await _latestDoc(coupleId).update({'windows': updated});
  }

  /// Mark a single window as seen, identified by its [startUtc] timestamp.
  Future<void> markSeen(String coupleId, DateTime startUtc) async {
    final doc = await fetchWindows(coupleId);
    if (doc == null) return;

    final updated = doc.windows.map((w) {
      if (w.startUtc == startUtc) return w.copyWith(seen: true).toMap();
      return w.toMap();
    }).toList();

    await _latestDoc(coupleId).update({'windows': updated});
  }
}
