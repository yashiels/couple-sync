import 'package:couple_sync/features/blocks/screens/blocks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlocksScreen', () {
    Widget buildSubject() {
      return const MaterialApp(home: BlocksScreen());
    }

    testWidgets('renders scaffold with app bar title', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.text('Time Blocks'), findsOneWidget);
    });

    testWidgets('renders view_list icon', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.byIcon(Icons.view_list), findsOneWidget);
    });

    testWidgets('renders Block Management heading', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.text('Block Management'), findsOneWidget);
    });

    testWidgets('renders coming soon description', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(
        find.text('View and manage your time blocks\n(Coming soon)'),
        findsOneWidget,
      );
    });

    testWidgets('content is centered', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.byType(Center), findsWidgets);
    });
  });
}
