import 'package:couple_sync/core/models/overlap_result.dart';
import 'package:couple_sync/features/home/next_window_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

/// Creates a future window starting [daysFromNow] days from now.
OverlapWindow _makeFutureWindow({
  int daysFromNow = 2,
  int durationMinutes = 120,
  double score = 0.85,
}) {
  final now = DateTime.now();
  final start = now.add(Duration(days: daysFromNow, hours: 18));
  final end = start.add(Duration(minutes: durationMinutes));

  return OverlapWindow(
    startUtc: start.toUtc().millisecondsSinceEpoch,
    endUtc: end.toUtc().millisecondsSinceEpoch,
    durationMinutes: durationMinutes,
    score: score,
    reasonableBoth: true,
  );
}

/// Creates a window that has already started (in the past).
OverlapWindow _makePastWindow() {
  final now = DateTime.now();
  final start = now.subtract(const Duration(hours: 1));
  final end = now.add(const Duration(hours: 1));

  return OverlapWindow(
    startUtc: start.toUtc().millisecondsSinceEpoch,
    endUtc: end.toUtc().millisecondsSinceEpoch,
    durationMinutes: 120,
    score: 0.9,
    reasonableBoth: true,
  );
}

Widget _buildSubject({
  OverlapWindow? window,
  String userTimezone = 'Africa/Johannesburg',
  String partnerTimezone = 'Europe/London',
}) {
  return MaterialApp(
    home: Scaffold(
      body: NextWindowCard(
        window: window,
        userTimezone: userTimezone,
        partnerTimezone: partnerTimezone,
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('NextWindowCard empty state', () {
    testWidgets('displays empty state when window is null', (tester) async {
      await tester.pumpWidget(_buildSubject(window: null));

      expect(find.text('No upcoming free windows'), findsOneWidget);
      expect(
        find.text('Add some time blocks to see when you can meet'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.event_busy), findsOneWidget);
    });

    testWidgets('does not display "Next Free Window" header when null',
        (tester) async {
      await tester.pumpWidget(_buildSubject(window: null));
      expect(find.text('Next Free Window'), findsNothing);
    });
  });

  group('NextWindowCard with window', () {
    testWidgets('displays "Next Free Window" header', (tester) async {
      await tester.pumpWidget(_buildSubject(window: _makeFutureWindow()));
      expect(find.text('Next Free Window'), findsOneWidget);
    });

    testWidgets('displays duration chip', (tester) async {
      await tester.pumpWidget(
        _buildSubject(window: _makeFutureWindow(durationMinutes: 120)),
      );
      expect(find.text('2 hr'), findsOneWidget);
    });

    testWidgets('displays score chip', (tester) async {
      await tester.pumpWidget(
        _buildSubject(window: _makeFutureWindow(score: 0.85)),
      );
      expect(find.text('Score: 85%'), findsOneWidget);
    });

    testWidgets('displays "Tap to see all windows" hint', (tester) async {
      await tester.pumpWidget(_buildSubject(window: _makeFutureWindow()));
      expect(find.text('Tap to see all windows'), findsOneWidget);
    });

    testWidgets('displays person and favorite icons for timezones',
        (tester) async {
      await tester.pumpWidget(_buildSubject(window: _makeFutureWindow()));
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('displays schedule and star icons for info chips',
        (tester) async {
      await tester.pumpWidget(_buildSubject(window: _makeFutureWindow()));
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('is wrapped in a Card with InkWell', (tester) async {
      await tester.pumpWidget(_buildSubject(window: _makeFutureWindow()));
      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
    });
  });

  group('NextWindowCard countdown', () {
    testWidgets('shows "Now" for past-start windows', (tester) async {
      await tester.pumpWidget(_buildSubject(window: _makePastWindow()));
      expect(find.text('Now'), findsOneWidget);
    });

    testWidgets('shows day-based countdown for far future windows',
        (tester) async {
      await tester.pumpWidget(
        _buildSubject(window: _makeFutureWindow(daysFromNow: 3)),
      );
      // Should show something like "3 days Xh"
      final countdownFinder = find.textContaining('day');
      expect(countdownFinder, findsOneWidget);
    });
  });

  group('NextWindowCard duration formatting', () {
    testWidgets('formats minutes-only duration', (tester) async {
      await tester.pumpWidget(
        _buildSubject(window: _makeFutureWindow(durationMinutes: 45)),
      );
      expect(find.text('45 min'), findsOneWidget);
    });

    testWidgets('formats hours-only duration', (tester) async {
      await tester.pumpWidget(
        _buildSubject(window: _makeFutureWindow(durationMinutes: 180)),
      );
      expect(find.text('3 hr'), findsOneWidget);
    });

    testWidgets('formats hours and minutes duration', (tester) async {
      await tester.pumpWidget(
        _buildSubject(window: _makeFutureWindow(durationMinutes: 90)),
      );
      expect(find.text('1 hr 30 min'), findsOneWidget);
    });
  });

  group('NextWindowCard timer', () {
    testWidgets('cancels timer on dispose without errors', (tester) async {
      await tester.pumpWidget(_buildSubject(window: _makeFutureWindow()));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // No errors means timer was properly cancelled
    });
  });
}
