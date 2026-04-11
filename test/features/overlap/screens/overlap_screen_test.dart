import 'package:couple_sync/core/models/overlap_result.dart';
import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/overlap/screens/overlap_screen.dart';
import 'package:couple_sync/features/overlap/widgets/window_card_widget.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:couple_sync/services/providers/couple_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

/// Helper to create a UserModel for tests.
UserModel _makeUser({
  required String timezone,
  String? coupleId,
  String email = 'test@test.com',
  String displayName = 'Test User',
}) {
  return UserModel(
    email: email,
    displayName: displayName,
    timezone: timezone,
    coupleId: coupleId,
    fcmTokens: const [],
    createdAt: DateTime(2024, 1, 1),
  );
}

/// Generate mock overlap windows for testing.
List<OverlapWindow> _generateMockWindows() {
  final now = DateTime.now();
  final windows = <OverlapWindow>[];

  for (int i = 0; i < 15; i++) {
    final startHour = 9 + (i * 24);
    final start = now.add(Duration(hours: startHour));
    final duration = [30, 60, 90, 120, 180][i % 5];

    windows.add(OverlapWindow(
      startUtc: start.toUtc().millisecondsSinceEpoch,
      endUtc:
          start.add(Duration(minutes: duration)).toUtc().millisecondsSinceEpoch,
      durationMinutes: duration,
      score: [0.3, 0.5, 0.7, 0.8, 0.9, 1.0][i % 6],
      reasonableBoth: i % 2 == 0,
    ));
  }

  return windows;
}

/// Build the test widget with provider overrides that supply data.
Widget _buildSubject({
  UserModel? userProfile,
  UserModel? partnerProfile,
  OverlapResult? overlapResult,
  bool overlapLoading = false,
  Object? overlapError,
}) {
  final user = userProfile ??
      _makeUser(timezone: 'Africa/Johannesburg', coupleId: 'couple-1');
  final partner = partnerProfile ??
      _makeUser(
        timezone: 'America/New_York',
        email: 'partner@test.com',
        displayName: 'Partner',
      );
  final overlap = overlapResult ??
      OverlapResult(
        windows: _generateMockWindows(),
        computedAt: DateTime.now(),
        blockHashA: 'hash_a',
        blockHashB: 'hash_b',
      );

  return ProviderScope(
    overrides: [
      currentUserProfileProvider.overrideWithValue(user),
      partnerProfileProvider.overrideWith(
        (ref) => Future.value(partner),
      ),
      if (overlapError != null)
        overlapWindowsProvider.overrideWith(
          (ref) => Stream.error(overlapError),
        )
      else if (overlapLoading)
        overlapWindowsProvider.overrideWith(
          (ref) => const Stream<OverlapResult?>.empty(),
        )
      else
        overlapWindowsProvider.overrideWith(
          (ref) => Stream.value(overlap),
        ),
    ],
    child: const MaterialApp(
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
      await tester.pumpAndSettle();
      expect(find.text('Mutual Free Time'), findsOneWidget);
    });

    testWidgets('displays filter icon button in app bar', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
    });

    testWidgets('renders WindowCardWidget items in list', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.byType(WindowCardWidget), findsAtLeast(1));
    });

    testWidgets('limits displayed windows to at most 10', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      final cards = tester.widgetList(find.byType(WindowCardWidget));
      expect(cards.length, lessThanOrEqualTo(10));
    });

    testWidgets('has a ListView.builder for scrollable content',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('OverlapScreen async states', () {
    testWidgets('shows loading spinner when data is loading', (tester) async {
      await tester.pumpWidget(_buildSubject(overlapLoading: true));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state with retry button on error',
        (tester) async {
      await tester.pumpWidget(
          _buildSubject(overlapError: Exception('Network error')));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows no couple message when user has no coupleId',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        userProfile: _makeUser(timezone: 'Africa/Johannesburg', coupleId: null),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No couple paired yet.'), findsOneWidget);
    });

    testWidgets('shows no overlaps message when result has empty windows',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        overlapResult: OverlapResult(
          windows: const [],
          computedAt: DateTime.now(),
          blockHashA: 'a',
          blockHashB: 'b',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No overlap windows found.'), findsOneWidget);
    });
  });

  group('OverlapScreen filter dialog', () {
    testWidgets('tapping filter icon opens filter dialog', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      expect(find.text('Filter & Sort'), findsOneWidget);
    });

    testWidgets('filter dialog shows duration choices', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      expect(find.text('Minimum Score'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
    });

    testWidgets('filter dialog shows sort choices', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      expect(find.text('Clear All'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('Apply button closes the dialog', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Filter & Sort'), findsNothing);
    });

    testWidgets('selecting a duration filter shows filter summary bar',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      // Tap the first WindowCardWidget
      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      expect(find.text('Window Details'), findsOneWidget);
    });

    testWidgets('details dialog shows score breakdown', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      expect(find.text('Score Breakdown'), findsOneWidget);
      expect(find.text('Overall Score'), findsOneWidget);
      expect(find.text('Duration Score'), findsOneWidget);
      expect(find.text('Timing Score'), findsOneWidget);
    });

    testWidgets('details dialog shows time info', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      expect(find.text('Your Time'), findsOneWidget);
      expect(find.text("Partner's Time"), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
    });

    testWidgets('details dialog has Close button', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Close button dismisses details dialog', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Window Details'), findsNothing);
    });

    testWidgets('details dialog shows reasonable hours indicator',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

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
