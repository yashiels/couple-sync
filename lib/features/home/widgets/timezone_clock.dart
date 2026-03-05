import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';

/// Live clock displaying the current time in a given UTC offset.
/// Ticks every second. Designed to sit inside a grouped card container.
class TimezoneClock extends StatefulWidget {
  const TimezoneClock({
    super.key,
    required this.city,
    required this.utcOffset,
    this.isMe = true,
    this.label,
  });

  final String city;
  final Duration utcOffset;
  final bool isMe;
  final String? label;

  @override
  State<TimezoneClock> createState() => _TimezoneClockState();
}

class _TimezoneClockState extends State<TimezoneClock> {
  late DateTime _localTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    if (mounted) {
      setState(() {
        _localTime = DateTime.now().toUtc().add(widget.utcOffset);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(_localTime);
    final secondsStr = DateFormat(':ss').format(_localTime);
    final dateStr = DateFormat('EEE, MMM d').format(_localTime);
    final amPm = _localTime.hour >= 12 ? 'PM' : 'AM';
    final accentColor = widget.isMe ? AppColors.rose : AppColors.partnerBlue;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label
          Text(
            widget.label ?? (widget.isMe ? 'You' : 'Partner'),
            style: AppTypography.caption.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // Time
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: AppTypography.title1.copyWith(
                  fontWeight: FontWeight.w300,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  secondsStr,
                  style: AppTypography.footnote.copyWith(
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  amPm,
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(widget.city, style: AppTypography.subhead),
          Text(dateStr, style: AppTypography.caption),
        ],
      ),
    );
  }
}
