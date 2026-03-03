import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/time_block_model.dart';
import '../../../core/theme/app_theme.dart';

/// Horizontally scrollable timeline showing today's blocks for both partners
/// in [myUtcOffset]-local time.
class DailyTimeline extends StatelessWidget {
  const DailyTimeline({
    super.key,
    required this.blocks,
    required this.myUtcOffset,
    required this.myCity,
  });

  final List<TimeBlock> blocks;
  final Duration myUtcOffset;
  final String myCity;

  static const double _hourWidth = 72.0;
  static const double _trackHeight = 38.0;
  static const int _startHour = 6;
  static const int _endHour = 24;
  static const int _visibleHours = _endHour - _startHour;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc().add(myUtcOffset);
    final todayLocal = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              const Text(
                'Today',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                DateFormat('EEEE, MMMM d').format(now),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.lavender.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: _hourWidth * _visibleHours.toDouble(),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _HourLabels(startHour: _startHour, endHour: _endHour, hourWidth: _hourWidth),
                  const SizedBox(height: 6),
                  _BlockTrack(
                    label: 'You',
                    labelColor: AppColors.rose,
                    blocks: blocks.where((b) => b.userId == 'me').toList(),
                    color: AppColors.rose,
                    startHour: _startHour,
                    hourWidth: _hourWidth,
                    trackHeight: _trackHeight,
                    utcOffset: myUtcOffset,
                    todayLocal: todayLocal,
                  ),
                  const SizedBox(height: 6),
                  _BlockTrack(
                    label: 'Partner',
                    labelColor: AppColors.partnerB,
                    blocks: blocks.where((b) => b.userId != 'me').toList(),
                    color: AppColors.partnerB,
                    startHour: _startHour,
                    hourWidth: _hourWidth,
                    trackHeight: _trackHeight,
                    utcOffset: myUtcOffset,
                    todayLocal: todayLocal,
                  ),
                  const SizedBox(height: 6),
                  _NowIndicator(
                    now: now,
                    startHour: _startHour,
                    hourWidth: _hourWidth,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HourLabels extends StatelessWidget {
  const _HourLabels({
    required this.startHour,
    required this.endHour,
    required this.hourWidth,
  });

  final int startHour;
  final int endHour;
  final double hourWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Stack(
        children: [
          for (int h = startHour; h <= endHour; h++)
            Positioned(
              left: (h - startHour) * hourWidth,
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
              ),
            ),
        ],
      ),
    );
  }
}

class _BlockTrack extends StatelessWidget {
  const _BlockTrack({
    required this.label,
    required this.labelColor,
    required this.blocks,
    required this.color,
    required this.startHour,
    required this.hourWidth,
    required this.trackHeight,
    required this.utcOffset,
    required this.todayLocal,
  });

  final String label;
  final Color labelColor;
  final List<TimeBlock> blocks;
  final Color color;
  final int startHour;
  final double hourWidth;
  final double trackHeight;
  final Duration utcOffset;
  final DateTime todayLocal;

  @override
  Widget build(BuildContext context) {
    final totalWidth = hourWidth * (DailyTimeline._endHour - startHour);

    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
        SizedBox(
          width: totalWidth - 50,
          height: trackHeight,
          child: Stack(
            children: [
              Container(
                height: trackHeight,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              for (final block in blocks) _buildBlock(block),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBlock(TimeBlock block) {
    final localStart = block.startUtc.add(utcOffset);
    final localEnd = block.endUtc.add(utcOffset);

    final startMinutes = (localStart.hour + localStart.minute / 60) - startHour;
    final durationHours = localEnd.difference(localStart).inMinutes / 60;

    if (startMinutes < 0 || startMinutes > (DailyTimeline._endHour - startHour)) {
      return const SizedBox.shrink();
    }

    final left = (startMinutes * hourWidth - 50).clamp(0.0, double.infinity);
    final width = (durationHours * hourWidth).clamp(8.0, double.infinity);

    return Positioned(
      left: left,
      top: 4,
      child: Container(
        width: width,
        height: trackHeight - 8,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: width > 30
            ? Text(
                block.title.isNotEmpty ? block.title : 'Busy',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              )
            : null,
      ),
    );
  }
}

class _NowIndicator extends StatelessWidget {
  const _NowIndicator({
    required this.now,
    required this.startHour,
    required this.hourWidth,
  });

  final DateTime now;
  final int startHour;
  final double hourWidth;

  @override
  Widget build(BuildContext context) {
    final nowHours = now.hour + now.minute / 60;
    final left = (nowHours - startHour) * hourWidth - 50;

    if (left < 0) return const SizedBox.shrink();

    return SizedBox(
      height: 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: left,
            top: -80,
            child: Container(
              width: 2,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.roseDark.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Positioned(
            left: left - 3,
            top: -84,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.roseDark,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
