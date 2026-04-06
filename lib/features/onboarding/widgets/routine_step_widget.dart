import 'package:flutter/material.dart';

/// Day of week selection for routine setup.
/// Uses standard weekday numbering (1 = Monday, 7 = Sunday).
class DayOfWeekSelector extends StatelessWidget {
  final Set<int> selectedDays;
  final Function(Set<int>) onSelectionChanged;

  const DayOfWeekSelector({
    super.key,
    required this.selectedDays,
    required this.onSelectionChanged,
  });

  static const _dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _fullDayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (index) {
        final day = index + 1; // 1-7 (Mon-Sun)
        final isSelected = selectedDays.contains(day);

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < 6 ? 8.0 : 0),
            child: _DayButton(
              label: _dayNames[index],
              fullLabel: _fullDayNames[index],
              isSelected: isSelected,
              onTap: () {
                final newSelection = Set<int>.from(selectedDays);
                if (isSelected) {
                  newSelection.remove(day);
                } else {
                  newSelection.add(day);
                }
                onSelectionChanged(newSelection);
              },
            ),
          ),
        );
      }),
    );
  }
}

class _DayButton extends StatelessWidget {
  final String label;
  final String fullLabel;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayButton({
    required this.label,
    required this.fullLabel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: fullLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Time picker field for routine setup.
/// Shows selected time and opens time picker on tap.
class TimePickerField extends StatelessWidget {
  final TimeOfDay? selectedTime;
  final String label;
  final Function(TimeOfDay) onTimeSelected;

  const TimePickerField({
    super.key,
    required this.selectedTime,
    required this.label,
    required this.onTimeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayTime = selectedTime != null
        ? _formatTimeOfDay(selectedTime!)
        : 'Select time';

    return InkWell(
      onTap: () => _showTimePicker(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.access_time,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayTime,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTimePicker(BuildContext context) async {
    final initialTime = selectedTime ?? const TimeOfDay(hour: 9, minute: 0);
    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        );
      },
    );

    if (time != null) {
      onTimeSelected(time);
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Duration picker field for routine setup.
/// Shows selected duration and allows adjustment via stepper.
class DurationPickerField extends StatelessWidget {
  final int durationMinutes;
  final String label;
  final int minMinutes;
  final int maxMinutes;
  final int stepMinutes;
  final Function(int) onDurationChanged;

  const DurationPickerField({
    super.key,
    required this.durationMinutes,
    required this.label,
    this.minMinutes = 5,
    this.maxMinutes = 180,
    this.stepMinutes = 5,
    required this.onDurationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: durationMinutes > minMinutes
                    ? () => onDurationChanged(
                          (durationMinutes - stepMinutes).clamp(minMinutes, maxMinutes),
                        )
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                iconSize: 32,
              ),
              const SizedBox(width: 16),
              Text(
                _formatDuration(durationMinutes),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: durationMinutes < maxMinutes
                    ? () => onDurationChanged(
                          (durationMinutes + stepMinutes).clamp(minMinutes, maxMinutes),
                        )
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                iconSize: 32,
              ),
            ],
          ),
        ],
      ),
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
}

/// Direction selector for commute setup.
/// Allows selecting to work, from work, or both.
enum CommuteDirection { toWork, fromWork, both }

class CommuteDirectionSelector extends StatelessWidget {
  final CommuteDirection selectedDirection;
  final Function(CommuteDirection) onDirectionChanged;

  const CommuteDirectionSelector({
    super.key,
    required this.selectedDirection,
    required this.onDirectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Direction',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DirectionButton(
                label: 'To Work',
                icon: Icons.arrow_forward,
                isSelected: selectedDirection == CommuteDirection.toWork,
                onTap: () => onDirectionChanged(CommuteDirection.toWork),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DirectionButton(
                label: 'From Work',
                icon: Icons.arrow_back,
                isSelected: selectedDirection == CommuteDirection.fromWork,
                onTap: () => onDirectionChanged(CommuteDirection.fromWork),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DirectionButton(
                label: 'Both',
                icon: Icons.swap_horiz,
                isSelected: selectedDirection == CommuteDirection.both,
                onTap: () => onDirectionChanged(CommuteDirection.both),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DirectionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _DirectionButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
