import 'package:couple_sync/features/blocks/widgets/recurrence_picker_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildSubject({
  String? initialRecurrenceRule,
  ValueChanged<String?>? onChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RecurrencePickerWidget(
          initialRecurrenceRule: initialRecurrenceRule,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  group('RecurrencePickerWidget', () {
    testWidgets('renders Recurrence title', (tester) async {
      await tester.pumpWidget(_buildSubject());

      expect(find.text('Recurrence'), findsOneWidget);
    });

    testWidgets('renders frequency dropdown with default "Does not repeat"', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject());

      expect(find.text('Does not repeat'), findsOneWidget);
    });

    testWidgets('does not show interval picker when frequency is none', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject());

      expect(find.text('Repeat every '), findsNothing);
    });

    testWidgets('shows interval picker when frequency is daily', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject());

      // Open dropdown and select Daily
      await tester.tap(find.text('Does not repeat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily').last);
      await tester.pumpAndSettle();

      expect(find.text('Repeat every '), findsOneWidget);
      expect(find.text('day'), findsOneWidget);
    });

    testWidgets('shows weekday chips when frequency is weekly', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Open dropdown and select Weekly
      await tester.tap(find.text('Does not repeat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekly').last);
      await tester.pumpAndSettle();

      expect(find.text('Repeat on'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Tue'), findsOneWidget);
      expect(find.text('Wed'), findsOneWidget);
      expect(find.text('Thu'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
      expect(find.text('Sat'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('does not show weekday chips for daily frequency', (
      tester,
    ) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.text('Does not repeat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily').last);
      await tester.pumpAndSettle();

      expect(find.text('Repeat on'), findsNothing);
      expect(find.text('Mon'), findsNothing);
    });

    testWidgets('emits null when frequency set to none', (tester) async {
      String? emitted = 'initial';
      await tester.pumpWidget(
        _buildSubject(
          initialRecurrenceRule: 'FREQ=DAILY',
          onChanged: (value) => emitted = value,
        ),
      );

      // Should currently be Daily; change to none
      await tester.tap(find.text('Daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Does not repeat').last);
      await tester.pumpAndSettle();

      expect(emitted, isNull);
    });

    testWidgets('emits FREQ=DAILY when daily selected', (tester) async {
      String? emitted;
      await tester.pumpWidget(
        _buildSubject(onChanged: (value) => emitted = value),
      );

      await tester.tap(find.text('Does not repeat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily').last);
      await tester.pumpAndSettle();

      expect(emitted, equals('FREQ=DAILY'));
    });

    testWidgets('emits FREQ=WEEKLY when weekly selected', (tester) async {
      String? emitted;
      await tester.pumpWidget(
        _buildSubject(onChanged: (value) => emitted = value),
      );

      await tester.tap(find.text('Does not repeat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekly').last);
      await tester.pumpAndSettle();

      expect(emitted, equals('FREQ=WEEKLY'));
    });

    testWidgets('emits FREQ=MONTHLY when monthly selected', (tester) async {
      String? emitted;
      await tester.pumpWidget(
        _buildSubject(onChanged: (value) => emitted = value),
      );

      await tester.tap(find.text('Does not repeat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly').last);
      await tester.pumpAndSettle();

      expect(emitted, equals('FREQ=MONTHLY'));
    });

    testWidgets('emits FREQ=YEARLY when yearly selected', (tester) async {
      String? emitted;
      await tester.pumpWidget(
        _buildSubject(onChanged: (value) => emitted = value),
      );

      await tester.tap(find.text('Does not repeat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yearly').last);
      await tester.pumpAndSettle();

      expect(emitted, equals('FREQ=YEARLY'));
    });

    group('parses initial RRULE', () {
      testWidgets('parses FREQ=WEEKLY with BYDAY', (tester) async {
        await tester.pumpWidget(
          _buildSubject(initialRecurrenceRule: 'FREQ=WEEKLY;BYDAY=MO,WE,FR'),
        );

        // Should show Weekly selected
        expect(find.text('Weekly'), findsOneWidget);
        // Weekday chips should be visible
        expect(find.text('Mon'), findsOneWidget);
      });

      testWidgets('parses FREQ=DAILY with INTERVAL', (tester) async {
        await tester.pumpWidget(
          _buildSubject(initialRecurrenceRule: 'FREQ=DAILY;INTERVAL=3'),
        );

        expect(find.text('Daily'), findsOneWidget);
        expect(find.text('Repeat every '), findsOneWidget);
      });

      testWidgets('parses FREQ=MONTHLY', (tester) async {
        await tester.pumpWidget(
          _buildSubject(initialRecurrenceRule: 'FREQ=MONTHLY'),
        );

        expect(find.text('Monthly'), findsOneWidget);
      });
    });

    group('interval labels', () {
      testWidgets('shows "week" for weekly frequency', (tester) async {
        await tester.pumpWidget(_buildSubject());

        await tester.tap(find.text('Does not repeat'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Weekly').last);
        await tester.pumpAndSettle();

        expect(find.text('week'), findsOneWidget);
      });

      testWidgets('shows "month" for monthly frequency', (tester) async {
        await tester.pumpWidget(_buildSubject());

        await tester.tap(find.text('Does not repeat'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Monthly').last);
        await tester.pumpAndSettle();

        expect(find.text('month'), findsOneWidget);
      });

      testWidgets('shows "year" for yearly frequency', (tester) async {
        await tester.pumpWidget(_buildSubject());

        await tester.tap(find.text('Does not repeat'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yearly').last);
        await tester.pumpAndSettle();

        expect(find.text('year'), findsOneWidget);
      });
    });

    group('weekday selection', () {
      testWidgets('tapping a weekday chip emits BYDAY in RRULE', (
        tester,
      ) async {
        String? emitted;
        await tester.pumpWidget(
          _buildSubject(onChanged: (value) => emitted = value),
        );

        // Select Weekly
        await tester.tap(find.text('Does not repeat'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Weekly').last);
        await tester.pumpAndSettle();

        // Tap Monday chip
        await tester.tap(find.text('Mon'));
        await tester.pumpAndSettle();

        expect(emitted, equals('FREQ=WEEKLY;BYDAY=MO'));
      });

      testWidgets('tapping multiple weekdays emits sorted BYDAY', (
        tester,
      ) async {
        String? emitted;
        await tester.pumpWidget(
          _buildSubject(onChanged: (value) => emitted = value),
        );

        // Select Weekly
        await tester.tap(find.text('Does not repeat'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Weekly').last);
        await tester.pumpAndSettle();

        // Tap Friday then Monday (out of order)
        await tester.tap(find.text('Fri'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mon'));
        await tester.pumpAndSettle();

        // Should be sorted: MO,FR
        expect(emitted, equals('FREQ=WEEKLY;BYDAY=MO,FR'));
      });
    });
  });

  group('RecurrenceFrequency enum', () {
    test('has 5 values', () {
      expect(RecurrenceFrequency.values.length, equals(5));
    });

    test('contains expected values', () {
      expect(RecurrenceFrequency.values, contains(RecurrenceFrequency.none));
      expect(RecurrenceFrequency.values, contains(RecurrenceFrequency.daily));
      expect(RecurrenceFrequency.values, contains(RecurrenceFrequency.weekly));
      expect(RecurrenceFrequency.values, contains(RecurrenceFrequency.monthly));
      expect(RecurrenceFrequency.values, contains(RecurrenceFrequency.yearly));
    });
  });
}
