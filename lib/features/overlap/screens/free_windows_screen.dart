import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/time_block.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mock_data.dart';
import '../widgets/window_card.dart';

class FreeWindowsScreen extends StatefulWidget {
  const FreeWindowsScreen({super.key});

  @override
  State<FreeWindowsScreen> createState() => _FreeWindowsScreenState();
}

class _FreeWindowsScreenState extends State<FreeWindowsScreen> {
  static const Duration _myOffset = Duration(hours: -5);
  static const Duration _partnerOffset = Duration(hours: 0);

  int _minDurationMinutes = 30;

  @override
  Widget build(BuildContext context) {
    final allWindows = MockData.upcomingWindows()
        .where((w) => w.duration.inMinutes >= _minDurationMinutes)
        .toList();

    // Group by local date (my timezone)
    final grouped = <String, List<FreeWindow>>{};
    for (final w in allWindows) {
      final local = w.startUtc.add(_myOffset);
      final key = DateFormat('yyyy-MM-dd').format(local);
      grouped.putIfAbsent(key, () => []).add(w);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                totalCount: allWindows.length,
                minDuration: _minDurationMinutes,
                onDurationChanged: (v) =>
                    setState(() => _minDurationMinutes = v),
              ),
            ),
            if (allWindows.isEmpty)
              const SliverFillRemaining(child: _EmptyState())
            else
              for (final key in sortedKeys) ...[
                SliverToBoxAdapter(
                  child: _DayHeader(
                    dateKey: key,
                    myOffset: _myOffset,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final window = grouped[key]![i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: WindowCard(
                            window: window,
                            myUtcOffset: _myOffset,
                            partnerUtcOffset: _partnerOffset,
                            onTap: () => _showDetail(window),
                          ),
                        );
                      },
                      childCount: grouped[key]!.length,
                    ),
                  ),
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  void _showDetail(FreeWindow window) {
    final myLocal = window.startUtc.add(_myOffset);
    final partnerLocal = window.startUtc.add(_partnerOffset);
    final myEnd = window.endUtc.add(_myOffset);
    final partnerEnd = window.endUtc.add(_partnerOffset);
    final fmt = DateFormat('h:mm a');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DetailSheet(
        window: window,
        myTimeRange: '${fmt.format(myLocal)} – ${fmt.format(myEnd)}',
        partnerTimeRange: '${fmt.format(partnerLocal)} – ${fmt.format(partnerEnd)}',
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.totalCount,
    required this.minDuration,
    required this.onDurationChanged,
  });

  final int totalCount;
  final int minDuration;
  final ValueChanged<int> onDurationChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Free Windows',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
              _TotalBadge(count: totalCount),
            ],
          ),
          const SizedBox(height: 12),
          _DurationFilter(
            selectedMinutes: minDuration,
            onChanged: onDurationChanged,
          ),
        ],
      ),
    );
  }
}

class _TotalBadge extends StatelessWidget {
  const _TotalBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count windows',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _DurationFilter extends StatelessWidget {
  const _DurationFilter({
    required this.selectedMinutes,
    required this.onChanged,
  });

  final int selectedMinutes;
  final ValueChanged<int> onChanged;

  static const _options = [15, 30, 60, 120];
  static const _labels = ['15m+', '30m+', '1h+', '2h+'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Min duration:',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.onSurfaceMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        ...List.generate(_options.length, (i) {
          final selected = _options[i] == selectedMinutes;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onChanged(_options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: selected ? AppColors.heroGradient : null,
                  color: selected ? null : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : AppColors.divider,
                  ),
                ),
                child: Text(
                  _labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : AppColors.onSurfaceMuted,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.dateKey,
    required this.myOffset,
  });

  final String dateKey;
  final Duration myOffset;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now().toUtc().add(myOffset);
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    String label;
    if (date.isAtSameMomentAs(today)) {
      label = 'Today';
    } else if (date.isAtSameMomentAs(tomorrow)) {
      label = 'Tomorrow';
    } else {
      label = DateFormat('EEEE, MMMM d').format(date);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          if (label == 'Today' || label == 'Tomorrow')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: label == 'Today' ? AppColors.roseLight : AppColors.lavenderLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                DateFormat('MMM d').format(date),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: label == 'Today' ? AppColors.roseDark : AppColors.lavenderDark,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({
    required this.window,
    required this.myTimeRange,
    required this.partnerTimeRange,
  });

  final FreeWindow window;
  final String myTimeRange;
  final String partnerTimeRange;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  window.durationLabel,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const Text(
                  'free together',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Times
          _DetailRow(
            icon: Icons.circle,
            iconColor: AppColors.rose,
            label: window.cityA,
            value: myTimeRange,
          ),
          const SizedBox(height: 10),
          _DetailRow(
            icon: Icons.circle,
            iconColor: AppColors.partnerB,
            label: window.cityB,
            value: partnerTimeRange,
          ),
          if (window.suggestedActivity != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.lavenderLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 16, color: AppColors.lavenderDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Suggested',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.lavenderDark,
                          ),
                        ),
                        Text(
                          window.suggestedActivity!,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.lavender,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Add to Calendar',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 10, color: iconColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.onSurfaceMuted,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (bounds) =>
                AppColors.heroGradient.createShader(bounds),
            child: const Icon(Icons.calendar_today_outlined,
                size: 56, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'No free windows found',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a shorter minimum duration',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}
