import 'package:couple_sync/features/overlap/screens/overlap_screen.dart';
import 'package:couple_sync/features/overlap/widgets/window_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

Widget _buildSubject() {
  return const ProviderScope(
    child: MaterialApp(
      home: OverlapScreen(),
    ),
  );
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('OverlapScreen rendering', () {
    testWidgets('displays app bar with "Mutual Free Time" title',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.text('Mutual Free Time'), findsOneWidget);
    });

    testWidgets('displays filter icon button in app bar', (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
    });

    testWidgets('renders WindowCardWidget items in list', (tester) async {
      await tester.pumpWidget(_buildSubject());
      // Mock data generates 15 windows, limited to 10
      expect(find.byType(WindowCardWidget), findsAtLeast(1));
    });

    testWidgets('limits displayed windows to at most 10', (tester) async {
      await tester.pumpWidget(_buildSubject());
      // The screen caps at 10 windows
      final cards = tester.widgetList(find.byType(WindowCardWidget));
      expect(cards.length, lessThanOrEqualTo(10));
    });

    testWidgets('has a ListView.builder for scrollable content',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('OverlapScreen filter dialog', () {
    testWidgets('tapping filter icon opens filter dialog', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      expect(find.text('Filter & Sort'), findsOneWidget);
    });

    testWidgets('filter dialog shows duration choices', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      expect(find.text('Minimum Duration'), findsOneWidget);
      expect(find.text('Any'), findsAtLeast(1));
      expect(find.text('30m'), findsOneWidget);
      expect(find.text('1h'), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);
    });

    testWidgets('filter dialog shows score choices', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      expect(find.text('Minimum Score'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
    });

    testWidgets('filter dialog shows sort choices', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      expect(find.text('Sort By'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Score'), findsOneWidget);
    });

    testWidgets('filter dialog has Clear All and Apply buttons',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      expect(find.text('Clear All'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('Apply button closes the dialog', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Filter & Sort'), findsNothing);
    });

    testWidgets('selecting a duration filter shows filter summary bar',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      // Select 1h duration filter
      await tester.tap(find.text('1h'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Filter chip should appear with "Min 1 hr"
      expect(find.text('Min 1 hr'), findsOneWidget);
    });

    testWidgets('selecting a score filter shows filter summary bar',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      // Select 60% score filter
      await tester.tap(find.text('60%'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Min 60% score'), findsOneWidget);
    });
  });

  group('OverlapScreen window details', () {
    testWidgets('tapping a window card opens details dialog', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Tap the first WindowCardWidget
      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      expect(find.text('Window Details'), findsOneWidget);
    });

    testWidgets('details dialog shows score breakdown', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      expect(find.text('Score Breakdown'), findsOneWidget);
      expect(find.text('Overall Score'), findsOneWidget);
      expect(find.text('Duration Score'), findsOneWidget);
      expect(find.text('Timing Score'), findsOneWidget);
    });

    testWidgets('details dialog shows time info', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      expect(find.text('Your Time'), findsOneWidget);
      expect(find.text("Partner's Time"), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
    });

    testWidgets('details dialog has Close button', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Close button dismisses details dialog', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Window Details'), findsNothing);
    });

    testWidgets('details dialog shows reasonable hours indicator',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      // First mock window has reasonableBoth = true (index 0, i % 2 == 0)
      expect(
        find.text('Reasonable hours for both'),
        findsOneWidget,
      );
    });
  });
}
