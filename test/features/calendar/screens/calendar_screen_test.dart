import 'package:couple_sync/features/calendar/screens/calendar_screen.dart';
import 'package:couple_sync/features/calendar/week_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _buildSubject() {
  return const MaterialApp(
    home: CalendarScreen(),
  );
}

void main() {
  group('CalendarScreen', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(CalendarScreen), findsOneWidget);
    });

    testWidgets('delegates to WeekViewScreen', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(WeekViewScreen), findsOneWidget);
    });

    testWidgets('shows Calendar title in app bar', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Calendar'), findsOneWidget);
    });

    testWidgets('shows today button in app bar', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.today), findsOneWidget);
    });

    testWidgets('shows FAB with add icon', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
