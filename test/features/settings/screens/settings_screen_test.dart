import 'package:couple_sync/core/models/user_model.dart';
import 'package:couple_sync/features/settings/screens/settings_screen.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:couple_sync/services/providers/calendar_provider.dart';
import 'package:couple_sync/services/providers/couple_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creates a mock UserModel for testing.
UserModel _createMockUser({
  String email = 'test@example.com',
  String displayName = 'Test User',
  String timezone = 'Africa/Johannesburg',
  String? coupleId,
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

Widget _buildSubject({
  UserModel? userProfile,
  bool calendarConnected = false,
  Size screenSize = const Size(400, 1200), // tall screen to show all sections
}) {
  final profile = userProfile ?? _createMockUser();

  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith((_) {
        return _SimpleAuthStateNotifier(AuthState(
          userProfile: profile,
          isLoading: false,
        ));
      }),
      calendarConnectionNotifierProvider.overrideWith((ref) {
        return _SimpleCalendarNotifier(calendarConnected);
      }),
      calendarSyncNotifierProvider.overrideWith((ref) {
        return _SimpleCalendarSyncNotifier();
      }),
      notificationSettingsProvider.overrideWith((ref) {
        return NotificationSettingsNotifier();
      }),
      // Override coupleProvider to avoid hitting Firestore
      coupleProvider.overrideWith((ref) async => null),
      partnerProfileProvider.overrideWith((ref) async => null),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: const SettingsScreen(),
      ),
    ),
  );
}

/// Simple notifier that holds a fixed AuthState without touching Firebase.
class _SimpleAuthStateNotifier extends StateNotifier<AuthState>
    implements AuthStateNotifier {
  _SimpleAuthStateNotifier(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Simple notifier that holds a fixed calendar connection state.
class _SimpleCalendarNotifier extends StateNotifier<AsyncValue<bool>>
    implements CalendarConnectionNotifier {
  _SimpleCalendarNotifier(bool connected)
      : super(AsyncValue.data(connected));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Simple notifier that holds a fixed calendar sync state.
class _SimpleCalendarSyncNotifier extends StateNotifier<CalendarSyncState>
    implements CalendarSyncNotifier {
  _SimpleCalendarSyncNotifier([CalendarSyncState? initialState])
      : super(initialState ?? const CalendarSyncState());

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Helper to scroll until a finder is visible.
Future<void> _scrollUntilVisible(
  WidgetTester tester,
  Finder finder, {
  double delta = -300.0,
}) async {
  final listView = find.byType(ListView);
  int attempts = 0;
  while (finder.evaluate().isEmpty && attempts < 10) {
    await tester.drag(listView, Offset(0, delta));
    await tester.pumpAndSettle();
    attempts++;
  }
}

void main() {
  group('SettingsScreen rendering', () {
    testWidgets('displays app bar with "Settings" title', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('displays Calendar section', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('Calendar'), findsOneWidget);
    });

    testWidgets('displays Timezone section', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('Timezone'), findsOneWidget);
    });

    testWidgets('displays Window Preferences section after scrolling',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Window Preferences'));
      expect(find.text('Window Preferences'), findsOneWidget);
    });

    testWidgets('displays Notifications section after scrolling',
        (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Notifications'));
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('displays Account section after scrolling', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Account'));
      expect(find.text('Account'), findsOneWidget);
    });

    testWidgets('has a scrollable ListView', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('SettingsScreen Calendar section', () {
    testWidgets('shows Google Calendar status', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('Google Calendar'), findsOneWidget);
    });

    testWidgets('shows Last Sync status', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('Last Sync'), findsOneWidget);
    });

    testWidgets('shows Connect Calendar button when not connected',
        (tester) async {
      await tester.pumpWidget(_buildSubject(calendarConnected: false));
      await tester.pumpAndSettle();
      expect(find.text('Connect Calendar'), findsAtLeast(1));
    });

    testWidgets('shows Disconnect button when connected', (tester) async {
      await tester.pumpWidget(_buildSubject(calendarConnected: true));
      await tester.pumpAndSettle();
      expect(find.text('Disconnect'), findsAtLeast(1));
    });

    testWidgets('shows Manual Sync option', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      expect(find.text('Manual Sync'), findsOneWidget);
    });
  });

  group('SettingsScreen Timezone section', () {
    testWidgets('shows current timezone', (tester) async {
      await tester.pumpWidget(_buildSubject(
        userProfile: _createMockUser(timezone: 'Africa/Johannesburg'),
      ));
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Africa/Johannesburg'));
      expect(find.text('Africa/Johannesburg'), findsOneWidget);
    });

    testWidgets('shows Change Timezone button', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Change Timezone'));
      expect(find.text('Change Timezone'), findsOneWidget);
    });
  });

  group('SettingsScreen Window Preferences section', () {
    testWidgets('shows late-night windows toggle', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Show late-night windows'));
      expect(find.text('Show late-night windows'), findsOneWidget);
    });

    testWidgets('late-night toggle defaults to off', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Show late-night windows'));
      final switchFinder = find.descendant(
        of: find.ancestor(
          of: find.text('Show late-night windows'),
          matching: find.byType(Card),
        ),
        matching: find.byType(Switch),
      );
      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isFalse);
    });
  });

  group('SettingsScreen Notifications section', () {
    testWidgets('shows notification toggle', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('New Window Alerts'));
      expect(find.text('New Window Alerts'), findsOneWidget);
    });

    testWidgets('notification toggle defaults to enabled', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('New Window Alerts'));
      final switchFinder = find.descendant(
        of: find.ancestor(
          of: find.text('New Window Alerts'),
          matching: find.byType(Card),
        ),
        matching: find.byType(Switch),
      );
      final switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isTrue);
    });
  });

  group('SettingsScreen Account section', () {
    testWidgets('shows user email', (tester) async {
      await tester.pumpWidget(_buildSubject(
        userProfile: _createMockUser(email: 'test@example.com'),
      ));
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('test@example.com'));
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('shows display name', (tester) async {
      await tester.pumpWidget(_buildSubject(
        userProfile: _createMockUser(displayName: 'Test User'),
      ));
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Test User'));
      expect(find.text('Test User'), findsOneWidget);
    });

    testWidgets('shows Sign Out button', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Sign Out'));
      expect(find.text('Sign Out'), findsAtLeast(1));
    });

    testWidgets('tapping Sign Out shows confirmation dialog', (tester) async {
      await tester.pumpWidget(_buildSubject());
      await tester.pumpAndSettle();
      await _scrollUntilVisible(tester, find.text('Sign Out'));

      // Ensure the Sign Out button is visible on screen before tapping
      await tester.ensureVisible(find.text('Sign Out').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign Out').last);
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to sign out?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('SettingsScreen without couple', () {
    testWidgets('does not show Couple section when user has no coupleId',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        userProfile: _createMockUser(coupleId: null),
      ));
      await tester.pumpAndSettle();

      // Scroll through entire list to be sure
      await _scrollUntilVisible(tester, find.text('Account'));

      final coupleSections = find.text('Couple');
      expect(coupleSections, findsNothing);
    });
  });
}
