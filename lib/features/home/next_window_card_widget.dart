import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/models/overlap_result.dart';
import '../../../core/utils/timezone_helper.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/format_utils.dart';

/// Card displaying the next free window with countdown.
/// Shows date, time (both timezones), duration, and quality score.
/// Tapping navigates to the full overlap screen.
class NextWindowCard extends StatefulWidget {
  /// The next overlap window to display
  final OverlapWindow? window;

  /// User's timezone IANA ID
  final String userTimezone;

  /// Partner's timezone IANA ID
  final String partnerTimezone;

  const NextWindowCard({
    super.key,
    required this.window,
    required this.userTimezone,
    required this.partnerTimezone,
  });

  @override
  State<NextWindowCard> createState() => _NextWindowCardState();
}

class _NextWindowCardState extends State<NextWindowCard> {
  Timer? _timer;
  String _countdown = '';

  @override
  void initState() {
    super.initState();
    _updateCountdown();
    // Update countdown every minute
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateCountdown(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (widget.window == null) {
      setState(() => _countdown = '');
      return;
    }

    final now = DateTime.now().toUtc();
    final start = widget.window!.startDateTime;
    final diff = start.difference(now);

    if (diff.isNegative) {
      setState(() => _countdown = 'Now');
    } else {
      final hours = diff.inHours;
      final minutes = diff.inMinutes.remainder(60);

      if (hours > 24) {
        final days = diff.inDays;
        final remainingHours = hours.remainder(24);
        setState(
          () => _countdown =
              '$days day${days != 1 ? 's' : ''} ${remainingHours}h',
        );
      } else {
        setState(() => _countdown = '${hours}h ${minutes}m');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.window == null) {
      return _buildEmptyState(theme);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(AppRoutes.overlap),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Next Free Window',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // Countdown badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _countdown,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Date and times
              _buildDateTimeRow(theme),

              const SizedBox(height: 12),

              // Duration and score row
              Row(
                children: [
                  _buildInfoChip(
                    icon: Icons.schedule,
                    label: formatDurationMinutes(widget.window!.durationMinutes),
                  ),
                  const SizedBox(width: 12),
                  _buildInfoChip(
                    icon: Icons.star,
                    label: 'Score: ${widget.window!.score.toStringAsFixed(0)}',
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Tap hint
              Center(
                child: Text(
                  'Tap to see all windows',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(
              Icons.event_busy,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No upcoming free windows',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add some time blocks to see when you can meet',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeRow(ThemeData theme) {
    final window = widget.window!;
    final userTz = TimezoneHelper.getCurrentOffset(widget.userTimezone);
    final partnerTz = TimezoneHelper.getCurrentOffset(widget.partnerTimezone);

    final dateFormat = DateFormat('EEE, MMM d');
    final timeFormat = DateFormat('h:mm a');

    // Convert to each user's timezone using TZDateTime
    final userLocation = tz.getLocation(widget.userTimezone);
    final partnerLocation = tz.getLocation(widget.partnerTimezone);
    final userStart = tz.TZDateTime.from(window.startDateTime, userLocation);
    final userEnd = tz.TZDateTime.from(window.endDateTime, userLocation);
    final partnerStart = tz.TZDateTime.from(
      window.startDateTime,
      partnerLocation,
    );
    final partnerEnd = tz.TZDateTime.from(window.endDateTime, partnerLocation);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date
        Text(
          dateFormat.format(userStart),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        // User's time
        Row(
          children: [
            Icon(Icons.person, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              '${timeFormat.format(userStart)} - ${timeFormat.format(userEnd)} ($userTz)',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Partner's time
        Row(
          children: [
            Icon(Icons.favorite, size: 16, color: theme.colorScheme.secondary),
            const SizedBox(width: 4),
            Text(
              '${timeFormat.format(partnerStart)} - ${timeFormat.format(partnerEnd)} ($partnerTz)',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

}
