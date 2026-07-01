import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/core/models/overlap_result.dart';
import 'package:couple_sync/core/utils/format_utils.dart';
import 'package:couple_sync/features/calendar/week_view_widget.dart';
import 'package:couple_sync/features/calendar/block_event_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

/// Fixed Monday for deterministic tests: 2024-06-10 (a Monday).
final _testMonday = DateTime(2024, 6, 10);

TimeBlock _makeBlock({
  String userId = 'user_1',
  String title = 'Work',
  TimeBlockCategory category = TimeBlockCategory.work,
  required int startUtc,
  required int endUtc,
}) {
  return TimeBlock(
    userId: userId,
    title: title,
    type: TimeBlockType.busy,
    category: category,
    startUtc: startUtc,
    endUtc: endUtc,
    timezone: 'UTC',
    source: TimeBlockSource.manual,
    visibility: TimeBlockVisibility.bothPartners,
    createdAt: DateTime(2024, 1, 1),
  );
}

OverlapWindow _makeOverlap({
  required int startUtc,
  required int endUtc,
  int durationMinutes = 60,
  double score = 8.0,
  bool reasonableBoth = true,
}) {
  return OverlapWindow(
    startUtc: startUtc,
    endUtc: endUtc,
    durationMinutes: durationMinutes,
    score: score,
    reasonableBoth: reasonableBoth,
  );
}

