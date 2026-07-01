import 'package:couple_sync/core/models/overlap_result.dart';
import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/home/screens/home_screen.dart';
import 'package:couple_sync/features/home/partner_clock_widget.dart';
import 'package:couple_sync/features/home/next_window_card_widget.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:couple_sync/services/calendar_service.dart';
import 'package:couple_sync/services/providers/calendar_provider.dart';
import 'package:couple_sync/services/providers/couple_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;

/// Generate mock overlap windows for testing.
OverlapResult _generateMockOverlapResult() {
  final now = DateTime.now();
  final windows = <OverlapWindow>[];

  for (int i = 0; i < 6; i++) {
    final start = now.add(Duration(days: i + 1, hours: 18));
    final end = start.add(const Duration(hours: 2));

    windows.add(OverlapWindow(
      startUtc: start.millisecondsSinceEpoch,
      endUtc: end.millisecondsSinceEpoch,
      durationMinutes: 120,
      score: 45 - (i * 3).toDouble(),
      reasonableBoth: true,
    ));
  }

  return OverlapResult(
    windows: windows,
    computedAt: now,
    inputHash: 'mock_hash',
  );
}

/// Mock user profile for the current user.
final _mockUserProfile = UserModel(
  email: 'user@test.com',
  displayName: 'Test User',
  timezone: 'Africa/Johannesburg',
  coupleId: 'couple123',
  fcmTokens: [],
  createdAt: DateTime(2024, 1, 1),
);

/// Mock partner profile.
final _mockPartnerProfile = UserModel(
  email: 'partner@test.com',
  displayName: 'Partner',
  timezone: 'Europe/London',
  coupleId: 'couple123',
  fcmTokens: [],
  createdAt: DateTime(2024, 1, 1),
);

/// Build the subject under test with provider overrides that supply mock data.
Widget _buildSubject({
  UserModel? userProfile,
  UserModel? partnerProfile,
  OverlapResult? overlapResult,
}) {
  final effectiveUserProfile = userProfile ?? _mockUserProfile;
  final effectivePartnerProfile = partnerProfile ?? _mockPartnerProfile;
  final effectiveOverlapResult = overlapResult ?? _generateMockOverlapResult();

  return ProviderScope(
    overrides: [
      currentUserProfileProvider.overrideWithValue(effectiveUserProfile),
      partnerProfileProvider
          .overrideWith((ref) async => effectivePartnerProfile),
      overlapWindowsProvider
          .overrideWith((ref) => Stream.value(effectiveOverlapResult)),
      calendarSyncNotifierProvider.overrideWith(
        (ref) => _NoOpCalendarSyncNotifier(),
      ),
    ],
    child: const MaterialApp(
      home: HomeScreen(),
    ),
  );
}

/// Build with no couple (coupleId is null) to test the "no partner" state.
Widget _buildNoCoupleSubject() {
  final noCoupleProfile = _mockUserProfile.copyWith(clearCoupleId: true);

  return ProviderScope(
    overrides: [
      currentUserProfileProvider.overrideWithValue(noCoupleProfile),
      partnerProfileProvider.overrideWith((ref) async => null),
      overlapWindowsProvider
          .overrideWith((ref) => Stream.value(null)),
      calendarSyncNotifierProvider.overrideWith(
        (ref) => _NoOpCalendarSyncNotifier(),
      ),
    ],
    child: const MaterialApp(
      home: HomeScreen(),
    ),
  );
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('HomeScreen rendering', () {
    testWidgets('displays app bar with "Couple Sync" title', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('Couple Sync'), findsOneWidget);
    });

    testWidgets('displays settings icon in app bar', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('displays PartnerClockWidget', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.byType(PartnerClockWidget), findsOneWidget);
    });

    testWidgets('displays NextWindowCard', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.byType(NextWindowCard), findsOneWidget);
    });

    testWidgets('displays "Upcoming Windows" section header', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('Upcoming Windows'), findsOneWidget);
    });

    testWidgets('displays FAB with add icon', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('has a RefreshIndicator for pull-to-refresh', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('HomeScreen no couple state', () {
    testWidgets('shows "No partner yet" when user has no coupleId',
        (tester) async {
      await tester.pumpWidget(_buildNoCoupleSubject());
      await tester.pumpAndSettle();
      expect(find.text('No partner yet'), findsOneWidget);
    });

    testWidgets('shows pairing message when user has no coupleId',
        (tester) async {
      await tester.pumpWidget(_buildNoCoupleSubject());
      await tester.pumpAndSettle();
      expect(
        find.text(
            'Pair with your partner to start finding mutual free time.'),
        findsOneWidget,
      );
    });
  });

  group('HomeScreen FAB quick actions', () {
    testWidgets('tapping FAB shows bottom sheet with actions',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Add Block'), findsOneWidget);
      expect(find.text('Sync Calendar'), findsOneWidget);
      expect(find.text('View All Windows'), findsOneWidget);
    });

    testWidgets('bottom sheet shows subtitles for each action',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Block out time in your schedule'), findsOneWidget);
      expect(find.text('Refresh from Google Calendar'), findsOneWidget);
      expect(find.text('See all upcoming free times'), findsOneWidget);
    });

    testWidgets('bottom sheet shows icons for each action', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.byIcon(Icons.sync), findsOneWidget);
      expect(find.byIcon(Icons.calendar_view_day), findsOneWidget);
    });

    testWidgets('tapping Sync Calendar dismisses bottom sheet',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sync Calendar'));
      await tester.pumpAndSettle();

      // Bottom sheet should be dismissed
      expect(find.text('Refresh from Google Calendar'), findsNothing);
    });
  });

  group('HomeScreen pull-to-refresh', () {
    testWidgets('shows loading indicator during refresh', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      // Trigger pull-to-refresh by dragging down
      await tester.fling(
        find.byType(SingleChildScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();

      // The refresh indicator should be visible
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('HomeScreen upcoming windows list', () {
    testWidgets('renders upcoming window cards with score numbers',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      // Mock data generates 6 windows; first is nextWindow, remaining 5 are upcoming
      // Each has a raw score displayed as a number (e.g. 45, 42, 39...)
      // The first window (score 45) is in the NextWindowCard, others in list
      expect(find.text('42'), findsAtLeast(1));
    });

    testWidgets('renders upcoming window cards with duration', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();

      // All mock windows have 120 minutes duration
      expect(find.text('2 hr'), findsWidgets);
    });
  });
}

class _NoOpCalendarSyncNotifier extends StateNotifier<CalendarSyncState>
    implements CalendarSyncNotifier {
  _NoOpCalendarSyncNotifier() : super(const CalendarSyncState());

  @override
  Future<CalendarSyncResult?> autoSyncIfNeeded() async => null;

  @override
  Future<CalendarSyncResult> sync() async => CalendarSyncResult(
        blocksFetched: 0,
        blocksDeleted: 0,
        blocksCreated: 0,
        syncedAt: DateTime.now(),
      );

  @override
  Future<void> refreshLastSyncTime() async {}
}
