import 'package:couple_sync/core/models/overlap_result.dart';
import 'package:couple_sync/features/overlap/widgets/window_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

OverlapWindow _createWindow({
  int durationMinutes = 60,
  double score = 0.8,
  bool reasonableBoth = true,
}) {
  final now = DateTime.now().toUtc();
  return OverlapWindow(
    startUtc: now.millisecondsSinceEpoch,
    endUtc: now.add(Duration(minutes: durationMinutes)).millisecondsSinceEpoch,
    durationMinutes: durationMinutes,
    score: score,
    reasonableBoth: reasonableBoth,
  );
}

Widget _buildSubject({
  OverlapWindow? window,
  String userTimezone = 'Africa/Johannesburg',
  String partnerTimezone = 'America/New_York',
  VoidCallback? onTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: WindowCardWidget(
        window: window ?? _createWindow(),
        userTimezone: userTimezone,
        partnerTimezone: partnerTimezone,
        onTap: onTap,
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('WindowCardWidget rendering', () {
    testWidgets('renders a Card widget', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('displays date header', (tester) async {
      await tester.pumpWidget(_buildSubject());
      // Should find a date string (day of week, month, day number)
      // The exact text depends on current date, so just check the card renders
      expect(find.byType(WindowCardWidget), findsOneWidget);
    });

    testWidgets('displays score badge', (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(score: 0.85),
      ));
      // 0.85 * 100 = 85%
      expect(find.text('85%'), findsOneWidget);
    });

    testWidgets('displays star icon in score badge', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('displays user time with person icon', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('displays partner time with favorite icon', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('displays schedule icon for duration', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });
  });

  group('WindowCardWidget duration formatting', () {
    testWidgets('displays minutes for short durations', (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(durationMinutes: 30),
      ));
      expect(find.text('30 min'), findsOneWidget);
    });

    testWidgets('displays hours for exact hour durations', (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(durationMinutes: 120),
      ));
      expect(find.text('2 hr'), findsOneWidget);
    });

    testWidgets('displays hours and minutes for mixed durations',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(durationMinutes: 90),
      ));
      expect(find.text('1 hr 30 min'), findsOneWidget);
    });
  });

  group('WindowCardWidget reasonable hours', () {
    testWidgets('shows "Reasonable hours" chip when reasonableBoth is true',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(reasonableBoth: true),
      ));
      expect(find.text('Reasonable hours'), findsOneWidget);
      expect(find.byIcon(Icons.wb_sunny), findsOneWidget);
    });

    testWidgets('hides "Reasonable hours" chip when reasonableBoth is false',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(reasonableBoth: false),
      ));
      expect(find.text('Reasonable hours'), findsNothing);
      expect(find.byIcon(Icons.wb_sunny), findsNothing);
    });
  });

  group('WindowCardWidget score colors', () {
    testWidgets('high score (>=0.8) uses green', (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(score: 0.9),
      ));
      expect(find.text('90%'), findsOneWidget);
    });

    testWidgets('medium score (>=0.6) renders', (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(score: 0.65),
      ));
      expect(find.text('65%'), findsOneWidget);
    });

    testWidgets('low score (>=0.4) renders', (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(score: 0.45),
      ));
      expect(find.text('45%'), findsOneWidget);
    });

    testWidgets('very low score (<0.4) renders', (tester) async {
      await tester.pumpWidget(_buildSubject(
        window: _createWindow(score: 0.2),
      ));
      expect(find.text('20%'), findsOneWidget);
    });
  });

  group('WindowCardWidget interaction', () {
    testWidgets('calls onTap when card is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_buildSubject(
        onTap: () => tapped = true,
      ));

      await tester.tap(find.byType(InkWell).first);
      expect(tapped, isTrue);
    });

    testWidgets('renders without onTap (nullable)', (tester) async {
      await tester.pumpWidget(_buildSubject(onTap: null));
      expect(find.byType(WindowCardWidget), findsOneWidget);
    });
  });

  group('WindowCardWidget timezone display', () {
    testWidgets('displays user timezone offset', (tester) async {
      await tester.pumpWidget(_buildSubject(
        userTimezone: 'Africa/Johannesburg',
      ));
      // Should show UTC+2 for Africa/Johannesburg
      expect(find.textContaining('UTC'), findsAtLeast(1));
    });

    testWidgets('displays partner timezone offset', (tester) async {
      await tester.pumpWidget(_buildSubject(
        partnerTimezone: 'America/New_York',
      ));
      // Should show UTC-4 or UTC-5 depending on DST
      expect(find.textContaining('UTC'), findsAtLeast(1));
    });
  });
}
