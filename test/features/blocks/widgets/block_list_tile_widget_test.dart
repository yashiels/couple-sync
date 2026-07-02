import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/core/utils/format_utils.dart';
import 'package:couple_sync/features/blocks/widgets/block_list_tile_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to create a TimeBlock for testing.
TimeBlock _makeBlock({
  String title = 'Work Meeting',
  TimeBlockType type = TimeBlockType.busy,
  TimeBlockCategory category = TimeBlockCategory.work,
  int? startUtc,
  int? endUtc,
  TimeBlockSource source = TimeBlockSource.manual,
  TimeBlockVisibility visibility = TimeBlockVisibility.bothPartners,
  String? recurrenceRule,
}) {
  // 2024-06-15 09:00 local (display tests use local time)
  final defaultStart = DateTime(2024, 6, 15, 9, 0).millisecondsSinceEpoch;
  // 2024-06-15 10:00 local
  final defaultEnd = DateTime(2024, 6, 15, 10, 0).millisecondsSinceEpoch;

  return TimeBlock(
    userId: 'user-1',
    title: title,
    type: type,
    category: category,
    startUtc: startUtc ?? defaultStart,
    endUtc: endUtc ?? defaultEnd,
    timezone: 'America/New_York',
    recurrenceRule: recurrenceRule,
    source: source,
    visibility: visibility,
    createdAt: DateTime(2024, 1, 1),
  );
}

Widget _buildSubject({
  required TimeBlock block,
  bool isCurrentUser = true,
  VoidCallback? onTap,
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    theme: brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: BlockListTileWidget(
        block: block,
        isCurrentUser: isCurrentUser,
        onTap: onTap,
      ),
    ),
  );
}

void main() {
  group('BlockListTileWidget', () {
    testWidgets('displays block title', (tester) async {
      await tester.pumpWidget(_buildSubject(block: _makeBlock()));

      expect(find.text('Work Meeting'), findsOneWidget);
    });

    testWidgets('displays "You" when isCurrentUser is true', (tester) async {
      await tester.pumpWidget(
        _buildSubject(block: _makeBlock(), isCurrentUser: true),
      );

      expect(find.text('You'), findsOneWidget);
      expect(find.text('Partner'), findsNothing);
    });

    testWidgets('displays "Partner" when isCurrentUser is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSubject(block: _makeBlock(), isCurrentUser: false),
      );

      expect(find.text('Partner'), findsOneWidget);
      expect(find.text('You'), findsNothing);
    });

    testWidgets('displays Manual badge for manual source', (tester) async {
      await tester.pumpWidget(
        _buildSubject(block: _makeBlock(source: TimeBlockSource.manual)),
      );

      expect(find.text('Manual'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('displays Google badge for google source', (tester) async {
      await tester.pumpWidget(
        _buildSubject(block: _makeBlock(source: TimeBlockSource.google)),
      );

      expect(find.text('Google'), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsOneWidget);
    });

    testWidgets('shows chevron_right icon', (tester) async {
      await tester.pumpWidget(_buildSubject(block: _makeBlock()));

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildSubject(block: _makeBlock(), onTap: () => tapped = true),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('formats same-day time range correctly', (tester) async {
      // 2024-06-15 09:00 - 10:30 local (display tests use local time)
      final start = DateTime(2024, 6, 15, 9, 0).millisecondsSinceEpoch;
      final end = DateTime(2024, 6, 15, 10, 30).millisecondsSinceEpoch;

      await tester.pumpWidget(
        _buildSubject(
          block: _makeBlock(startUtc: start, endUtc: end),
        ),
      );

      // C3: same day uses locale-aware 12h time (formatTimeHm = DateFormat.jm()).
      // Note: jm() emits a NARROW NO-BREAK SPACE (U+202F) before the am/pm
      // marker, so compare against the formatter output rather than a literal.
      final startDt = DateTime(2024, 6, 15, 9, 0);
      final endDt = DateTime(2024, 6, 15, 10, 30);
      expect(find.textContaining('15 Jun'), findsOneWidget);
      expect(find.textContaining(formatTimeHm(startDt)), findsOneWidget);
      expect(find.textContaining(formatTimeHm(endDt)), findsOneWidget);
    });

    testWidgets('formats cross-day time range correctly', (tester) async {
      // 2024-06-15 23:00 - 2024-06-16 01:00 local (different days)
      final start = DateTime(2024, 6, 15, 23, 0).millisecondsSinceEpoch;
      final end = DateTime(2024, 6, 16, 1, 0).millisecondsSinceEpoch;

      await tester.pumpWidget(
        _buildSubject(
          block: _makeBlock(startUtc: start, endUtc: end),
        ),
      );

      // Cross-day: "15 Jun 23:00 - 16 Jun 01:00"
      expect(find.textContaining('15 Jun'), findsOneWidget);
      expect(find.textContaining('16 Jun'), findsOneWidget);
    });

    testWidgets('renders in dark theme without errors', (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          block: _makeBlock(category: TimeBlockCategory.sleep),
          brightness: Brightness.dark,
        ),
      );

      expect(find.text('Work Meeting'), findsOneWidget);
    });

    testWidgets('renders each category without errors', (tester) async {
      for (final category in TimeBlockCategory.values) {
        await tester.pumpWidget(
          _buildSubject(
            block: _makeBlock(category: category, title: category.name),
          ),
        );

        expect(find.text(category.name), findsOneWidget);
      }
    });
  });
}
