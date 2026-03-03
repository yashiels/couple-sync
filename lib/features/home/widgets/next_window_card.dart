import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/free_window.dart';
import '../../../core/theme/app_theme.dart';

/// Hero card showing the soonest upcoming [FreeWindow] with a live countdown
/// and dual-timezone time display.
class NextWindowCard extends StatefulWidget {
  const NextWindowCard({
    super.key,
    required this.window,
    this.myUtcOffset = const Duration(hours: -5),
    this.partnerUtcOffset = const Duration(hours: 0),
    this.onTap,
  });

  final FreeWindow window;
  final Duration myUtcOffset;
  final Duration partnerUtcOffset;
  final VoidCallback? onTap;

  @override
  State<NextWindowCard> createState() => _NextWindowCardState();
}

class _NextWindowCardState extends State<NextWindowCard> {
  Timer? _timer;
  Duration _countdown = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateCountdown();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCountdown());
  }

  void _updateCountdown() {
    if (mounted) {
      final diff = widget.window.startUtc.difference(DateTime.now().toUtc());
      setState(() {
        _countdown = diff.isNegative ? Duration.zero : diff;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatCountdown(Duration d) {
    if (d.inDays > 0) {
      final h = d.inHours.remainder(24);
      return '${d.inDays}d ${h}h';
    }
    if (d.inHours > 0) {
      final m = d.inMinutes.remainder(60);
      return '${d.inHours}h ${m.toString().padLeft(2, '0')}m';
    }
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String _formatLocalTime(DateTime utc, Duration offset) {
    final local = utc.add(offset);
    return DateFormat('h:mm a').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final myStart = _formatLocalTime(widget.window.startUtc, widget.myUtcOffset);
    final myEnd = _formatLocalTime(widget.window.endUtc, widget.myUtcOffset);
    final partnerStart = _formatLocalTime(widget.window.startUtc, widget.partnerUtcOffset);
    final partnerEnd = _formatLocalTime(widget.window.endUtc, widget.partnerUtcOffset);
    final isHappening = widget.window.startUtc.isBefore(DateTime.now().toUtc());

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.lavender.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isHappening ? 'You\'re free now!' : 'Next free window',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isHappening ? 'Now → $myEnd' : 'in ${_formatCountdown(_countdown)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.window.durationLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _TimeZoneRow(
                        city: widget.window.cityA,
                        timeRange: '$myStart – $myEnd',
                        dotColor: AppColors.rose,
                        isMe: true,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    Expanded(
                      child: _TimeZoneRow(
                        city: widget.window.cityB,
                        timeRange: '$partnerStart – $partnerEnd',
                        dotColor: AppColors.partnerB,
                        isMe: false,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.window.suggestedActivity != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 13, color: Colors.white70),
                    const SizedBox(width: 5),
                    Text(
                      widget.window.suggestedActivity!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeZoneRow extends StatelessWidget {
  const _TimeZoneRow({
    required this.city,
    required this.timeRange,
    required this.dotColor,
    required this.isMe,
  });

  final String city;
  final String timeRange;
  final Color dotColor;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isMe ? 0 : 12,
        right: isMe ? 12 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                city,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            timeRange,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
