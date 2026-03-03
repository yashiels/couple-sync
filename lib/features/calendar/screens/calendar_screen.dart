import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/free_window.dart';
import '../../../shared/models/time_block_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mock_data.dart';
import '../widgets/week_view.dart';

/// Full-featured week-view calendar showing both partners' blocks and overlap
/// windows, navigated by swiping or tapping the chevron buttons.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Duration _myOffset = Duration(hours: -5);
  static const Duration _partnerOffset = Duration(hours: 0);

  late DateTime _currentWeekStart;

  @override
  void initState() {
    super.initState();
    _currentWeekStart = _startOfWeek(DateTime.now());
  }

  DateTime _startOfWeek(DateTime date) {
    final weekday = date.weekday % 7; // 0 = Sunday
    return DateTime(date.year, date.month, date.day - weekday);
  }

  void _previousWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    });
  }

  void _goToToday() {
    setState(() {
      _currentWeekStart = _startOfWeek(DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final blocks = MockData.todayBlocks();
    final windows = MockData.upcomingWindows();
    final weekEnd = _currentWeekStart.add(const Duration(days: 6));
    final isCurrentWeek = _startOfWeek(DateTime.now()) == _currentWeekStart;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _CalendarHeader(
              weekStart: _currentWeekStart,
              weekEnd: weekEnd,
              isCurrentWeek: isCurrentWeek,
              onPrevious: _previousWeek,
              onNext: _nextWeek,
              onToday: _goToToday,
            ),
            _Legend(),
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity != null) {
                    if (details.primaryVelocity! < -300) _nextWeek();
                    if (details.primaryVelocity! > 300) _previousWeek();
                  }
                },
                child: WeekView(
                  weekStart: _currentWeekStart,
                  blocks: blocks,
                  freeWindows: windows,
                  myUtcOffset: _myOffset,
                  partnerUtcOffset: _partnerOffset,
                  onBlockTap: _showBlockSheet,
                  onWindowTap: _showWindowSheet,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBlockSheet(TimeBlock block) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _BlockDetailSheet(
        block: block,
        myOffset: _myOffset,
        partnerOffset: _partnerOffset,
      ),
    );
  }

  void _showWindowSheet(FreeWindow window) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _WindowDetailSheet(
        window: window,
        myOffset: _myOffset,
        partnerOffset: _partnerOffset,
      ),
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.weekStart,
    required this.weekEnd,
    required this.isCurrentWeek,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final bool isCurrentWeek;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final sameMonth = weekStart.month == weekEnd.month;
    final label = sameMonth
        ? DateFormat('MMMM yyyy').format(weekStart)
        : '${DateFormat('MMM').format(weekStart)} – ${DateFormat('MMM yyyy').format(weekEnd)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calendar',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          if (!isCurrentWeek)
            TextButton(
              onPressed: onToday,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.roseDark,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              child: const Text('Today', style: TextStyle(fontSize: 13)),
            ),
          _NavButton(icon: Icons.chevron_left_rounded, onTap: onPrevious),
          const SizedBox(width: 4),
          _NavButton(icon: Icons.chevron_right_rounded, onTap: onNext),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon, size: 18, color: AppColors.onSurfaceMuted),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.surfaceElevated,
      child: Row(
        children: [
          _LegendItem(color: AppColors.rose, label: 'You'),
          const SizedBox(width: 12),
          _LegendItem(color: AppColors.partnerB, label: 'Partner'),
          const SizedBox(width: 12),
          _LegendItem(
            gradient: AppColors.overlapGradient,
            label: 'Free together',
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({this.color, this.gradient, required this.label});

  final Color? color;
  final Gradient? gradient;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            gradient: gradient,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.onSurfaceMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _BlockDetailSheet extends StatelessWidget {
  const _BlockDetailSheet({
    required this.block,
    required this.myOffset,
    required this.partnerOffset,
  });

  final TimeBlock block;
  final Duration myOffset;
  final Duration partnerOffset;

  bool get _isMe => block.userId == 'me';

  @override
  Widget build(BuildContext context) {
    final offset = _isMe ? myOffset : partnerOffset;
    final localStart = block.startUtc.add(offset);
    final localEnd = block.endUtc.add(offset);
    final timeRange =
        '${DateFormat('h:mm a').format(localStart)} – ${DateFormat('h:mm a').format(localEnd)}';

    return _BottomSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _isMe
                      ? AppColors.rose
                      : AppColors.partnerB,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isMe ? 'Your block' : 'Partner\'s block',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            block.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeRange,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${block.duration.inMinutes} minutes',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowDetailSheet extends StatelessWidget {
  const _WindowDetailSheet({
    required this.window,
    required this.myOffset,
    required this.partnerOffset,
  });

  final FreeWindow window;
  final Duration myOffset;
  final Duration partnerOffset;

  String _fmt(DateTime utc, Duration offset) =>
      DateFormat('h:mm a').format(utc.add(offset));

  @override
  Widget build(BuildContext context) {
    return _BottomSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    AppColors.heroGradient.createShader(bounds),
                child: const Icon(Icons.favorite_rounded,
                    size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text(
                'Free window together',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  window.durationLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _WindowTimeRow(
            city: window.cityA,
            start: _fmt(window.startUtc, myOffset),
            end: _fmt(window.endUtc, myOffset),
            dotColor: AppColors.rose,
          ),
          const SizedBox(height: 8),
          _WindowTimeRow(
            city: window.cityB,
            start: _fmt(window.startUtc, partnerOffset),
            end: _fmt(window.endUtc, partnerOffset),
            dotColor: AppColors.partnerB,
          ),
          if (window.suggestedActivity != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lavenderLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      size: 14, color: AppColors.lavenderDark),
                  const SizedBox(width: 8),
                  Text(
                    window.suggestedActivity!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.lavenderDark,
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
}

class _WindowTimeRow extends StatelessWidget {
  const _WindowTimeRow({
    required this.city,
    required this.start,
    required this.end,
    required this.dotColor,
  });

  final String city;
  final String start;
  final String end;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          city,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface),
        ),
        const Spacer(),
        Text(
          '$start – $end',
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurface),
        ),
      ],
    );
  }
}

class _BottomSheet extends StatelessWidget {
  const _BottomSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
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
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
