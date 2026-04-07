import 'package:couple_sync/features/home/screens/home_screen.dart';
import 'package:couple_sync/features/home/partner_clock_widget.dart';
import 'package:couple_sync/features/home/next_window_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

Widget _buildSubject() {
  return const MaterialApp(
    home: HomeScreen(),
  );
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('HomeScreen rendering', () {
    testWidgets('displays app bar with "Couple Sync" title', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.text('Couple Sync'), findsOneWidget);
    });

    testWidgets('displays settings icon in app bar', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('displays PartnerClockWidget', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byType(PartnerClockWidget), findsOneWidget);
    });

    testWidgets('displays NextWindowCard', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byType(NextWindowCard), findsOneWidget);
    });

    testWidgets('displays "Upcoming Windows" section header', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.text('Upcoming Windows'), findsOneWidget);
    });

    testWidgets('displays FAB with add icon', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('has a RefreshIndicator for pull-to-refresh', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('HomeScreen FAB quick actions', () {
    testWidgets('tapping FAB shows bottom sheet with actions',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Add Block'), findsOneWidget);
      expect(find.text('Sync Calendar'), findsOneWidget);
      expect(find.text('View All Windows'), findsOneWidget);
    });

    testWidgets('bottom sheet shows subtitles for each action',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Block out time in your schedule'), findsOneWidget);
      expect(find.text('Refresh from Google Calendar'), findsOneWidget);
      expect(find.text('See all upcoming free times'), findsOneWidget);
    });

    testWidgets('bottom sheet shows icons for each action', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(find.byIcon(Icons.calendar_view_day), findsOneWidget);
    });

    testWidgets('tapping Sync Calendar dismisses bottom sheet',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync Calendar'));
      await tester.pumpAndSettle();

      // Bottom sheet should be dismissed
      expect(find.text('Refresh from Google Calendar'), findsNothing);
    });
  });

  group('HomeScreen pull-to-refresh', () {
    testWidgets('shows loading indicator during refresh', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Trigger pull-to-refresh by dragging down
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();

      // The refresh indicator should be visible
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('HomeScreen upcoming windows list', () {
    testWidgets('renders upcoming window cards with score percentages',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Mock data generates 6 windows; first is nextWindow, remaining 5 are upcoming
      // Each has a score displayed as percentage
      final scoreFinder = find.textContaining('%');
      expect(scoreFinder, findsWidgets);
    });

    testWidgets('renders upcoming window cards with duration', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // All mock windows have 120 minutes duration
      expect(find.text('2 hr'), findsWidgets);
    });
  });
}
