import 'package:couple_sync/features/onboarding/widgets/routine_step_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DayOfWeekSelector', () {
    testWidgets('renders 7 day buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayOfWeekSelector(
              selectedDays: const {1, 2, 3, 4, 5},
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      );

      // M, T, W, T, F, S, S
      expect(find.text('M'), findsOneWidget);
      expect(find.text('T'), findsNWidgets(2)); // Tuesday and Thursday
      expect(find.text('W'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
      expect(find.text('S'), findsNWidgets(2)); // Saturday and Sunday
    });

    testWidgets('calls onSelectionChanged when day is toggled off',
        (tester) async {
      Set<int>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayOfWeekSelector(
              selectedDays: const {1, 2, 3, 4, 5},
              onSelectionChanged: (days) => result = days,
            ),
          ),
        ),
      );

      // Tap Monday (M) to deselect it
      await tester.tap(find.text('M'));
      await tester.pump();

      expect(result, isNotNull);
      expect(result!.contains(1), isFalse);
      expect(result!.length, 4);
    });

    testWidgets('calls onSelectionChanged when day is toggled on',
        (tester) async {
      Set<int>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayOfWeekSelector(
              selectedDays: const {1, 2, 3, 4, 5},
              onSelectionChanged: (days) => result = days,
            ),
          ),
        ),
      );

      // Tap first S (Saturday = 6) to select it
      await tester.tap(find.text('S').first);
      await tester.pump();

      expect(result, isNotNull);
      expect(result!.contains(6), isTrue);
      expect(result!.length, 6);
    });

    testWidgets('renders with empty selection', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayOfWeekSelector(
              selectedDays: const {},
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('M'), findsOneWidget);
    });

    testWidgets('renders with all days selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DayOfWeekSelector(
              selectedDays: const {1, 2, 3, 4, 5, 6, 7},
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('M'), findsOneWidget);
    });
  });

  group('TimePickerField', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimePickerField(
              selectedTime: null,
              label: 'Bedtime',
              onTimeSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Bedtime'), findsOneWidget);
    });

    testWidgets('shows "Select time" when no time selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimePickerField(
              selectedTime: null,
              label: 'Start time',
              onTimeSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Select time'), findsOneWidget);
    });

    testWidgets('shows formatted time when time is selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimePickerField(
              selectedTime: const TimeOfDay(hour: 22, minute: 30),
              label: 'Bedtime',
              onTimeSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('22:30'), findsOneWidget);
    });

    testWidgets('shows clock icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimePickerField(
              selectedTime: null,
              label: 'Start time',
              onTimeSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('shows chevron right icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimePickerField(
              selectedTime: null,
              label: 'Start time',
              onTimeSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('formats single digit hours with leading zero',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimePickerField(
              selectedTime: const TimeOfDay(hour: 6, minute: 0),
              label: 'Wake up',
              onTimeSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('06:00'), findsOneWidget);
    });

    testWidgets('formats single digit minutes with leading zero',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimePickerField(
              selectedTime: const TimeOfDay(hour: 12, minute: 5),
              label: 'Lunch',
              onTimeSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('12:05'), findsOneWidget);
    });
  });

  group('DurationPickerField', () {
    testWidgets('renders label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPickerField(
              durationMinutes: 30,
              label: 'Commute duration',
              onDurationChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Commute duration'), findsOneWidget);
    });

    testWidgets('shows duration in minutes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPickerField(
              durationMinutes: 45,
              label: 'Duration',
              onDurationChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('45 min'), findsOneWidget);
    });

    testWidgets('shows duration in hours when 60+ minutes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPickerField(
              durationMinutes: 60,
              label: 'Duration',
              onDurationChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('1 hr'), findsOneWidget);
    });

    testWidgets('shows hours and minutes for mixed duration', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPickerField(
              durationMinutes: 90,
              label: 'Duration',
              onDurationChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('1 hr 30 min'), findsOneWidget);
    });

    testWidgets('increment button calls onDurationChanged', (tester) async {
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPickerField(
              durationMinutes: 30,
              label: 'Duration',
              stepMinutes: 5,
              maxMinutes: 180,
              minMinutes: 5,
              onDurationChanged: (v) => result = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();

      expect(result, 35);
    });

    testWidgets('decrement button calls onDurationChanged', (tester) async {
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPickerField(
              durationMinutes: 30,
              label: 'Duration',
              stepMinutes: 5,
              maxMinutes: 180,
              minMinutes: 5,
              onDurationChanged: (v) => result = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();

      expect(result, 25);
    });

    testWidgets('decrement button disabled at minimum', (tester) async {
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPickerField(
              durationMinutes: 5,
              label: 'Duration',
              stepMinutes: 5,
              maxMinutes: 180,
              minMinutes: 5,
              onDurationChanged: (v) => result = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();

      expect(result, isNull); // Should not call callback
    });

    testWidgets('increment button disabled at maximum', (tester) async {
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPickerField(
              durationMinutes: 180,
              label: 'Duration',
              stepMinutes: 5,
              maxMinutes: 180,
              minMinutes: 5,
              onDurationChanged: (v) => result = v,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();

      expect(result, isNull); // Should not call callback
    });

    testWidgets('shows + and - icons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationPickerField(
              durationMinutes: 30,
              label: 'Duration',
              onDurationChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    });
  });

  group('CommuteDirectionSelector', () {
    testWidgets('renders three direction buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommuteDirectionSelector(
              selectedDirection: CommuteDirection.both,
              onDirectionChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('To Work'), findsOneWidget);
      expect(find.text('From Work'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
    });

    testWidgets('renders direction icons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommuteDirectionSelector(
              selectedDirection: CommuteDirection.both,
              onDirectionChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    });

    testWidgets('calls onDirectionChanged when To Work is tapped',
        (tester) async {
      CommuteDirection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommuteDirectionSelector(
              selectedDirection: CommuteDirection.both,
              onDirectionChanged: (d) => result = d,
            ),
          ),
        ),
      );

      await tester.tap(find.text('To Work'));
      await tester.pump();

      expect(result, CommuteDirection.toWork);
    });

    testWidgets('calls onDirectionChanged when From Work is tapped',
        (tester) async {
      CommuteDirection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommuteDirectionSelector(
              selectedDirection: CommuteDirection.both,
              onDirectionChanged: (d) => result = d,
            ),
          ),
        ),
      );

      await tester.tap(find.text('From Work'));
      await tester.pump();

      expect(result, CommuteDirection.fromWork);
    });

    testWidgets('calls onDirectionChanged when Both is tapped',
        (tester) async {
      CommuteDirection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommuteDirectionSelector(
              selectedDirection: CommuteDirection.toWork,
              onDirectionChanged: (d) => result = d,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Both'));
      await tester.pump();

      expect(result, CommuteDirection.both);
    });

    testWidgets('shows Direction label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommuteDirectionSelector(
              selectedDirection: CommuteDirection.both,
              onDirectionChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Direction'), findsOneWidget);
    });
  });

  group('CommuteDirection enum', () {
    test('has three values', () {
      expect(CommuteDirection.values.length, 3);
    });

    test('contains toWork, fromWork, and both', () {
      expect(CommuteDirection.values,
          contains(CommuteDirection.toWork));
      expect(CommuteDirection.values,
          contains(CommuteDirection.fromWork));
      expect(CommuteDirection.values,
          contains(CommuteDirection.both));
    });
  });
}
