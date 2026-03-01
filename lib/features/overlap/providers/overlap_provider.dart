import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/overlap_window_model.dart';
import '../services/overlap_service.dart';

/// Exposes the [OverlapService] as a singleton.
final overlapServiceProvider = Provider<OverlapService>((ref) {
  return OverlapService(FirebaseFirestore.instance);
});

/// Streams the latest overlap windows document for [coupleId].
/// Emits `null` if the document does not yet exist.
final overlapWindowsProvider =
    StreamProvider.family<OverlapWindowsDoc?, String>((ref, coupleId) {
  final service = ref.watch(overlapServiceProvider);
  return service.watchWindows(coupleId);
});

/// Convenience: flat list of [OverlapWindow]s for the given couple.
final overlapWindowListProvider =
    Provider.family<AsyncValue<List<OverlapWindow>>, String>((ref, coupleId) {
  return ref.watch(overlapWindowsProvider(coupleId)).whenData(
        (doc) => doc?.windows ?? [],
      );
});

/// Count of unseen overlap windows (badge counter).
final unseenOverlapCountProvider =
    Provider.family<AsyncValue<int>, String>((ref, coupleId) {
  return ref.watch(overlapWindowListProvider(coupleId)).whenData(
        (windows) => windows.where((w) => !w.seen).length,
      );
});
