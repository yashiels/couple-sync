import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/time_block_model.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/block_providers.dart';
import '../../shared/providers/pairing_providers.dart';

class BlocksScreen extends ConsumerWidget {
  const BlocksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final couple = ref.watch(currentCoupleProvider);

    final coupleId = couple?.coupleId;
    final userId = user?.uid;

    if (coupleId == null || userId == null) {
      return Scaffold(
        backgroundColor: AppColors.groupedBackground,
        body: Center(
          child: Text(
            'Please complete pairing to view blocks.',
            style: AppTypography.body,
          ),
        ),
      );
    }

    final blocksAsync = ref.watch(
      userBlocksProvider((coupleId: coupleId, userId: userId)),
    );

    return Scaffold(
      backgroundColor: AppColors.groupedBackground,
      body: CustomScrollView(
        slivers: [
          // Large title with + button in trailing
          SliverAppBar(
            pinned: true,
            expandedHeight: 96,
            backgroundColor: AppColors.groupedBackground,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
              title: Text('My Blocks',
                  style: AppTypography.largeTitle.copyWith(fontSize: 28)),
              expandedTitleScale: 1.0,
            ),
            actions: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onPressed: () => context.push('/blocks/add'),
                child: Icon(Icons.add, color: AppColors.primary, size: 28),
              ),
            ],
          ),

          // Content
          blocksAsync.when(
            data: (blocks) => blocks.isEmpty
                ? SliverFillRemaining(child: _EmptyState())
                : _BlockSliverList(blocks: blocks, coupleId: coupleId),
            loading: () => const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Text('Error: $e', style: AppTypography.footnote),
              ),
            ),
          ),
        ],
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
              color: AppColors.primary.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.view_timeline_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text('No blocks yet', style: AppTypography.title2),
          const SizedBox(height: 8),
          Text(
            'Add time blocks to let your partner\nknow when you\'re busy.',
            textAlign: TextAlign.center,
            style: AppTypography.footnote,
          ),
        ],
      ),
    );
  }
}

class _BlockSliverList extends ConsumerWidget {
  final List<TimeBlock> blocks;
  final String coupleId;
  const _BlockSliverList({required this.blocks, required this.coupleId});

  static final _dateFmt = DateFormat('EEE d MMM');
  static final _timeFmt = DateFormat('HH:mm');

  IconData _categoryIcon(BlockCategory cat) {
    return switch (cat) {
      BlockCategory.commute => Icons.directions_car_rounded,
      BlockCategory.exercise => Icons.fitness_center_rounded,
      BlockCategory.meals => Icons.restaurant_rounded,
      BlockCategory.sleep => Icons.nightlight_round,
      BlockCategory.personal => Icons.person_rounded,
      BlockCategory.work => Icons.work_rounded,
      BlockCategory.study => Icons.school_rounded,
      BlockCategory.social => Icons.groups_rounded,
      BlockCategory.other => Icons.more_horiz_rounded,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final block = blocks[i];
            final start = block.startUtc.toLocal();
            final end = block.endUtc.toLocal();

            return Padding(
              padding: EdgeInsets.only(
                top: i == 0 ? 0 : 0,
                bottom: 0,
              ),
              child: Column(
                children: [
                  Dismissible(
                    key: ValueKey(block.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: AppColors.destructive,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_rounded,
                          color: Colors.white, size: 24),
                    ),
                    confirmDismiss: (_) async {
                      return await showCupertinoDialog<bool>(
                        context: context,
                        builder: (ctx) => CupertinoAlertDialog(
                          title: const Text('Delete Block?'),
                          content: Text(
                            'Are you sure you want to delete "${block.title}"? This cannot be undone.',
                          ),
                          actions: [
                            CupertinoDialogAction(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            CupertinoDialogAction(
                              isDestructiveAction: true,
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                    onDismissed: (_) async {
                      await ref
                          .read(blockServiceProvider)
                          .deleteBlock(coupleId, block.id);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.groupedBackground,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _categoryIcon(block.category),
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(block.title, style: AppTypography.headline),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_dateFmt.format(start)}  ${_timeFmt.format(start)} - ${_timeFmt.format(end)}',
                                    style: AppTypography.footnote,
                                  ),
                                  if (block.recurrenceRule != null)
                                    Row(
                                      children: [
                                        Icon(Icons.repeat_rounded,
                                            size: 12, color: AppColors.textSecondary),
                                        const SizedBox(width: 4),
                                        Text('Recurring', style: AppTypography.caption),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.push('/blocks/edit/${block.id}'),
                              child: const Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (i < blocks.length - 1) const SizedBox(height: 8),
                ],
              ),
            );
          },
          childCount: blocks.length,
        ),
      ),
    );
  }
}
