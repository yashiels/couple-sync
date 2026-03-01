import 'package:flutter/material.dart';

/// A row that shows two [TimeOfDay] pickers (start / end) labelled for quiet
/// hours selection.
class TimeRangePicker extends StatelessWidget {
  const TimeRangePicker({
    super.key,
    required this.start,
    required this.end,
    required this.onStartChanged,
    required this.onEndChanged,
    this.startLabel = 'From',
    this.endLabel = 'To',
  });

  final TimeOfDay start;
  final TimeOfDay end;
  final ValueChanged<TimeOfDay> onStartChanged;
  final ValueChanged<TimeOfDay> onEndChanged;
  final String startLabel;
  final String endLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _TimePill(
            label: startLabel,
            time: start,
            onTap: () => _pick(context, start, onStartChanged),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('–'),
          ),
          _TimePill(
            label: endLabel,
            time: end,
            onTap: () => _pick(context, end, onEndChanged),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    TimeOfDay initial,
    ValueChanged<TimeOfDay> onChanged,
  ) async {
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) onChanged(picked);
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({
    required this.label,
    required this.time,
    required this.onTap,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final formatted = time.format(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
          color: colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              formatted,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
