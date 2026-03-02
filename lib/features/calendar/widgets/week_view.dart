import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/time_block.dart';
import '../../../core/theme/app_theme.dart';
import 'block_overlay.dart';

/// Scrollable week-view calendar widget displaying [blocks] and [freeWindows]
/// for both partners, with configurable UTC offsets per partner.
class WeekView extends StatelessWidget {
  const WeekView({
    super.key,
    required this.weekStart,
    required this.blocks,
    required this.freeWindows,
    required this.myUtcOffset,
    required this.partnerUtcOffset,
    this.onBlockTap,
    this.onWindowTap,
    this.onDayTap,
  });

  final DateTime weekStart;
  final List<TimeBlock> blocks;
  final List<FreeWindow> freeWindows;
  final Duration myUtcOffset;
  final Duration partnerUtcOffset;
  final void Function(TimeBlock)? onBlockTap;
  final void Function(FreeWindow)? onWindowTap;
  final void Function(DateTime)? onDayTap;

  static const double _hourHeight = 56.0;
  static const double _timeGutterWidth = 46.0;
  static const int _startHour = 6;
  static const int _endHour = 23;
  static const int _visibleHours = _endHour - _startHour;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Column(
      children: [
        // Day header row
        _DayHeader(
          days: days,
          today: today,
          onDayTap: onDayTap,
          gutterWidth: _timeGutterWidth,
        ),
        // Scrollable time grid
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: _hourHeight * _visibleHours,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time gutter
                  SizedBox(
                    width: _timeGutterWidth,
                    child: _TimeGutter(
                      startHour: _startHour,
                      endHour: _endHour,
                      hourHeight: _hourHeight,
                    ),
                  ),
                  // Day columns
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final colWidth = constraints.maxWidth / 7;
                        return Stack(
                          children: [
                            // Grid lines
                            _GridLines(
                              startHour: _startHour,
                              endHour: _endHour,
                              hourHeight: _hourHeight,
                              days: days,
                              colWidth: colWidth,
                              today: today,
                            ),
                            // Overlap highlights (behind blocks)
                            for (final window in freeWindows)
                              ..._buildWindowOverlays(window, days, colWidth),
                            // Time blocks
                            for (final block in blocks)
                              ..._buildBlockOverlays(block, days, colWidth),
                            // Now indicator
                            if (days.any((d) =>
                                d.year == today.year &&
                                d.month == today.month &&
                                d.day == today.day))
                              _NowLine(
                                today: today,
                                days: days,
                                colWidth: colWidth,
                                startHour: _startHour,
                                hourHeight: _hourHeight,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildBlockOverlays(
    TimeBlock block,
    List<DateTime> days,
    double colWidth,
  ) {
    final localOffset =
        block.owner == BlockOwner.me ? myUtcOffset : partnerUtcOffset;
    final localStart = block.startUtc.add(localOffset);
    final localEnd = block.endUtc.add(localOffset);

    final widgets = <Widget>[];
    for (int i = 0; i < days.length; i++) {
      final day = days[i];
      if (localStart.year == day.year &&
          localStart.month == day.month &&
          localStart.day == day.day) {
        final top = _timeToY(localStart.hour + localStart.minute / 60);
        final bottom = _timeToY(localEnd.hour + localEnd.minute / 60);
        final h = (bottom - top).clamp(12.0, double.infinity);

        // Split column: me on left half, partner on right half
        final isMe = block.owner == BlockOwner.me;
        final left = i * colWidth + (isMe ? 1 : colWidth / 2);
        final width = colWidth / 2 - 2;

        widgets.add(BlockOverlay(
          block: block,
          top: top,
          height: h,
          left: left,
          width: width,
          onTap: () => onBlockTap?.call(block),
        ));
      }
    }
    return widgets;
  }

  List<Widget> _buildWindowOverlays(
    FreeWindow window,
    List<DateTime> days,
    double colWidth,
  ) {
    final localStart = window.startUtc.add(myUtcOffset);
    final localEnd = window.endUtc.add(myUtcOffset);

    final widgets = <Widget>[];
    for (int i = 0; i < days.length; i++) {
      final day = days[i];
      if (localStart.year == day.year &&
          localStart.month == day.month &&
          localStart.day == day.day) {
        final top = _timeToY(localStart.hour + localStart.minute / 60);
        final bottom = _timeToY(localEnd.hour + localEnd.minute / 60);
        final h = (bottom - top).clamp(8.0, double.infinity);

        widgets.add(OverlapOverlay(
          top: top,
          height: h,
          left: i * colWidth + 1,
          width: colWidth - 2,
          onTap: () => onWindowTap?.call(window),
        ));
      }
    }
    return widgets;
  }

  double _timeToY(double hour) {
    return (hour - _startHour) * _hourHeight;
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.days,
    required this.today,
    required this.gutterWidth,
    this.onDayTap,
  });

  final List<DateTime> days;
  final DateTime today;
  final double gutterWidth;
  final void Function(DateTime)? onDayTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: gutterWidth),
          ...days.map((day) {
            final isToday = day.year == today.year &&
                day.month == today.month &&
                day.day == today.day;
            return Expanded(
              child: GestureDetector(
                onTap: () => onDayTap?.call(day),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('EEE').format(day).toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isToday
                              ? AppColors.roseDark
                              : AppColors.onSurfaceMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: isToday
                            ? const BoxDecoration(
                                gradient: AppColors.heroGradient,
                                shape: BoxShape.circle,
                              )
                            : null,
                        alignment: Alignment.center,
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isToday ? FontWeight.w700 : FontWeight.w500,
                            color:
                                isToday ? Colors.white : AppColors.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TimeGutter extends StatelessWidget {
  const _TimeGutter({
    required this.startHour,
    required this.endHour,
    required this.hourHeight,
  });

  final int startHour;
  final int endHour;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (int h = startHour; h < endHour; h++)
          Positioned(
            top: (h - startHour) * hourHeight + 2,
            left: 4,
            right: 4,
            child: Text(
              h == 12
                  ? '12pm'
                  : h < 12
                      ? '${h}am'
                      : '${h - 12}pm',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.onSurfaceMuted,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
      ],
    );
  }
}

class _GridLines extends StatelessWidget {
  const _GridLines({
    required this.startHour,
    required this.endHour,
    required this.hourHeight,
    required this.days,
    required this.colWidth,
    required this.today,
  });

  final int startHour;
  final int endHour;
  final double hourHeight;
  final List<DateTime> days;
  final double colWidth;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(colWidth * 7, hourHeight * (endHour - startHour)),
      painter: _GridPainter(
        startHour: startHour,
        endHour: endHour,
        hourHeight: hourHeight,
        colCount: 7,
        colWidth: colWidth,
        todayIndex: days.indexWhere((d) =>
            d.year == today.year && d.month == today.month && d.day == today.day),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.startHour,
    required this.endHour,
    required this.hourHeight,
    required this.colCount,
    required this.colWidth,
    required this.todayIndex,
  });

  final int startHour;
  final int endHour;
  final double hourHeight;
  final int colCount;
  final double colWidth;
  final int todayIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 0.5;

    final todayPaint = Paint()
      ..color = AppColors.roseLight.withValues(alpha: 0.4);

    // Today column highlight
    if (todayIndex >= 0) {
      canvas.drawRect(
        Rect.fromLTWH(todayIndex * colWidth, 0, colWidth, size.height),
        todayPaint,
      );
    }

    // Horizontal hour lines
    for (int h = 0; h <= endHour - startHour; h++) {
      final y = h * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Vertical column dividers
    for (int c = 1; c < colCount; c++) {
      final x = c * colWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.todayIndex != todayIndex ||
      old.startHour != startHour ||
      old.endHour != endHour;
}

class _NowLine extends StatelessWidget {
  const _NowLine({
    required this.today,
    required this.days,
    required this.colWidth,
    required this.startHour,
    required this.hourHeight,
  });

  final DateTime today;
  final List<DateTime> days;
  final double colWidth;
  final int startHour;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final todayIdx = days.indexWhere((d) =>
        d.year == today.year && d.month == today.month && d.day == today.day);
    if (todayIdx < 0) return const SizedBox.shrink();

    final now = DateTime.now();
    final y = (now.hour + now.minute / 60 - startHour) * hourHeight;
    final x = todayIdx * colWidth;

    return Positioned(
      top: y - 1,
      left: x,
      width: colWidth,
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.roseDark,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(
              height: 1.5,
              color: AppColors.roseDark,
            ),
          ),
        ],
      ),
    );
  }
}
