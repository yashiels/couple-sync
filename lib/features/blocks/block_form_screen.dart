import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/time_block_model.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/block_providers.dart';
import '../../shared/providers/pairing_providers.dart';

class BlockFormScreen extends ConsumerStatefulWidget {
  final String? editingBlockId;
  const BlockFormScreen({super.key, this.editingBlockId});

  @override
  ConsumerState<BlockFormScreen> createState() => _BlockFormScreenState();
}

class _BlockFormScreenState extends ConsumerState<BlockFormScreen> {
  final _titleController = TextEditingController();
  static final _timeFmt = DateFormat('EEE d MMM, HH:mm');
  bool _loadingBlock = false;

  @override
  void initState() {
    super.initState();
    if (widget.editingBlockId != null) {
      _loadExistingBlock();
    }
  }

  Future<void> _loadExistingBlock() async {
    final couple = ref.read(currentCoupleProvider);
    if (couple == null || widget.editingBlockId == null) return;

    setState(() => _loadingBlock = true);
    try {
      final block = await ref
          .read(blockServiceProvider)
          .getBlock(couple.coupleId, widget.editingBlockId!);
      if (block != null && mounted) {
        ref.read(blockFormProvider.notifier).prefillFromBlock(block);
        _titleController.text = block.title;
      }
    } catch (_) {
      // Block fetch failed
    } finally {
      if (mounted) setState(() => _loadingBlock = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// Shows iOS-style date+time picker in a bottom sheet.
  Future<void> _pickDateTime({
    required DateTime? initial,
    required void Function(DateTime) onPicked,
  }) async {
    DateTime selected = initial?.toLocal() ?? DateTime.now();

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.separator,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            SizedBox(
              height: 216,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: selected,
                minimumDate: DateTime.now().subtract(const Duration(days: 1)),
                maximumDate: DateTime.now().add(const Duration(days: 365)),
                onDateTimeChanged: (dt) => selected = dt,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    onPicked(selected.toUtc());
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Confirm'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStart() async {
    final state = ref.read(blockFormProvider);
    await _pickDateTime(
      initial: state.startUtc,
      onPicked: (dt) => ref.read(blockFormProvider.notifier).setStart(dt),
    );
  }

  Future<void> _pickEnd() async {
    final state = ref.read(blockFormProvider);
    final initial = state.endUtc ?? state.startUtc?.add(const Duration(hours: 1));
    await _pickDateTime(
      initial: initial,
      onPicked: (dt) => ref.read(blockFormProvider.notifier).setEnd(dt),
    );
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    final couple = ref.read(currentCoupleProvider);
    if (user == null || couple == null) return;

    final notifier = ref.read(blockFormProvider.notifier);
    notifier.setTitle(_titleController.text);
    await notifier.save(
      coupleId: couple.coupleId,
      userId: user.uid,
      timezone: user.timezone,
      editingBlockId: widget.editingBlockId,
    );
    if (mounted && ref.read(blockFormProvider).error == null) {
      Navigator.of(context).pop();
    }
  }

  void _applyPreset({
    required String title,
    required BlockCategory category,
    required Duration duration,
  }) {
    final notifier = ref.read(blockFormProvider.notifier);
    notifier.setTitle(title);
    notifier.setCategory(category);
    _titleController.text = title;

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour + 1).toUtc();
    notifier.setStart(start);
    notifier.setEnd(start.add(duration));
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(blockFormProvider);
    final user = ref.watch(currentUserProvider);
    final couple = ref.watch(currentCoupleProvider);
    final canSave = user != null && couple != null;

    if (_loadingBlock) {
      return Scaffold(
        backgroundColor: AppColors.groupedBackground,
        appBar: AppBar(
          backgroundColor: AppColors.groupedBackground,
          title: const Text('Edit Block'),
        ),
        body: const Center(child: CupertinoActivityIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.groupedBackground,
      appBar: AppBar(
        backgroundColor: AppColors.groupedBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.editingBlockId != null ? 'Edit Block' : 'Add Block'),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            onPressed: (formState.saving || !canSave) ? null : _save,
            child: Text(
              'Save',
              style: AppTypography.headline.copyWith(
                color: (formState.saving || !canSave)
                    ? AppColors.textTertiary
                    : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick-add presets
            _SectionHeader(title: 'QUICK ADD'),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _PresetPill(
                    label: 'Study',
                    icon: Icons.menu_book_rounded,
                    onTap: () => _applyPreset(
                      title: 'Study',
                      category: BlockCategory.study,
                      duration: const Duration(hours: 2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PresetPill(
                    label: 'Gym',
                    icon: Icons.fitness_center_rounded,
                    onTap: () => _applyPreset(
                      title: 'Gym',
                      category: BlockCategory.exercise,
                      duration: const Duration(hours: 1),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PresetPill(
                    label: 'Commute',
                    icon: Icons.directions_car_rounded,
                    onTap: () => _applyPreset(
                      title: 'Commute',
                      category: BlockCategory.commute,
                      duration: const Duration(minutes: 30),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PresetPill(
                    label: 'Work',
                    icon: Icons.work_rounded,
                    onTap: () => _applyPreset(
                      title: 'Work',
                      category: BlockCategory.work,
                      duration: const Duration(hours: 8),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Form grouped card
            _SectionHeader(title: 'DETAILS'),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText: 'Block title (e.g. Morning Run)',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        hintStyle: AppTypography.body.copyWith(color: AppColors.textTertiary),
                      ),
                      style: AppTypography.body,
                      onChanged: ref.read(blockFormProvider.notifier).setTitle,
                    ),
                  ),
                  const _FormSeparator(),

                  // Start time
                  _FormRow(
                    label: 'Starts',
                    value: formState.startUtc != null
                        ? _timeFmt.format(formState.startUtc!.toLocal())
                        : 'Select',
                    onTap: _pickStart,
                  ),
                  const _FormSeparator(),

                  // End time
                  _FormRow(
                    label: 'Ends',
                    value: formState.endUtc != null
                        ? _timeFmt.format(formState.endUtc!.toLocal())
                        : 'Select',
                    onTap: _pickEnd,
                  ),
                  const _FormSeparator(),

                  // Block type
                  _FormRow(
                    label: 'Type',
                    value: formState.type == BlockType.busy ? 'Busy' : 'Free',
                    onTap: () {
                      final next = formState.type == BlockType.busy
                          ? BlockType.free
                          : BlockType.busy;
                      ref.read(blockFormProvider.notifier).setType(next);
                    },
                  ),
                  const _FormSeparator(),

                  // Visibility
                  _FormRow(
                    label: 'Visibility',
                    value: formState.visibility == TimeBlockVisibility.bothPartners
                        ? 'Both Partners'
                        : 'Only Me',
                    onTap: () {
                      final next =
                          formState.visibility == TimeBlockVisibility.bothPartners
                              ? TimeBlockVisibility.onlyMe
                              : TimeBlockVisibility.bothPartners;
                      ref.read(blockFormProvider.notifier).setVisibility(next);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Category picker
            _SectionHeader(title: 'CATEGORY'),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categoryItems.map((item) {
                  final (cat, icon, label) = item;
                  final isSelected = formState.category == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(blockFormProvider.notifier).setCategory(cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 16,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: AppTypography.subhead.copyWith(
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 32),

            if (formState.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  formState.error!,
                  style: AppTypography.footnote
                      .copyWith(color: AppColors.destructive),
                ),
              ),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (formState.saving || !formState.isValid || !canSave)
                    ? null
                    : _save,
                child: formState.saving
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text('Save Block'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Constants ──────────────────────────────────────────────────────────────────

const _categoryItems = [
  (BlockCategory.work, Icons.work_rounded, 'Work'),
  (BlockCategory.study, Icons.menu_book_rounded, 'Study'),
  (BlockCategory.commute, Icons.directions_car_rounded, 'Commute'),
  (BlockCategory.exercise, Icons.fitness_center_rounded, 'Exercise'),
  (BlockCategory.social, Icons.people_rounded, 'Social'),
  (BlockCategory.meals, Icons.restaurant_rounded, 'Meals'),
  (BlockCategory.sleep, Icons.nightlight_round, 'Sleep'),
  (BlockCategory.personal, Icons.person_rounded, 'Personal'),
  (BlockCategory.other, Icons.more_horiz_rounded, 'Other'),
];

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 2),
      child: Text(
        title,
        style: AppTypography.footnote.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _FormSeparator extends StatelessWidget {
  const _FormSeparator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 16),
      child: Divider(height: 0.33, thickness: 0.33, color: AppColors.separator),
    );
  }
}

class _FormRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _FormRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: AppTypography.body),
            ),
            Text(
              value,
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PresetPill({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.subhead.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
