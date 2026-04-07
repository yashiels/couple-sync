import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/utils/timezone_helper.dart';

/// Widget displaying two live clocks: user's timezone and partner's timezone.
/// Updates every minute to show current time in both locations.
class PartnerClockWidget extends StatefulWidget {
  /// User's timezone IANA ID
  final String userTimezone;
  
  /// Partner's timezone IANA ID
  final String partnerTimezone;
  
  /// Partner's display name
  final String partnerName;

  const PartnerClockWidget({
    super.key,
    required this.userTimezone,
    required this.partnerTimezone,
    required this.partnerName,
  });

  @override
  State<PartnerClockWidget> createState() => _PartnerClockWidgetState();
}

class _PartnerClockWidgetState extends State<PartnerClockWidget> {
  Timer? _timer;
  late String _userTime;
  late String _partnerTime;

  @override
  void initState() {
    super.initState();
    _updateTimes();
    // Update every minute
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _updateTimes());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTimes() {
    setState(() {
      _userTime = TimezoneHelper.getCurrentTime(widget.userTimezone);
      _partnerTime = TimezoneHelper.getCurrentTime(widget.partnerTimezone);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // User's clock
            Expanded(
              child: _ClockColumn(
                label: 'You',
                time: _userTime,
                timezone: widget.userTimezone,
                isUser: true,
              ),
            ),
            
            // Divider
            Container(
              height: 60,
              width: 1,
              color: theme.dividerColor,
            ),
            
            // Partner's clock
            Expanded(
              child: _ClockColumn(
                label: widget.partnerName,
                time: _partnerTime,
                timezone: widget.partnerTimezone,
                isUser: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single clock display with label and timezone offset.
class _ClockColumn extends StatelessWidget {
  final String label;
  final String time;
  final String timezone;
  final bool isUser;

  const _ClockColumn({
    required this.label,
    required this.time,
    required this.timezone,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offset = TimezoneHelper.getCurrentOffset(timezone);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isUser 
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          time,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          offset,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