Widget _buildSubject({
  DateTime? initialWeek,
  List<TimeBlock> userBlocks = const [],
  List<TimeBlock> partnerBlocks = const [],
  List<OverlapWindow> overlapWindows = const [],
  String currentUserId = 'user_1',
  void Function(DateTime)? onWeekChanged,
  VoidCallback? onAddBlock,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: WeekViewWidget(
        initialWeek: initialWeek,
        userBlocks: userBlocks,
        partnerBlocks: partnerBlocks,
        overlapWindows: overlapWindows,
        currentUserId: currentUserId,
        onWeekChanged: onWeekChanged,
        onAddBlock: onAddBlock,
      ),
    ),
  );
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  group('WeekViewWidget', () {
    testWidgets('renders without errors with no data', (tester) async {
      await tester.pumpWidget(_buildSubject(initialWeek: _testMonday));

      expect(find.byType(WeekViewWidget), findsOneWidget);
    });

    testWidgets('shows day name headers Mon-Sun', (tester) async {
      await tester.pumpWidget(_buildSubject(initialWeek: _testMonday));

      for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(find.text(day), findsOneWidget);
      }
    });

    testWidgets('shows month and year in header', (tester) async {
      await tester.pumpWidget(_buildSubject(initialWeek: _testMonday));

      expect(find.text('June 2024'), findsOneWidget);
    });

    testWidgets('shows navigation chevron buttons', (tester) async {
      await tester.pumpWidget(_buildSubject(initialWeek: _testMonday));

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('shows date numbers for the week', (tester) async {
      await tester.pumpWidget(_buildSubject(initialWeek: _testMonday));

      // Week of June 10: 10, 11, 12, 13, 14, 15, 16
      for (final day in [10, 11, 12, 13, 14, 15, 16]) {
        expect(find.text('$day'), findsOneWidget);
      }
    });

    testWidgets('renders user blocks as BlockEventWidget', (tester) async {
      final blockStart =
          _testMonday.add(const Duration(hours: 9)).millisecondsSinceEpoch;
      final blockEnd =
          _testMonday.add(const Duration(hours: 10)).millisecondsSinceEpoch;

      await tester.pumpWidget(_buildSubject(
        initialWeek: _testMonday,
        userBlocks: [_makeBlock(startUtc: blockStart, endUtc: blockEnd)],
      ));

      expect(find.byType(BlockEventWidget), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('renders partner blocks', (tester) async {
      final blockStart =
          _testMonday.add(const Duration(hours: 14)).millisecondsSinceEpoch;
      final blockEnd =
          _testMonday.add(const Duration(hours: 16)).millisecondsSinceEpoch;

      await tester.pumpWidget(_buildSubject(
        initialWeek: _testMonday,
        partnerBlocks: [
          _makeBlock(
            userId: 'partner_1',
            title: 'Partner Meeting',
            startUtc: blockStart,
            endUtc: blockEnd,
          ),
        ],
      ));

      expect(find.text('Partner Meeting'), findsOneWidget);
    });

    testWidgets('renders overlap windows with heart icon', (tester) async {
      final overlapStart =
          _testMonday.add(const Duration(hours: 17)).millisecondsSinceEpoch;
      final overlapEnd =
          _testMonday.add(const Duration(hours: 18)).millisecondsSinceEpoch;

      await tester.pumpWidget(_buildSubject(
        initialWeek: _testMonday,
        overlapWindows: [
          _makeOverlap(startUtc: overlapStart, endUtc: overlapEnd),
        ],
      ));

      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('renders in dark theme without errors', (tester) async {
      await tester.pumpWidget(_buildSubject(
        initialWeek: _testMonday,
        brightness: Brightness.dark,
      ));

      expect(find.byType(WeekViewWidget), findsOneWidget);
    });

    testWidgets('tapping overlap shows detail dialog', (tester) async {
      final overlapStart =
          _testMonday.add(const Duration(hours: 10)).millisecondsSinceEpoch;
      final overlapEnd =
          _testMonday.add(const Duration(hours: 11)).millisecondsSinceEpoch;

      await tester.pumpWidget(_buildSubject(
        initialWeek: _testMonday,
        overlapWindows: [
          _makeOverlap(
            startUtc: overlapStart,
            endUtc: overlapEnd,
            durationMinutes: 60,
            score: 9.0,
          ),
        ],
      ));

      // Scroll to make the overlap visible before tapping
      await tester.ensureVisible(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(find.text('Free Time Together'), findsOneWidget);
      expect(find.text('1 hr'), findsOneWidget);
      expect(find.text('9.0'), findsOneWidget);
    });

    testWidgets('tapping block shows block detail dialog', (tester) async {
      final blockStart =
          _testMonday.add(const Duration(hours: 9)).millisecondsSinceEpoch;
      final blockEnd =
          _testMonday.add(const Duration(hours: 10)).millisecondsSinceEpoch;

      await tester.pumpWidget(_buildSubject(
        initialWeek: _testMonday,
        userBlocks: [_makeBlock(startUtc: blockStart, endUtc: blockEnd)],
      ));

      await tester.ensureVisible(find.byType(BlockEventWidget));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BlockEventWidget));
      await tester.pumpAndSettle();

      expect(find.byType(BlockDetailDialog), findsOneWidget);
      expect(find.text('Work'), findsWidgets);
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('time labels are locale-aware', (tester) async {
      await tester.pumpWidget(_buildSubject(initialWeek: _testMonday));

      // Locale-aware (DateFormat.jm) — 12h with am/pm in en_US.
      // Compare against the same helper the widget uses, so the test
      // is robust to intl's choice of separator (NNBSP, not ASCII space).
      final midnight = formatTimeHm(DateTime(2024, 1, 1, 0));
      final noon = formatTimeHm(DateTime(2024, 1, 1, 12));
      expect(find.text(midnight), findsOneWidget);
      expect(find.text(noon), findsOneWidget);
    });

    testWidgets('does not render blocks outside of visible week',
        (tester) async {
      // Block on a different week entirely
      final otherWeek = _testMonday.subtract(const Duration(days: 14));
      final blockStart =
          otherWeek.add(const Duration(hours: 9)).millisecondsSinceEpoch;
      final blockEnd =
          otherWeek.add(const Duration(hours: 10)).millisecondsSinceEpoch;

      await tester.pumpWidget(_buildSubject(
        initialWeek: _testMonday,
        userBlocks: [
          _makeBlock(title: 'Old Block', startUtc: blockStart, endUtc: blockEnd)
        ],
      ));

      expect(find.text('Old Block'), findsNothing);
    });

    testWidgets(
        'cross-midnight block renders without throwing and has positive height',
        (tester) async {
      // Block starts 23:00 UTC Monday and ends 01:00 UTC Tuesday.
      // startUtc → 23:00, endUtc → 01:00 next day.
      // In the widget: startMinutes=1380, endMinutes=60.
      // Since endMinutes < startMinutes, effectiveEnd clips to 1440,
      // giving duration=60 min → height=60px (clamped to ≥20px).
      final startUtc =
          DateTime.utc(2024, 6, 10, 23, 0).millisecondsSinceEpoch;
      final endUtc =
          DateTime.utc(2024, 6, 11, 1, 0).millisecondsSinceEpoch;

      await tester.pumpWidget(_buildSubject(
        initialWeek: _testMonday,
        userBlocks: [
          _makeBlock(
            title: 'Late Night',
            startUtc: startUtc,
            endUtc: endUtc,
          ),
        ],
      ));

      // Widget must render without any exception
      expect(find.byType(WeekViewWidget), findsOneWidget);

      // Cross-midnight block appears in both the start day and end day columns
      expect(find.byType(BlockEventWidget), findsAtLeastNWidgets(1));

      // Measure the rendered height of the first block widget and verify it is positive
      final renderBox = tester.renderObject<RenderBox>(
        find.byType(BlockEventWidget).first,
      );
      expect(renderBox.size.height, greaterThan(0.0));
    });

    testWidgets(
        'cross-midnight overlap window renders without throwing and has positive height',
        (tester) async {
      // Overlap starts 23:00 UTC Monday and ends 01:00 UTC Tuesday.
      final startUtc =
          DateTime.utc(2024, 6, 10, 23, 0).millisecondsSinceEpoch;
      final endUtc =
          DateTime.utc(2024, 6, 11, 1, 0).millisecondsSinceEpoch;

      await tester.pumpWidget(_buildSubject(
        initialWeek: _testMonday,
        overlapWindows: [
          _makeOverlap(
            startUtc: startUtc,
            endUtc: endUtc,
            durationMinutes: 120,
          ),
        ],
      ));

      // Widget must render without any exception
      expect(find.byType(WeekViewWidget), findsOneWidget);

      // Cross-midnight overlap appears in both the start day and end day columns
      expect(find.byIcon(Icons.favorite), findsAtLeastNWidgets(1));

      // Verify the overlap container has positive height
      final overlapFinder = find.ancestor(
        of: find.byIcon(Icons.favorite),
        matching: find.byType(Container),
      );
      final renderBox = tester.renderObject<RenderBox>(overlapFinder.first);
      expect(renderBox.size.height, greaterThan(0.0));
    });
  });
}
