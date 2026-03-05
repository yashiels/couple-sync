import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/free_window.dart';
import '../../shared/models/time_block_model.dart';
import '../../shared/providers/auth_providers.dart';
import '../../shared/providers/block_providers.dart';
import '../../shared/providers/pairing_providers.dart';
import 'providers/google_calendar_provider.dart';
import 'widgets/week_view.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late final PageController _pageController;
  static const _initialPage = 52;
  int _currentPage = _initialPage;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _weekStartForPage(int page) {
    final now = DateTime.now();
    final currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final startOfDay = DateTime(
      currentWeekStart.year,
      currentWeekStart.month,
      currentWeekStart.day,
    );
    return startOfDay.add(Duration(days: (page - _initialPage) * 7));
  }

  String _weekLabel(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final startFmt = DateFormat('d MMM').format(weekStart);
    final endFmt = DateFormat('d MMM').format(weekEnd);
    return '$startFmt \u2013 $endFmt';
  }

  Future<void> _syncAll() async {
    final user = ref.read(currentUserProvider);
    final couple = ref.read(currentCoupleProvider);
    if (user == null || couple == null) return;

    final googleConnected = ref.read(googleCalendarConnectionProvider);
    if (!googleConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No calendars connected. Add one in Settings.')),
        );
      }
      return;
    }

    try {
      await ref.read(googleCalendarSyncProvider.notifier).sync(
            userId: user.uid,
            coupleId: couple.coupleId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendars synced successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed. Please try again.')),
        );
      }
    }
  }

  void _showBlockDetail(TimeBlock block) {
    final user = ref.read(currentUserProvider);
    final isMe = block.userId == user?.uid;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.separator,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Title row
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.rose : AppColors.partnerBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      block.title.isNotEmpty
                          ? block.title
                          : (isMe ? 'Busy' : 'Partner busy'),
                      style: AppTypography.title2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(
                icon: Icons.schedule_rounded,
                label:
                    '${DateFormat('EEE d MMM, HH:mm').format(block.startUtc.toLocal())}'
                    ' \u2013 '
                    '${DateFormat('HH:mm').format(block.endUtc.toLocal())}',
              ),
              const SizedBox(height: 8),
              _DetailRow(
                icon: Icons.category_rounded,
                label: block.category.name[0].toUpperCase() +
                    block.category.name.substring(1),
              ),
              const SizedBox(height: 8),
              _DetailRow(
                icon: Icons.person_rounded,
                label: isMe ? 'You' : 'Partner',
              ),
              const SizedBox(height: 8),
              _DetailRow(
                icon: _sourceIcon(block.source),
                label: block.source.name[0].toUpperCase() +
                    block.source.name.substring(1),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  IconData _sourceIcon(BlockSource source) {
    switch (source) {
      case BlockSource.google:
        return Icons.event_rounded;
      case BlockSource.microsoft:
        return Icons.calendar_today_rounded;
      case BlockSource.manual:
        return Icons.edit_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final couple = ref.watch(currentCoupleProvider);
    final coupleId = couple?.coupleId;
    final blocks = coupleId != null
        ? ref.watch(coupleBlocksProvider(coupleId)).valueOrNull ?? []
        : <TimeBlock>[];
    final freeWindows = <FreeWindow>[];
    final weekStart = _weekStartForPage(_currentPage);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Large title
          SliverAppBar(
            pinned: true,
            expandedHeight: 96,
            backgroundColor: AppColors.background,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
              title: Text('Calendar',
                  style: AppTypography.largeTitle.copyWith(fontSize: 28)),
              expandedTitleScale: 1.0,
            ),
            actions: [
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () {
                  _pageController.animateToPage(
                    _initialPage,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                child: Text('Today',
                    style: AppTypography.headline
                        .copyWith(color: AppColors.primary)),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onPressed: _syncAll,
                child: Icon(Icons.sync_rounded, color: AppColors.primary, size: 22),
              ),
            ],
          ),

          SliverFillRemaining(
            child: Column(
              children: [
                // Week nav header
                _WeekNavHeader(
                  label: _weekLabel(weekStart),
                  onPrev: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  onNext: () => _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                ),

                // Legend
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _LegendDot(color: AppColors.rose, label: 'You'),
                      const SizedBox(width: 16),
                      _LegendDot(
                          color: AppColors.partnerBlue, label: 'Partner'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // Week view pages
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _initialPage * 2 + 1,
                    onPageChanged: (page) =>
                        setState(() => _currentPage = page),
                    itemBuilder: (context, page) {
                      final ws = _weekStartForPage(page);
                      return WeekView(
                        weekStart: ws,
                        blocks: blocks,
                        freeWindows: freeWindows,
                        myUtcOffset: DateTime.now().timeZoneOffset,
                        partnerUtcOffset: DateTime.now().timeZoneOffset,
                        myUserId:
                            ref.read(currentUserProvider)?.uid ?? '',
                        onBlockTap: _showBlockDetail,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _WeekNavHeader extends StatelessWidget {
  const _WeekNavHeader({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onPrev,
            child: const Icon(Icons.chevron_left_rounded,
                color: AppColors.onSurface),
          ),
          Text(label, style: AppTypography.headline),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onNext,
            child: const Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurface),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.footnote),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.onSurfaceMuted),
        const SizedBox(width: 10),
        Text(label, style: AppTypography.body),
      ],
    );
  }
}
