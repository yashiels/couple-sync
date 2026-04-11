import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/router/routes.dart';
import '../../../core/models/time_block.dart';
import '../../../services/providers/auth_state_provider.dart';
import '../widgets/routine_step_widget.dart';

/// Multi-step routine setup wizard with 3 steps:
/// 1. Sleep Setup - Start time, end time, days
/// 2. Work/Study Setup - Work hours and days
/// 3. Commute Setup - Duration and direction
class RoutineWizardScreen extends ConsumerStatefulWidget {
  const RoutineWizardScreen({super.key});

  @override
  ConsumerState<RoutineWizardScreen> createState() => _RoutineWizardScreenState();
}

class _RoutineWizardScreenState extends ConsumerState<RoutineWizardScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isSaving = false;
  String? _error;

  // Step 1: Sleep data
  TimeOfDay? _sleepStartTime;
  TimeOfDay? _sleepEndTime;
  Set<int> _sleepDays = {1, 2, 3, 4, 5, 6, 7}; // All days by default

  // Step 2: Work/Study data
  TimeOfDay? _workStartTime;
  TimeOfDay? _workEndTime;
  Set<int> _workDays = {1, 2, 3, 4, 5}; // Weekdays by default

  // Step 3: Commute data
  int _commuteDurationMinutes = 30;
  CommuteDirection _commuteDirection = CommuteDirection.both;

  static const _totalSteps = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep++;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentStep--;
      });
    }
  }

  void _skipStep() {
    _nextStep();
  }

  Future<void> _finishWizard() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final uid = ref.read(authStateProvider).uid;
      final userProfile = ref.read(authStateProvider).userProfile;
      final timezone = userProfile?.timezone ?? 'UTC';

      if (uid == null) {
        setState(() {
          _isSaving = false;
          _error = 'Not authenticated. Please sign in again.';
        });
        return;
      }

      final blocks = <TimeBlock>[];
      final now = DateTime.now();

      // Create Sleep TimeBlock if configured
      if (_sleepStartTime != null && _sleepEndTime != null && _sleepDays.isNotEmpty) {
        blocks.add(_createTimeBlock(
          userId: uid,
          title: 'Sleep',
          category: TimeBlockCategory.sleep,
          startTime: _sleepStartTime!,
          endTime: _sleepEndTime!,
          days: _sleepDays,
          timezone: timezone,
          createdAt: now,
        ));
      }

      // Create Work/Study TimeBlock if configured
      if (_workStartTime != null && _workEndTime != null && _workDays.isNotEmpty) {
        blocks.add(_createTimeBlock(
          userId: uid,
          title: 'Work/Study',
          category: TimeBlockCategory.work,
          startTime: _workStartTime!,
          endTime: _workEndTime!,
          days: _workDays,
          timezone: timezone,
          createdAt: now,
        ));
      }

      // Create Commute TimeBlock if configured (only if direction is selected)
      if (_commuteDurationMinutes > 0) {
        if (_commuteDirection == CommuteDirection.toWork ||
            _commuteDirection == CommuteDirection.both) {
          // Morning commute - before work
          if (_workStartTime != null) {
            final commuteEnd = TimeOfDay(
              hour: _workStartTime!.hour,
              minute: _workStartTime!.minute,
            );
            final commuteStartMinutes = 
                (commuteEnd.hour * 60 + commuteEnd.minute) - _commuteDurationMinutes;
            final commuteStart = TimeOfDay(
              hour: (commuteStartMinutes ~/ 60) % 24,
              minute: commuteStartMinutes % 60,
            );
            blocks.add(_createTimeBlock(
              userId: uid,
              title: 'Morning Commute',
              category: TimeBlockCategory.commute,
              startTime: commuteStart,
              endTime: commuteEnd,
              days: _workDays,
              timezone: timezone,
              createdAt: now,
            ));
          }
        }
        if (_commuteDirection == CommuteDirection.fromWork ||
            _commuteDirection == CommuteDirection.both) {
          // Evening commute - after work
          if (_workEndTime != null) {
            final commuteStart = TimeOfDay(
              hour: _workEndTime!.hour,
              minute: _workEndTime!.minute,
            );
            final commuteEndMinutes = 
                (commuteStart.hour * 60 + commuteStart.minute) + _commuteDurationMinutes;
            final commuteEnd = TimeOfDay(
              hour: (commuteEndMinutes ~/ 60) % 24,
              minute: commuteEndMinutes % 60,
            );
            blocks.add(_createTimeBlock(
              userId: uid,
              title: 'Evening Commute',
              category: TimeBlockCategory.commute,
              startTime: commuteStart,
              endTime: commuteEnd,
              days: _workDays,
              timezone: timezone,
              createdAt: now,
            ));
          }
        }
      }

      // Save all blocks to Firestore
      final batch = FirebaseFirestore.instance.batch();
      final coupleId = userProfile?.coupleId;

      for (final block in blocks) {
        final DocumentReference docRef;
        if (coupleId != null) {
          // User is paired — save to shared timeblocks collection
          docRef = FirebaseFirestore.instance
              .collection('timeblocks')
              .doc(coupleId)
              .collection('blocks')
              .doc();
        } else {
          // User is not yet paired — save to personal pending blocks
          final blockUid = uid;
          docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(blockUid)
              .collection('pendingBlocks')
              .doc();
        }
        batch.set(docRef, block.toJson());
      }

      await batch.commit();

      // Refresh auth state and navigate
      await ref.read(authStateProvider.notifier).refreshProfile();

      if (mounted) {
        context.go(AppRoutes.pairing);
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = _getFirebaseErrorMessage(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = 'An unexpected error occurred. Please try again.';
        });
      }
    }
  }

  /// Creates a TimeBlock with RRULE for recurring weekly events.
  TimeBlock _createTimeBlock({
    required String userId,
    required String title,
    required TimeBlockCategory category,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required Set<int> days,
    required String timezone,
    required DateTime createdAt,
  }) {
    // Convert local time to UTC timestamps
    // Use next Monday as reference date for the first occurrence
    final now = DateTime.now();
    var referenceDate = now;
    
    // Find the first selected day
    for (var i = 0; i < 7; i++) {
      final checkDate = now.add(Duration(days: i));
      final weekday = checkDate.weekday; // 1 = Monday, 7 = Sunday
      if (days.contains(weekday)) {
        referenceDate = checkDate;
        break;
      }
    }

    // Create start and end times in local timezone
    final startLocal = tz.TZDateTime(
      tz.getLocation(timezone),
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
      startTime.hour,
      startTime.minute,
    );

    // Handle overnight blocks (e.g., sleep from 22:00 to 06:00)
    var endLocal = tz.TZDateTime(
      tz.getLocation(timezone),
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
      endTime.hour,
      endTime.minute,
    );
    if (endLocal.isBefore(startLocal)) {
      // End time is on the next day
      endLocal = endLocal.add(const Duration(days: 1));
    }

    // Convert to UTC milliseconds
    final startUtc = startLocal.toUtc().millisecondsSinceEpoch;
    final endUtc = endLocal.toUtc().millisecondsSinceEpoch;

    // Generate RRULE string (FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR)
    final rrule = _generateRRule(days);

    return TimeBlock(
      userId: userId,
      title: title,
      type: TimeBlockType.busy,
      category: category,
      startUtc: startUtc,
      endUtc: endUtc,
      timezone: timezone,
      recurrenceRule: rrule,
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: createdAt,
    );
  }

  /// Generates an RRULE string for weekly recurrence.
  /// E.g., FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
  String _generateRRule(Set<int> days) {
    const dayNames = ['', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    final byDay = days.map((d) => dayNames[d]).toList();
    byDay.sort((a, b) {
      // Sort in weekday order (MO, TU, WE, TH, FR, SA, SU)
      const order = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
      return order.indexOf(a) - order.indexOf(b);
    });
    return 'FREQ=WEEKLY;BYDAY=${byDay.join(',')}';
  }

  String _getFirebaseErrorMessage(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission denied. Please sign in again.';
      case 'unavailable':
        return 'Network error. Please check your connection.';
      default:
        return 'Failed to save routine. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Set Up Your Routine (${_currentStep + 1}/$_totalSteps)'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Progress indicator
          LinearProgressIndicator(
            value: (_currentStep + 1) / _totalSteps,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),

          // Error message
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: theme.colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Page view for steps
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _SleepStep(
                  startTime: _sleepStartTime,
                  endTime: _sleepEndTime,
                  selectedDays: _sleepDays,
                  onStartTimeChanged: (time) {
                    setState(() {
                      _sleepStartTime = time;
                    });
                  },
                  onEndTimeChanged: (time) {
                    setState(() {
                      _sleepEndTime = time;
                    });
                  },
                  onDaysChanged: (days) {
                    setState(() {
                      _sleepDays = days;
                    });
                  },
                ),
                _WorkStep(
                  startTime: _workStartTime,
                  endTime: _workEndTime,
                  selectedDays: _workDays,
                  onStartTimeChanged: (time) {
                    setState(() {
                      _workStartTime = time;
                    });
                  },
                  onEndTimeChanged: (time) {
                    setState(() {
                      _workEndTime = time;
                    });
                  },
                  onDaysChanged: (days) {
                    setState(() {
                      _workDays = days;
                    });
                  },
                ),
                _CommuteStep(
                  durationMinutes: _commuteDurationMinutes,
                  direction: _commuteDirection,
                  onDurationChanged: (duration) {
                    setState(() {
                      _commuteDurationMinutes = duration;
                    });
                  },
                  onDirectionChanged: (direction) {
                    setState(() {
                      _commuteDirection = direction;
                    });
                  },
                ),
              ],
            ),
          ),

          // Navigation buttons
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _previousStep,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                      ),
                    ),
                  if (_currentStep > 0) const SizedBox(width: 16),
                  Expanded(
                    child: _currentStep < _totalSteps - 1
                        ? _buildSkipNextButtons()
                        : _buildFinishButton(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkipNextButtons() {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: _skipStep,
            child: const Text('Skip'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _nextStep,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Next'),
          ),
        ),
      ],
    );
  }

  Widget _buildFinishButton() {
    return FilledButton.icon(
      onPressed: _isSaving ? null : _finishWizard,
      icon: _isSaving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.check),
      label: Text(_isSaving ? 'Saving...' : 'Finish'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}

/// Step 1: Sleep Setup
class _SleepStep extends StatelessWidget {
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final Set<int> selectedDays;
  final Function(TimeOfDay) onStartTimeChanged;
  final Function(TimeOfDay) onEndTimeChanged;
  final Function(Set<int>) onDaysChanged;

  const _SleepStep({
    required this.startTime,
    required this.endTime,
    required this.selectedDays,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Icon(
            Icons.bedtime,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Sleep Schedule',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When do you usually sleep? This helps us find free time for both of you.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Time pickers
          TimePickerField(
            selectedTime: startTime,
            label: 'Bedtime',
            onTimeSelected: onStartTimeChanged,
          ),
          const SizedBox(height: 16),
          TimePickerField(
            selectedTime: endTime,
            label: 'Wake up time',
            onTimeSelected: onEndTimeChanged,
          ),
          const SizedBox(height: 32),

          // Day selection
          Text(
            'Days',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select the days you follow this sleep schedule',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          DayOfWeekSelector(
            selectedDays: selectedDays,
            onSelectionChanged: onDaysChanged,
          ),
        ],
      ),
    );
  }
}

