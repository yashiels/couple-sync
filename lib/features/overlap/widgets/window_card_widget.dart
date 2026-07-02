import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/models/overlap_result.dart';
import '../../../core/utils/timezone_helper.dart';

/// Card displaying a single overlap window with date, time ranges (both timezones),
/// duration, and score breakdown.
class WindowCardWidget extends StatelessWidget {
  /// The overlap window to display
  final OverlapWindow window;

  /// User's timezone IANA ID
  final String userTimezone;

  /// Partner's timezone IANA ID
  final String partnerTimezone;

  /// Callback when card is tapped
  final VoidCallback? onTap;

  const WindowCardWidget({
    super.key,
    required this.window,
    required this.userTimezone,
    required this.partnerTimezone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Date and Score badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _formatDate(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildScoreBadge(theme),
                ],
              ),

              const SizedBox(height: 16),

              // Time ranges
              _buildTimeRanges(theme),

              const SizedBox(height: 16),

              // Duration and reasonable hours indicator
              Row(
                children: [
                  _buildInfoChip(
                    theme: theme,
                    icon: Icons.schedule,
                    label: _formatDuration(window.durationMinutes),
                  ),
                  if (window.reasonableBoth) ...[
                    const SizedBox(width: 12),
                    _buildInfoChip(
                      theme: theme,
                      icon: Icons.wb_sunny,
                      label: 'Reasonable hours',
                      color: Colors.green,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreBadge(ThemeData theme) {
    final scoreDisplay = window.score.round();
    final color = _getScoreColor(window.score);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            '$scoreDisplay',
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRanges(ThemeData theme) {
    final userTz = TimezoneHelper.getCurrentOffset(userTimezone);
    final partnerTz = TimezoneHelper.getCurrentOffset(partnerTimezone);

    final timeFormat = DateFormat('h:mm a');

    // Convert UTC timestamps to user's timezone using TZDateTime
    final userLocation = tz.getLocation(userTimezone);
    final userStart = tz.TZDateTime.from(window.startDateTime, userLocation);
    final userEnd = tz.TZDateTime.from(window.endDateTime, userLocation);

    // Convert UTC timestamps to partner's timezone using TZDateTime
    final partnerLocation = tz.getLocation(partnerTimezone);
    final partnerStart = tz.TZDateTime.from(
      window.startDateTime,
      partnerLocation,
    );
    final partnerEnd = tz.TZDateTime.from(window.endDateTime, partnerLocation);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User's time
        Row(
          children: [
            Icon(Icons.person, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '${timeFormat.format(userStart)} - ${timeFormat.format(userEnd)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '($userTz)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Partner's time
        Row(
          children: [
            Icon(Icons.favorite, size: 16, color: theme.colorScheme.secondary),
            const SizedBox(width: 8),
            Text(
              '${timeFormat.format(partnerStart)} - ${timeFormat.format(partnerEnd)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '($partnerTz)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final chipColor = color ?? theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: chipColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: chipColor),
        ),
      ],
    );
  }

  String _formatDate() {
    final dateFormat = DateFormat('EEEE, MMMM d');
    final userLocation = tz.getLocation(userTimezone);
    final userStart = tz.TZDateTime.from(window.startDateTime, userLocation);
    return dateFormat.format(userStart);
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final mins = minutes.remainder(60);
    if (mins == 0) {
      return '$hours hr';
    }
    return '$hours hr $mins min';
  }

  Color _getScoreColor(double score) {
    // Score range is 0-60+ (composite of duration, time-of-day, recency)
    if (score >= 40) return Colors.green;
    if (score >= 25) return Colors.lightGreen;
    if (score >= 15) return Colors.orange;
    return Colors.red;
  }
}
