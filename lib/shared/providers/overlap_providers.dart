import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/overlap_window.dart';

/// Streams the pre-computed overlap result document for a couple.
final overlapResultProvider = StreamProvider.family<OverlapResult?, String>((ref, coupleId) {
  return FirebaseFirestore.instance
      .collection('overlapWindows')
      .doc(coupleId)
      .snapshots()
      .map((snap) => snap.exists ? OverlapResult.fromFirestore(snap) : null);
});

/// Convenience provider: just the ranked window list.
final overlapWindowsProvider = Provider.family<List<OverlapWindow>, String>((ref, coupleId) {
  return ref.watch(overlapResultProvider(coupleId)).valueOrNull?.windows ?? [];
});

/// Convenience provider: the top (highest-scored) window, if any.
final topOverlapWindowProvider = Provider.family<OverlapWindow?, String>((ref, coupleId) {
  final windows = ref.watch(overlapWindowsProvider(coupleId));
  return windows.isEmpty ? null : windows.first;
});

/// When the last overlap computation happened.
final overlapComputedAtProvider = Provider.family<DateTime?, String>((ref, coupleId) {
  return ref.watch(overlapResultProvider(coupleId)).valueOrNull?.computedAt;
});
