import 'dart:async';

import 'package:couple_sync/core/models/overlap_result.dart';
import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/core/overlap/overlap_controller.dart';
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
      score: [10, 20, 30, 40, 50, 55][i % 6].toDouble(),
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
        inputHash: 'hash',
      );

  return ProviderScope(
    overrides: [
      currentUserProfileProvider.overrideWithValue(user),
      partnerProfileProvider.overrideWith(
        (ref) => Future.value(partner),
      ),
      // overlap_screen now reads overlapControllerProvider(coupleId) (the
      // device-side AsyncNotifier), not overlapWindowsProvider. Override the
      // family with a stub controller that returns the test OverlapResult.
      overlapControllerProvider.overrideWith(
        () => _StubOverlapController(
          result: overlap,
          error: overlapError,
          loading: overlapLoading,
        ),
      ),
    ],
    child: const MaterialApp(
      home: OverlapScreen(),
    ),
  );
}

/// Test-only [OverlapController] that short-circuits [build] to return a fixed
/// [OverlapResult] (or throw / hang) instead of wiring up Firestore streams.
class _StubOverlapController extends OverlapController {
  final OverlapResult? result;
  final Object? error;
  final bool loading;

  _StubOverlapController({
    this.result,
    this.error,
    this.loading = false,
  });

  @override
  Future<OverlapResult> build(String coupleId) {
    if (error != null) throw error!;
    if (loading) {
      // Never-completing future keeps the provider in the loading state.
      return Completer<OverlapResult>().future;
    }
    return Future.value(result ??
        OverlapResult(
          windows: const [],
          computedAt: DateTime.now(),
          inputHash: '',
        ));
  }
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
          inputHash: 'a',
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
      expect(find.text('15+'), findsOneWidget);
      expect(find.text('25+'), findsOneWidget);
      expect(find.text('40+'), findsOneWidget);
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

      // Select 25+ score filter
      await tester.tap(find.text('25+'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Min score 25'), findsOneWidget);
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

    testWidgets('details dialog shows score', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(WindowCardWidget).first);
      await tester.pumpAndSettle();

      expect(find.text('Score'), findsWidgets);
      // Fabricated sub-scores have been removed — only the real score is shown.
      expect(find.text('Duration Score'), findsNothing);
      expect(find.text('Timing Score'), findsNothing);
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
