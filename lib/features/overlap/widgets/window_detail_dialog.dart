import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/models/overlap_result.dart';

/// Detail dialog for an [OverlapWindow], showing the date, both partners'
/// local time ranges, duration, score, and reasonable-hours badge.
///
/// Shared by the overlap screen list and the home screen's upcoming-window
/// card so both surfaces present identical details.
class WindowDetailDialog extends StatelessWidget {
  final OverlapWindow window;
  final String userTimezone;
  final String partnerTimezone;

  const WindowDetailDialog({
    super.key,
    required this.window,
    required this.userTimezone,
    required this.partnerTimezone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('EEEE, MMMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

    final userLocation = tz.getLocation(userTimezone);
    final userStart = tz.TZDateTime.from(window.startDateTime, userLocation);
    final userEnd = tz.TZDateTime.from(window.endDateTime, userLocation);

    final partnerLocation = tz.getLocation(partnerTimezone);
    final partnerStart =
        tz.TZDateTime.from(window.startDateTime, partnerLocation);
    final partnerEnd = tz.TZDateTime.from(window.endDateTime, partnerLocation);

    return AlertDialog(
      title: const Text('Window Details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateFormat.format(userStart),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            'Your Time',
            '${timeFormat.format(userStart)} - ${timeFormat.format(userEnd)}',
            theme,
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            'Partner\'s Time',
            '${timeFormat.format(partnerStart)} - ${timeFormat.format(partnerEnd)}',
            theme,
          ),
          const Divider(height: 32),
          _buildDetailRow(
            'Duration',
            _formatDuration(window.durationMinutes),
            theme,
          ),
          const SizedBox(height: 8),
          Text(
            'Score',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildScoreRow('Match Score', window.score, theme),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                window.reasonableBoth ? Icons.check_circle : Icons.cancel,
                size: 20,
                color: window.reasonableBoth ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                window.reasonableBoth
                    ? 'Reasonable hours for both'
                    : 'Outside typical hours',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScoreRow(String label, double score, ThemeData theme) {
    final scoreDisplay = score.round();
    final color = _getScoreColor(score);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (score / 60).clamp(0.0, 1.0),
                backgroundColor: color.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$scoreDisplay',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '$hours hr';
    }
    return '$hours hr $mins min';
  }

  Color _getScoreColor(double score) {
    if (score >= 40) return Colors.green;
    if (score >= 25) return Colors.lightGreen;
    if (score >= 15) return Colors.orange;
    return Colors.red;
  }
}
