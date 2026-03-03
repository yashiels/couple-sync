import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/time_block_model.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/block_providers.dart';
import '../../shared/providers/pairing_providers.dart';

/// Lists the current user's custom time blocks with edit/delete actions.
class BlocksScreen extends ConsumerWidget {
  const BlocksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final couple = ref.watch(currentCoupleProvider);

    final coupleId = couple?.coupleId;
    final userId = user?.uid;

    if (coupleId == null || userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please complete pairing to view blocks.')),
      );
    }

    final blocksAsync = ref.watch(
      userBlocksProvider((coupleId: coupleId, userId: userId)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('My Blocks')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/blocks/add'),
        backgroundColor: AppColors.roseDeep,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Block'),
      ),
      body: blocksAsync.when(
        data: (blocks) =>
            blocks.isEmpty ? _EmptyState() : _BlockList(blocks: blocks),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.rose.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.view_timeline_rounded,
              size: 40,
              color: AppColors.rose,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No blocks yet',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Add time blocks to let your partner\nknow when you\'re busy.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _BlockList extends StatelessWidget {
  final List<TimeBlock> blocks;
  const _BlockList({required this.blocks});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: blocks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _BlockCard(block: blocks[i]),
    );
  }
}

class _BlockCard extends ConsumerWidget {
  final TimeBlock block;
  const _BlockCard({required this.block});

  static final _dateFmt = DateFormat('EEE d MMM');
  static final _timeFmt = DateFormat('HH:mm');

  IconData get _categoryIcon {
    return switch (block.category) {
      BlockCategory.commute => Icons.directions_car_rounded,
      BlockCategory.exercise => Icons.fitness_center_rounded,
      BlockCategory.meals => Icons.restaurant_rounded,
      BlockCategory.sleep => Icons.nightlight_round,
      BlockCategory.personal => Icons.person_rounded,
      BlockCategory.work => Icons.work_rounded,
      BlockCategory.study => Icons.school_rounded,
      BlockCategory.social => Icons.groups_rounded,
      BlockCategory.other => Icons.block_rounded,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couple = ref.watch(currentCoupleProvider);
    final coupleId = couple?.coupleId ?? '';

    final start = block.startUtc.toLocal();
    final end = block.endUtc.toLocal();

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.rose.withAlpha(40),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_categoryIcon, color: AppColors.roseDeep, size: 22),
        ),
        title: Text(
          block.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '${_dateFmt.format(start)}  ${_timeFmt.format(start)} – ${_timeFmt.format(end)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (block.recurrenceRule != null)
              Row(
                children: [
                  const Icon(
                    Icons.repeat_rounded,
                    size: 12,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Recurring',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textHint),
          onSelected: (action) async {
            if (action == 'edit') {
              context.push('/blocks/edit/${block.id}');
            } else if (action == 'delete') {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete block?'),
                  content: Text(
                    'Are you sure you want to delete "${block.title}"? This cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref
                    .read(blockServiceProvider)
                    .deleteBlock(coupleId, block.id);
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
