import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';

/// Live clock card displaying the current time in a given UTC offset.
///
/// Ticks every second. Rose-tinted for the user's own clock, sky-blue for the
/// partner's.
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
    final isPM = _localTime.hour >= 12;
    final amPm = isPM ? 'PM' : 'AM';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (widget.isMe ? AppColors.rose : AppColors.partnerB)
                .withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: (widget.isMe ? AppColors.roseLight : const Color(0xFFD0E8FF)),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.isMe ? AppColors.rose : AppColors.partnerB,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label ?? (widget.isMe ? 'You' : 'Partner'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: widget.isMe ? AppColors.roseDark : const Color(0xFF5A9FE0),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                  color: AppColors.onSurface,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  secondsStr,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    color: AppColors.onSurfaceMuted,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  amPm,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.isMe ? AppColors.rose : AppColors.partnerB,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.city,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurface,
            ),
          ),
          Text(
            dateStr,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}
