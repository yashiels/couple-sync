import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a widget with MaterialApp and ProviderScope for testing.
Widget createTestWidget(Widget child, {List<Override>? overrides}) {
  return ProviderScope(
    overrides: overrides ?? [],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

/// Pumps a widget with MaterialApp wrapper and settles animations.
Future<void> pumpTestWidget(
  WidgetTester tester,
  Widget child, {
  List<Override>? overrides,
}) async {
  await tester.pumpWidget(createTestWidget(child, overrides: overrides));
  await tester.pumpAndSettle();
}
