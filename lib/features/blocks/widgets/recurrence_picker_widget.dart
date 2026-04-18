import 'package:flutter/material.dart';

/// Recurrence frequency options
enum RecurrenceFrequency {
  none,
  daily,
  weekly,
  monthly,
  yearly,
}

/// Widget for picking recurrence patterns and generating RRULE strings.
/// Supports daily, weekly, monthly, and yearly frequencies.
class RecurrencePickerWidget extends StatefulWidget {
  final String? initialRecurrenceRule;
  final ValueChanged<String?> onChanged;

  const RecurrencePickerWidget({
    super.key,
    this.initialRecurrenceRule,
    required this.onChanged,
  });

  @override
  State<RecurrencePickerWidget> createState() => _RecurrencePickerWidgetState();
}

class _RecurrencePickerWidgetState extends State<RecurrencePickerWidget> {
  RecurrenceFrequency _frequency = RecurrenceFrequency.none;
  final Set<int> _selectedWeekdays = {};
  int _interval = 1;
  int? _count;
  DateTime? _until;

  @override
  void initState() {
    super.initState();
    if (widget.initialRecurrenceRule != null) {
      _parseRRULE(widget.initialRecurrenceRule!);
    }
  }

  /// Parse an RRULE string and populate the state
  void _parseRRULE(String rrule) {
    final parts = rrule.split(';');
    
    for (final part in parts) {
      final keyValue = part.split('=');
      if (keyValue.length != 2) continue;
      
      final key = keyValue[0];
      final value = keyValue[1];
      
      switch (key) {
        case 'FREQ':
          switch (value) {
            case 'DAILY':
              _frequency = RecurrenceFrequency.daily;
              break;
            case 'WEEKLY':
              _frequency = RecurrenceFrequency.weekly;
              break;
            case 'MONTHLY':
              _frequency = RecurrenceFrequency.monthly;
              break;
            case 'YEARLY':
              _frequency = RecurrenceFrequency.yearly;
              break;
          }
          break;
        case 'INTERVAL':
          _interval = int.tryParse(value) ?? 1;
          break;
        case 'BYDAY':
          _selectedWeekdays.clear();
          for (final day in value.split(',')) {
            final dayNum = _weekdayFromString(day);
            if (dayNum != null) {
              _selectedWeekdays.add(dayNum);
            }
          }
          break;
        case 'COUNT':
          _count = int.tryParse(value);
          break;
        case 'UNTIL':
          _until = _parseRruleUntil(value);
          break;
      }
    }
  }

  /// Convert weekday string to DateTime weekday (1 = Monday, 7 = Sunday)
  int? _weekdayFromString(String day) {
    switch (day.toUpperCase()) {
      case 'MO':
        return 1;
      case 'TU':
        return 2;
      case 'WE':
        return 3;
      case 'TH':
        return 4;
      case 'FR':
        return 5;
      case 'SA':
        return 6;
      case 'SU':
        return 7;
      default:
        return null;
    }
  }

  /// Convert DateTime weekday to RRULE string
  String _weekdayToString(int weekday) {
    switch (weekday) {
      case 1:
        return 'MO';
      case 2:
        return 'TU';
      case 3:
        return 'WE';
      case 4:
        return 'TH';
      case 5:
        return 'FR';
      case 6:
        return 'SA';
      case 7:
        return 'SU';
      default:
        return 'MO';
    }
  }

