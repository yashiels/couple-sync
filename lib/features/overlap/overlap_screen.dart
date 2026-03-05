import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/overlap_window.dart';
import '../../shared/providers/overlap_providers.dart';
import '../../shared/providers/pairing_providers.dart';

enum _DurationFilter {
  any('Any', 0),
  thirtyMin('30 min', 30),
  oneHour('1 hr', 60),
  twoHours('2 hr', 120);

  const _DurationFilter(this.label, this.minMinutes);
  final String label;
  final int minMinutes;
}

class OverlapScreen extends ConsumerStatefulWidget {
  const OverlapScreen({super.key});

  @override
  ConsumerState<OverlapScreen> createState() => _OverlapScreenState();
}

class _OverlapScreenState extends ConsumerState<OverlapScreen> {
  _DurationFilter _selectedFilter = _DurationFilter.any;

  static final _dateFmt = DateFormat('EEEE, d MMMM');
  static final _timeFmt = DateFormat('HH:mm');

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final couple = ref.watch(currentCoupleProvider);

    if (couple == null) {
      return Scaffold(
        backgroundColor: AppColors.groupedBackground,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 96,
              backgroundColor: AppColors.groupedBackground,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
                title: Text('Free Time',
                    style: AppTypography.largeTitle.copyWith(fontSize: 28)),
                expandedTitleScale: 1.0,
              ),
            ),
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Pair with your partner first to see shared free windows.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final coupleId = couple.coupleId;
    final overlapAsync = ref.watch(overlapResultProvider(coupleId));
    final computedAt = ref.watch(overlapComputedAtProvider(coupleId));

    return Scaffold(
      backgroundColor: AppColors.groupedBackground,
      body: CustomScrollView(
        slivers: [
          // Large title
          SliverAppBar(
            pinned: true,
            expandedHeight: 96,
            backgroundColor: AppColors.groupedBackground,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
              title: Text('Free Time',
                  style: AppTypography.largeTitle.copyWith(fontSize: 28)),
              expandedTitleScale: 1.0,
            ),
            actions: [
              if (computedAt != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Text(
                      'Updated ${_relativeTime(computedAt)}',
                      style: AppTypography.caption,
                    ),
                  ),
                ),
            ],
          ),

          // Segmented filter
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: CupertinoSlidingSegmentedControl<_DurationFilter>(
                groupValue: _selectedFilter,
                children: {
                  for (final f in _DurationFilter.values)
                    f: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Text(
                        f.label,
                        style: AppTypography.subhead.copyWith(
                          fontWeight: _selectedFilter == f
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                },
                onValueChanged: (v) {
                  if (v != null) setState(() => _selectedFilter = v);
                },
              ),
            ),
          ),

          // Window list
          overlapAsync.when(
            data: (result) {
              if (result == null || result.windows.isEmpty) {
                return SliverFillRemaining(child: _buildEmptyState());
              }
              final filtered = result.windows
                  .where((w) => w.durationMinutes >= _selectedFilter.minMinutes)
                  .toList();
              if (filtered.isEmpty) {
                return SliverFillRemaining(child: _buildNoMatchState());
              }
              return _buildWindowSliver(filtered);
            },
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                gradient: AppColors.heroGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text('No free windows yet', style: AppTypography.title2),
            const SizedBox(height: 10),
            Text(
              'Add your schedules and we\'ll find moments when you\'re both free.',
              textAlign: TextAlign.center,
              style: AppTypography.footnote,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_list_off_rounded,
                size: 48, color: AppColors.onSurfaceMuted),
            const SizedBox(height: 16),
            Text('No windows match this filter', style: AppTypography.title2),
            const SizedBox(height: 10),
            Text(
              'Try a shorter minimum duration to see more results.',
              textAlign: TextAlign.center,
              style: AppTypography.footnote,
            ),
          ],
        ),
      ),
    );
  }

  SliverPadding _buildWindowSliver(List<OverlapWindow> windows) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final window = windows[i];
            return Padding(
              padding: EdgeInsets.only(bottom: i < windows.length - 1 ? 10 : 80),
              child: i == 0
                  ? _buildHeroCard(window)
                  : _buildWindowCard(window),
            );
          },
          childCount: windows.length,
        ),
      ),
    );
  }

  Widget _buildHeroCard(OverlapWindow window) {
    final start = window.startUtc.toLocal();
    final end = window.endUtc.toLocal();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text('Best Match',
                  style: AppTypography.caption.copyWith(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _dateFmt.format(start),
            style: AppTypography.headline.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            '${_timeFmt.format(start)} - ${_timeFmt.format(end)}',
            style: AppTypography.title1.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _heroChip(_formatDuration(window.durationMinutes)),
              const SizedBox(width: 8),
              if (window.reasonableBoth) _heroChip('Good hours for both'),
            ],
          ),
          if (window.suggestedActivity != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      window.suggestedActivity!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(50),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildWindowCard(OverlapWindow window) {
    final start = window.startUtc.toLocal();
    final end = window.endUtc.toLocal();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_dateFmt.format(start), style: AppTypography.headline),
                    const SizedBox(height: 2),
                    Text(
                      '${_timeFmt.format(start)} - ${_timeFmt.format(end)}',
                      style: AppTypography.footnote,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.groupedBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _formatDuration(window.durationMinutes),
                  style: AppTypography.captionBold.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (window.suggestedActivity != null) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    window.suggestedActivity!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
