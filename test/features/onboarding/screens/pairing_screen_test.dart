import 'package:couple_sync/features/onboarding/screens/pairing_screen.dart';
import 'package:couple_sync/features/onboarding/widgets/share_code_tab.dart';
import 'package:couple_sync/features/onboarding/widgets/enter_code_tab.dart';
import 'package:couple_sync/services/providers/auth_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject() {
    // PairingScreen reads authStateProvider.uid in initState for the Firestore listener.
    // Override with a state that has no uid so the listener is skipped.
    return ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => _TestAuthNotifier())],
      child: const MaterialApp(home: PairingScreen()),
    );
  }

  group('PairingScreen', () {
    testWidgets('renders AppBar with correct title', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Pair with Partner'), findsOneWidget);
    });

    testWidgets('renders two tabs: Share Code and Enter Code', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('Share Code'), findsOneWidget);
      expect(find.text('Enter Code'), findsOneWidget);
    });

    testWidgets('shows ShareCodeTab by default on first tab', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(ShareCodeTab), findsOneWidget);
    });

    testWidgets('shows EnterCodeTab when Enter Code tab is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter Code'));
      await tester.pumpAndSettle();

      expect(find.byType(EnterCodeTab), findsOneWidget);
    });

    testWidgets('has a TabBar with 2 tabs', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(Tab), findsNWidgets(2));
    });

    testWidgets('has a TabBarView', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byType(TabBarView), findsOneWidget);
    });

    testWidgets('does not show back button in AppBar', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // automaticallyImplyLeading: false means no back button
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.automaticallyImplyLeading, isFalse);
    });

    testWidgets('can switch between tabs via swipe', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();

      // Swipe left to go to Enter Code tab
      await tester.fling(find.byType(TabBarView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.byType(EnterCodeTab), findsOneWidget);
    });
  });
}

/// Test-only notifier that doesn't call Firebase.
class _TestAuthNotifier extends StateNotifier<AuthState>
    implements AuthStateNotifier {
  _TestAuthNotifier() : super(const AuthState(isLoading: false));

  @override
  Future<void> refreshProfile() async {}
  @override
  Future<bool> signInWithGoogle() async => false;
  @override
  Future<bool> signInWithApple() async => false;
  @override
  Future<bool> signInWithEmail(String email, String password) async => false;
  @override
  Future<void> signOut() async {}
  @override
  String? get lastError => null;
  @override
  void clearError() {}
}
