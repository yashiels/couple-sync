import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/time_block_model.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/block_providers.dart';
import '../../shared/providers/pairing_providers.dart';

/// Form screen for creating a new block or editing an existing one.
///
/// Pass [editingBlockId] to pre-fill the form with the existing block's data.
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
      // Block fetch failed — form stays empty
    } finally {
      if (mounted) setState(() => _loadingBlock = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final state = ref.read(blockFormProvider);
    final date = await _pickDate(initial: state.startUtc);
    if (date == null || !mounted) return;
    final time = await _pickTime(initial: state.startUtc);
    if (time == null || !mounted) return;
    final dt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute)
            .toUtc();
    ref.read(blockFormProvider.notifier).setStart(dt);
  }

  Future<void> _pickEnd() async {
    final state = ref.read(blockFormProvider);
    final initial = state.startUtc?.add(const Duration(hours: 1));
    final date = await _pickDate(initial: initial);
    if (date == null || !mounted) return;
    final time = await _pickTime(initial: initial);
    if (time == null || !mounted) return;
    final dt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute)
            .toUtc();
    ref.read(blockFormProvider.notifier).setEnd(dt);
  }

  Future<DateTime?> _pickDate({DateTime? initial}) async {
    return showDatePicker(
      context: context,
      initialDate: initial?.toLocal() ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
  }

  Future<TimeOfDay?> _pickTime({DateTime? initial}) async {
    return showTimePicker(
      context: context,
      initialTime: initial != null
          ? TimeOfDay.fromDateTime(initial.toLocal())
          : TimeOfDay.now(),
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

  /// Pre-fills the form with a preset: sets title, category, and duration.
  void _applyPreset({
    required String title,
    required BlockCategory category,
    required Duration duration,
  }) {
    final notifier = ref.read(blockFormProvider.notifier);
    notifier.setTitle(title);
    notifier.setCategory(category);
    _titleController.text = title;

    // Pre-fill start to the next round hour and end based on duration.
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
        appBar: AppBar(title: const Text('Edit Block')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.editingBlockId != null ? 'Edit Block' : 'Add Block'),
        actions: [
          TextButton(
            onPressed: (formState.saving || !canSave) ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick-add presets row
            _Label(text: 'Quick Add'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PresetChip(
                  label: 'Study',
                  icon: Icons.menu_book_rounded,
                  onTap: () => _applyPreset(
                    title: 'Study',
                    category: BlockCategory.study,
                    duration: const Duration(hours: 2),
                  ),
                ),
                _PresetChip(
                  label: 'Gym',
                  icon: Icons.fitness_center_rounded,
                  onTap: () => _applyPreset(
                    title: 'Gym',
                    category: BlockCategory.exercise,
                    duration: const Duration(hours: 1),
                  ),
                ),
                _PresetChip(
                  label: 'Commute',
                  icon: Icons.directions_car_rounded,
                  onTap: () => _applyPreset(
                    title: 'Commute',
                    category: BlockCategory.commute,
                    duration: const Duration(minutes: 30),
                  ),
                ),
                _PresetChip(
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
            const SizedBox(height: 20),

            // Title
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Block title (e.g. Morning Run)',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              onChanged: ref.read(blockFormProvider.notifier).setTitle,
            ),
            const SizedBox(height: 20),

            // Type toggle
            _Label(text: 'Block Type'),
            const SizedBox(height: 8),
            SegmentedButton<BlockType>(
              segments: const [
                ButtonSegment(
                  value: BlockType.busy,
                  label: Text('Busy'),
                  icon: Icon(Icons.block_rounded),
                ),
                ButtonSegment(
                  value: BlockType.free,
                  label: Text('Free'),
                  icon: Icon(Icons.check_circle_outline_rounded),
                ),
              ],
              selected: {formState.type},
              onSelectionChanged: (s) =>
                  ref.read(blockFormProvider.notifier).setType(s.first),
            ),
            const SizedBox(height: 20),

            // Category picker
            _Label(text: 'Category'),
            const SizedBox(height: 8),
            _CategoryPicker(
              selected: formState.category,
              onSelect: ref.read(blockFormProvider.notifier).setCategory,
            ),
            const SizedBox(height: 20),

            // Start time
            _Label(text: 'Start Time'),
            const SizedBox(height: 8),
            _TimeTile(
              icon: Icons.play_circle_outline_rounded,
              label: formState.startUtc != null
                  ? _timeFmt.format(formState.startUtc!.toLocal())
                  : 'Tap to set start time',
              onTap: _pickStart,
            ),
            const SizedBox(height: 12),

            // End time
            _Label(text: 'End Time'),
            const SizedBox(height: 8),
            _TimeTile(
              icon: Icons.stop_circle_outlined,
              label: formState.endUtc != null
                  ? _timeFmt.format(formState.endUtc!.toLocal())
                  : 'Tap to set end time',
              onTap: _pickEnd,
            ),
            const SizedBox(height: 20),

            // Visibility
            _Label(text: 'Visibility'),
            const SizedBox(height: 8),
            SegmentedButton<TimeBlockVisibility>(
              segments: const [
                ButtonSegment(
                  value: TimeBlockVisibility.bothPartners,
                  label: Text('Both'),
                  icon: Icon(Icons.people_rounded),
                ),
                ButtonSegment(
                  value: TimeBlockVisibility.onlyMe,
                  label: Text('Only Me'),
                  icon: Icon(Icons.lock_rounded),
                ),
              ],
              selected: {formState.visibility},
              onSelectionChanged: (s) =>
                  ref.read(blockFormProvider.notifier).setVisibility(s.first),
            ),
            const SizedBox(height: 32),

            if (formState.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  formState.error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),

            ElevatedButton(
              onPressed:
                  (formState.saving || !formState.isValid || !canSave)
                      ? null
                      : _save,
              child: formState.saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save Block'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);
}

class _PresetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PresetChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.lavenderDeep),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: AppColors.lavender.withAlpha(60),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.lavenderDeep,
      ),
      side: BorderSide(color: AppColors.lavenderDeep.withAlpha(80)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TimeTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.inputFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.lavenderDeep, size: 20),
            const SizedBox(width: 12),
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  final BlockCategory selected;
  final ValueChanged<BlockCategory> onSelect;
  const _CategoryPicker({required this.selected, required this.onSelect});

  static const _items = [
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

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _items.map((item) {
        final (cat, icon, label) = item;
        final isSelected = selected == cat;
        return GestureDetector(
          onTap: () => onSelect(cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.lavender.withAlpha(120)
                  : AppColors.inputFill,
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? Border.all(color: AppColors.lavenderDeep, width: 1.5)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? AppColors.lavenderDeep
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.lavenderDeep
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