/// Step 2: Work/Study Setup
class _WorkStep extends StatelessWidget {
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final Set<int> selectedDays;
  final Function(TimeOfDay) onStartTimeChanged;
  final Function(TimeOfDay) onEndTimeChanged;
  final Function(Set<int>) onDaysChanged;

  const _WorkStep({
    required this.startTime,
    required this.endTime,
    required this.selectedDays,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Icon(
            Icons.work,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Work/Study Hours',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When are you usually at work or studying? This could also be classes.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Time pickers
          TimePickerField(
            selectedTime: startTime,
            label: 'Start time',
            onTimeSelected: onStartTimeChanged,
          ),
          const SizedBox(height: 16),
          TimePickerField(
            selectedTime: endTime,
            label: 'End time',
            onTimeSelected: onEndTimeChanged,
          ),
          const SizedBox(height: 32),

          // Day selection
          Text(
            'Days',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select the days you work or study',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          DayOfWeekSelector(
            selectedDays: selectedDays,
            onSelectionChanged: onDaysChanged,
          ),
        ],
      ),
    );
  }
}

/// Step 3: Commute Setup
class _CommuteStep extends StatelessWidget {
  final int durationMinutes;
  final CommuteDirection direction;
  final Function(int) onDurationChanged;
  final Function(CommuteDirection) onDirectionChanged;

  const _CommuteStep({
    required this.durationMinutes,
    required this.direction,
    required this.onDurationChanged,
    required this.onDirectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Icon(
            Icons.directions_car,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Commute Time',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How long does it take you to get to work? This helps us avoid suggesting times when you\'re traveling.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // Duration picker
          DurationPickerField(
            durationMinutes: durationMinutes,
            label: 'Commute duration',
            minMinutes: 5,
            maxMinutes: 180,
            stepMinutes: 5,
            onDurationChanged: onDurationChanged,
          ),
          const SizedBox(height: 32),

          // Direction selector
          CommuteDirectionSelector(
            selectedDirection: direction,
            onDirectionChanged: onDirectionChanged,
          ),
        ],
      ),
    );
  }
}
