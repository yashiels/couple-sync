import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/time_block_model.dart';
import '../services/block_service.dart';

/// Singleton [BlockService] instance.
final blockServiceProvider = Provider<BlockService>((ref) => BlockService());

/// Streams all blocks for a specific user within a couple.
final userBlocksProvider = StreamProvider.family<List<TimeBlock>, ({String coupleId, String userId})>((ref, ids) {
  return ref.watch(blockServiceProvider).watchUserBlocks(ids.coupleId, ids.userId);
});

/// Streams all couple blocks for the next 14 days.
final coupleBlocksProvider = StreamProvider.family<List<TimeBlock>, String>((ref, coupleId) {
  final now = DateTime.now().toUtc();
  return ref.watch(blockServiceProvider).watchBlocksInRange(
        coupleId: coupleId,
        fromUtc: now,
        toUtc: now.add(const Duration(days: 14)),
      );
});

/// Ephemeral state for the add/edit block form.
class BlockFormState {
  final String title;
  final BlockType type;
  final BlockCategory category;
  final DateTime? startUtc;
  final DateTime? endUtc;
  final TimeBlockVisibility visibility;
  final String? recurrenceRule;
  final bool saving;
  final String? error;

  const BlockFormState({
    this.title = '',
    this.type = BlockType.busy,
    this.category = BlockCategory.other,
    this.startUtc,
    this.endUtc,
    this.visibility = TimeBlockVisibility.bothPartners,
    this.recurrenceRule,
    this.saving = false,
    this.error,
  });

  /// `true` when all required fields are filled and the time range is valid.
  bool get isValid =>
      title.isNotEmpty && startUtc != null && endUtc != null && endUtc!.isAfter(startUtc!);

  /// Returns a copy of this state with the given fields replaced.
  BlockFormState copyWith({
    String? title,
    BlockType? type,
    BlockCategory? category,
    DateTime? startUtc,
    DateTime? endUtc,
    TimeBlockVisibility? visibility,
    String? recurrenceRule,
    bool? saving,
    String? error,
  }) {
    return BlockFormState(
      title: title ?? this.title,
      type: type ?? this.type,
      category: category ?? this.category,
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      visibility: visibility ?? this.visibility,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      saving: saving ?? this.saving,
      error: error ?? this.error,
    );
  }
}

/// Manages the block creation / edit form, including persistence via
/// [BlockService].
class BlockFormNotifier extends StateNotifier<BlockFormState> {
  final BlockService _service;

  BlockFormNotifier(this._service) : super(const BlockFormState());

  /// Updates the title field.
  void setTitle(String v) => state = state.copyWith(title: v);

  /// Updates the block type.
  void setType(BlockType v) => state = state.copyWith(type: v);

  /// Updates the block category.
  void setCategory(BlockCategory v) => state = state.copyWith(category: v);

  /// Updates the start time.
  void setStart(DateTime v) => state = state.copyWith(startUtc: v);

  /// Updates the end time.
  void setEnd(DateTime v) => state = state.copyWith(endUtc: v);

  /// Updates the visibility setting.
  void setVisibility(TimeBlockVisibility v) => state = state.copyWith(visibility: v);

  /// Updates the optional RFC 5545 recurrence rule.
  void setRecurrenceRule(String? v) => state = state.copyWith(recurrenceRule: v);

  /// Pre-fills the form with data from an existing [block] for editing.
  void prefillFromBlock(TimeBlock block) {
    state = BlockFormState(
      title: block.title,
      type: block.type,
      category: block.category,
      startUtc: block.startUtc,
      endUtc: block.endUtc,
      visibility: block.visibility,
      recurrenceRule: block.recurrenceRule,
    );
  }

  /// Persists the form as a new or updated block.
  ///
  /// Pass [editingBlockId] to update an existing block; omit to create.
  Future<void> save({
    required String coupleId,
    required String userId,
    required String timezone,
    String? editingBlockId,
  }) async {
    if (!state.isValid) return;
    state = state.copyWith(saving: true, error: null);
    try {
      if (editingBlockId != null) {
        final existing = await _service.getBlock(coupleId, editingBlockId);
        if (existing != null) {
          await _service.updateBlock(
            coupleId,
            existing.copyWith(
              title: state.title,
              type: state.type,
              category: state.category,
              startUtc: state.startUtc,
              endUtc: state.endUtc,
              visibility: state.visibility,
              recurrenceRule: state.recurrenceRule,
            ),
          );
        }
      } else {
        await _service.createBlock(
          coupleId: coupleId,
          userId: userId,
          title: state.title,
          type: state.type,
          startUtc: state.startUtc!,
          endUtc: state.endUtc!,
          timezone: timezone,
          category: state.category,
          visibility: state.visibility,
          recurrenceRule: state.recurrenceRule,
        );
      }
      state = const BlockFormState();
    } catch (e) {
      state = state.copyWith(saving: false, error: e.toString());
    }
  }
}

/// Auto-disposed provider for the add/edit block form notifier.
final blockFormProvider = StateNotifierProvider.autoDispose<BlockFormNotifier, BlockFormState>((ref) {
  return BlockFormNotifier(ref.watch(blockServiceProvider));
});