  /// Parse RRULE UNTIL format (YYYYMMDDTHHMMSSz) into a UTC DateTime.
  /// Returns null if the value is not a valid RRULE UNTIL string.
  static DateTime? _parseRruleUntil(String until) {
    final regex = RegExp(r'(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z?');
    final match = regex.firstMatch(until);
    if (match == null) return null;
    return DateTime.utc(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
  }

  /// Serialize a DateTime to the RRULE UNTIL compact format (YYYYMMDDTHHMMSSz).
  static String _formatRruleUntil(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}'
        'T${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }

  /// Generate RRULE string from current state
  String? _generateRRULE() {
    if (_frequency == RecurrenceFrequency.none) {
      return null;
    }

    final parts = <String>[];

    // Add frequency
    switch (_frequency) {
      case RecurrenceFrequency.daily:
        parts.add('FREQ=DAILY');
        break;
      case RecurrenceFrequency.weekly:
        parts.add('FREQ=WEEKLY');
        break;
      case RecurrenceFrequency.monthly:
        parts.add('FREQ=MONTHLY');
        break;
      case RecurrenceFrequency.yearly:
        parts.add('FREQ=YEARLY');
        break;
      case RecurrenceFrequency.none:
        return null;
    }

    // Add interval if > 1
    if (_interval > 1) {
      parts.add('INTERVAL=$_interval');
    }

    // Add weekdays for weekly frequency
    if (_frequency == RecurrenceFrequency.weekly && _selectedWeekdays.isNotEmpty) {
      final days = _selectedWeekdays.toList()..sort();
      final dayStrings = days.map(_weekdayToString).join(',');
      parts.add('BYDAY=$dayStrings');
    }

    // Add count or until
    if (_count != null) {
      parts.add('COUNT=$_count');
    } else if (_until != null) {
      parts.add('UNTIL=${_formatRruleUntil(_until!)}');
    }

    return parts.join(';');
  }

  /// Update the recurrence rule and notify parent
  void _updateRecurrence() {
    final rrule = _generateRRULE();
    widget.onChanged(rrule);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recurrence',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        
        // Frequency dropdown
        DropdownButtonFormField<RecurrenceFrequency>(
          initialValue: _frequency,
          decoration: const InputDecoration(
            labelText: 'Repeat',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: RecurrenceFrequency.none,
              child: Text('Does not repeat'),
            ),
            DropdownMenuItem(
              value: RecurrenceFrequency.daily,
              child: Text('Daily'),
            ),
            DropdownMenuItem(
              value: RecurrenceFrequency.weekly,
              child: Text('Weekly'),
            ),
            DropdownMenuItem(
              value: RecurrenceFrequency.monthly,
              child: Text('Monthly'),
            ),
            DropdownMenuItem(
              value: RecurrenceFrequency.yearly,
              child: Text('Yearly'),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _frequency = value ?? RecurrenceFrequency.none;
            });
            _updateRecurrence();
          },
        ),

        // Weekday picker (only for weekly frequency)
        if (_frequency == RecurrenceFrequency.weekly) ...[
          const SizedBox(height: 16),
          Text(
            'Repeat on',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (int i = 1; i <= 7; i++)
                FilterChip(
                  label: Text(_getWeekdayLabel(i)),
                  selected: _selectedWeekdays.contains(i),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedWeekdays.add(i);
                      } else {
                        _selectedWeekdays.remove(i);
                      }
                    });
                    _updateRecurrence();
                  },
                ),
            ],
          ),
        ],

        // Interval picker
        if (_frequency != RecurrenceFrequency.none) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Repeat every '),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _interval,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  items: List.generate(30, (index) => index + 1)
                      .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _interval = value ?? 1;
                    });
                    _updateRecurrence();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(_getIntervalLabel()),
            ],
          ),
        ],
      ],
    );
  }

  /// Get short weekday label
  String _getWeekdayLabel(int weekday) {
    switch (weekday) {
      case 1:
        return 'Mon';
      case 2:
        return 'Tue';
      case 3:
        return 'Wed';
      case 4:
        return 'Thu';
      case 5:
        return 'Fri';
      case 6:
        return 'Sat';
      case 7:
        return 'Sun';
      default:
        return '';
    }
  }

  /// Get interval label based on frequency
  String _getIntervalLabel() {
    switch (_frequency) {
      case RecurrenceFrequency.daily:
        return _interval == 1 ? 'day' : 'days';
      case RecurrenceFrequency.weekly:
        return _interval == 1 ? 'week' : 'weeks';
      case RecurrenceFrequency.monthly:
        return _interval == 1 ? 'month' : 'months';
      case RecurrenceFrequency.yearly:
        return _interval == 1 ? 'year' : 'years';
      default:
        return '';
    }
  }
}
