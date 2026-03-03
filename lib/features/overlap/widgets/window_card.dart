import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/overlap_window.dart';

/// Reusable card widget showing a single [OverlapWindow] with time range,
/// duration badge, optional Gemini-suggested activity, and Schedule Call button.
class WindowCard extends StatelessWidget {
  const WindowCard({
    super.key,
    required this.window,
    this.onScheduleCall,
  });

  /// The overlap window to display.
  final OverlapWindow window;

  /// Callback triggered when the "Schedule Call" button is tapped.
  final VoidCallback? onScheduleCall;

  static final _dateFmt = DateFormat('EEEE, d MMMM');
  static final _timeFmt = DateFormat('HH:mm');

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final start = window.startUtc.toLocal();
    final end = window.endUtc.toLocal();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.lavender.withAlpha(60),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.access_time_rounded,
                      color: AppColors.lavenderDeep),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_dateFmt.format(start),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${_timeFmt.format(start)} – ${_timeFmt.format(end)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                // Duration badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lavenderLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _formatDuration(window.durationMinutes),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.lavenderDark,
                    ),
                  ),
                ),
              ],
            ),
            // Gemini-suggested activity chip
            if (window.suggestedActivity != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.lavenderLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 14, color: AppColors.lavenderDark),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        window.suggestedActivity!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.lavenderDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Schedule Call button
            if (onScheduleCall != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onScheduleCall,
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text('Schedule Call'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.lavenderDark,
                    side: const BorderSide(color: AppColors.lavender),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
