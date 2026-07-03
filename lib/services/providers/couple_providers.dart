import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/couple_model.dart';
import '../../core/models/overlap_result.dart';
import '../../core/models/time_block.dart';
import '../../core/models/user_model.dart';
import 'auth_state_provider.dart';
import 'sync_provider.dart';

/// Fetches the current user's couple document.
/// Returns null if the user has no coupleId set on their profile.
final coupleProvider = FutureProvider<CoupleModel?>((ref) {
  final profile = ref.watch(currentUserProfileProvider);
  if (profile?.coupleId == null) return null;
  return ref.watch(syncServiceProvider).getCouple(profile!.coupleId!);
});

/// Fetches the partner's user profile.
/// Returns null if the couple document is not loaded or the current user ID is unavailable.
final partnerProfileProvider = FutureProvider<UserModel?>((ref) {
  final couple = ref.watch(coupleProvider).valueOrNull;
  final myUid = ref.watch(currentUserIdProvider);
  if (couple == null || myUid == null) return null;
  final partnerId = couple.userAUid == myUid
      ? couple.userBUid
      : couple.userAUid;
  return ref.watch(syncServiceProvider).getUserByUid(partnerId);
});

/// Real-time stream of the current user's time blocks.
/// Returns an empty list if the user has no coupleId or user ID.
final userBlocksProvider = StreamProvider<List<TimeBlock>>((ref) {
  final profile = ref.watch(currentUserProfileProvider);
  final myUid = ref.watch(currentUserIdProvider);
  if (profile?.coupleId == null || myUid == null) return Stream.value([]);
  return ref
      .watch(syncServiceProvider)
      .watchBlocks(profile!.coupleId!, userId: myUid);
});

/// Real-time stream of the partner's time blocks.
/// Returns an empty list if the couple document is not loaded or the current user ID is unavailable.
final partnerBlocksProvider = StreamProvider<List<TimeBlock>>((ref) {
  final couple = ref.watch(coupleProvider).valueOrNull;
  final profile = ref.watch(currentUserProfileProvider);
  final myUid = ref.watch(currentUserIdProvider);
  if (couple == null || myUid == null || profile?.coupleId == null) {
    return Stream.value([]);
  }
  final partnerId = couple.userAUid == myUid
      ? couple.userBUid
      : couple.userAUid;
  return ref
      .watch(syncServiceProvider)
      .watchBlocks(profile!.coupleId!, userId: partnerId);
});

/// Real-time stream of overlap computation results.
/// Returns null if the user has no coupleId set on their profile.
final overlapWindowsProvider = StreamProvider<OverlapResult?>((ref) {
  final profile = ref.watch(currentUserProfileProvider);
  if (profile?.coupleId == null) return Stream.value(null);
  return ref.watch(syncServiceProvider).watchOverlap(profile!.coupleId!);
});
