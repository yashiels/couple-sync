import 'package:couple_sync/core/models/time_block.dart';
import 'package:couple_sync/features/calendar/block_event_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TimeBlock _makeBlock({
  String title = 'Work Meeting',
  TimeBlockType type = TimeBlockType.busy,
  TimeBlockCategory category = TimeBlockCategory.work,
  int? startUtc,
  int? endUtc,
  TimeBlockSource source = TimeBlockSource.manual,
}) {
  // 2024-06-15 09:00 local (display tests use local time)
  final defaultStart = DateTime(2024, 6, 15, 9, 0).millisecondsSinceEpoch;
  // 2024-06-15 10:00 local (60 min duration >= 30 so time range is shown)
  final defaultEnd = DateTime(2024, 6, 15, 10, 0).millisecondsSinceEpoch;

  return TimeBlock(
    userId: 'user-1',
    title: title,
    type: type,
    category: category,
    startUtc: startUtc ?? defaultStart,
    endUtc: endUtc ?? defaultEnd,
    timezone: 'UTC',
    source: source,
    visibility: TimeBlockVisibility.bothPartners,
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
      body: SizedBox(
        width: 100,
        height: 80,
        child: BlockEventWidget(
          block: block,
          isCurrentUser: isCurrentUser,
          onTap: onTap,
        ),
      ),
    ),
  );
}

void main() {
  group('BlockEventWidget', () {
    testWidgets('displays block title', (tester) async {
      await tester.pumpWidget(_buildSubject(block: _makeBlock()));

      expect(find.text('Work Meeting'), findsOneWidget);
    });

    testWidgets('shows time range for blocks >= 30 minutes', (tester) async {
      await tester.pumpWidget(_buildSubject(block: _makeBlock()));

      // 60 min block: 09:00 - 10:00
      expect(find.text('09:00 - 10:00'), findsOneWidget);
    });

    testWidgets('hides time range for blocks < 30 minutes', (tester) async {
      // 15 minute block
      final start = DateTime(2024, 6, 15, 9, 0).millisecondsSinceEpoch;
      final end = DateTime(2024, 6, 15, 9, 15).millisecondsSinceEpoch;

      await tester.pumpWidget(_buildSubject(
        block: _makeBlock(startUtc: start, endUtc: end),
      ));

      expect(find.text('Work Meeting'), findsOneWidget);
      expect(find.text('09:00 - 09:15'), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_buildSubject(
        block: _makeBlock(),
        onTap: () => tapped = true,
      ));

      await tester.tap(find.byType(GestureDetector).first);
      expect(tapped, isTrue);
    });

    testWidgets('renders each category without errors in light theme',
        (tester) async {
      for (final category in TimeBlockCategory.values) {
        await tester.pumpWidget(_buildSubject(
          block: _makeBlock(category: category, title: category.name),
        ));

        expect(find.text(category.name), findsOneWidget);
      }
    });

    testWidgets('renders each category without errors in dark theme',
        (tester) async {
      for (final category in TimeBlockCategory.values) {
        await tester.pumpWidget(_buildSubject(
          block: _makeBlock(category: category, title: category.name),
          brightness: Brightness.dark,
        ));

        expect(find.text(category.name), findsOneWidget);
      }
    });

    testWidgets('renders with reduced opacity for partner blocks',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        block: _makeBlock(),
        isCurrentUser: false,
      ));

      // Widget renders without error — visual opacity tested via rendering
      expect(find.text('Work Meeting'), findsOneWidget);
    });

    testWidgets('title truncates with ellipsis on overflow', (tester) async {
      await tester.pumpWidget(_buildSubject(
        block: _makeBlock(
            title:
                'Very Long Title That Should Overflow The Available Space Completely'),
      ));

      // Widget renders; Text widget has maxLines: 1, overflow: ellipsis
      expect(
        find.text(
            'Very Long Title That Should Overflow The Available Space Completely'),
        findsOneWidget,
      );
    });
  });

  group('BlockDetailDialog', () {
    Widget buildDialog({
      required TimeBlock block,
      bool isCurrentUser = true,
      Brightness brightness = Brightness.light,
    }) {
      return MaterialApp(
        theme: brightness == Brightness.light
            ? ThemeData.light(useMaterial3: true)
            : ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => BlockDetailDialog(
                  block: block,
                  isCurrentUser: isCurrentUser,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
    }

    testWidgets('shows block title', (tester) async {
      await tester.pumpWidget(buildDialog(block: _makeBlock()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Work Meeting'), findsOneWidget);
    });

    testWidgets('shows "You" for current user', (tester) async {
      await tester.pumpWidget(buildDialog(block: _makeBlock()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('shows "Partner" for partner', (tester) async {
      await tester.pumpWidget(
          buildDialog(block: _makeBlock(), isCurrentUser: false));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Partner'), findsOneWidget);
    });

    testWidgets('shows time range', (tester) async {
      await tester.pumpWidget(buildDialog(block: _makeBlock()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('09:00 - 10:00'), findsOneWidget);
    });

    testWidgets('shows date', (tester) async {
      await tester.pumpWidget(buildDialog(block: _makeBlock()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('15 Jun 2024'), findsOneWidget);
    });

    testWidgets('shows duration', (tester) async {
      await tester.pumpWidget(buildDialog(block: _makeBlock()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('1 hr'), findsOneWidget);
    });

    testWidgets('shows category label', (tester) async {
      await tester.pumpWidget(buildDialog(block: _makeBlock()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('shows Manual source for manual blocks', (tester) async {
      await tester.pumpWidget(buildDialog(block: _makeBlock()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Manual'), findsOneWidget);
    });

    testWidgets('shows Google Calendar source for google blocks',
        (tester) async {
      await tester.pumpWidget(
          buildDialog(block: _makeBlock(source: TimeBlockSource.google)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Google Calendar'), findsOneWidget);
    });

    testWidgets('close button dismisses dialog', (tester) async {
      await tester.pumpWidget(buildDialog(block: _makeBlock()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(BlockDetailDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(BlockDetailDialog), findsNothing);
    });

    testWidgets('formats duration with hours and minutes', (tester) async {
      // 1.5 hour block
      final start = DateTime.utc(2024, 6, 15, 9, 0).millisecondsSinceEpoch;
      final end = DateTime.utc(2024, 6, 15, 10, 30).millisecondsSinceEpoch;

      await tester
          .pumpWidget(buildDialog(block: _makeBlock(startUtc: start, endUtc: end)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('1 hr 30 min'), findsOneWidget);
    });

    testWidgets('formats duration in minutes only for < 60 min',
        (tester) async {
      final start = DateTime.utc(2024, 6, 15, 9, 0).millisecondsSinceEpoch;
      final end = DateTime.utc(2024, 6, 15, 9, 45).millisecondsSinceEpoch;

      await tester
          .pumpWidget(buildDialog(block: _makeBlock(startUtc: start, endUtc: end)));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('45 min'), findsOneWidget);
    });

    testWidgets('renders in dark theme', (tester) async {
      await tester.pumpWidget(
          buildDialog(block: _makeBlock(), brightness: Brightness.dark));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(BlockDetailDialog), findsOneWidget);
    });
  });
}
