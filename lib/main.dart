import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'core/router/router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'shared/providers/auth_providers.dart';
import 'shared/providers/pairing_providers.dart';
import 'shared/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.instance.init();
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }

  // Create the ProviderContainer and GoRouter OUTSIDE the widget tree.
  // This avoids Riverpod's _UncontrolledProviderScopeElement calling
  // markNeedsBuild() during its own mount when provider state changes
  // (e.g. Firebase Auth stream emitting cached user), which causes
  // the `!_dirty` assertion crash in framework.dart.
  final container = ProviderContainer();

  // Force-create firebaseAuthStateProvider so its synchronous emission
  // (cached Firebase user) happens before any widget builds.
  container.read(firebaseAuthStateProvider);

  // Create the router using the container directly — no ref.watch needed.
  final router = createAppRouter(container);

  // Listen for auth state changes to drive session hydration.
  // This replaces the ref.listen that was previously in CoupleScheduleApp.build().
  container.listen<AsyncValue<User?>>(firebaseAuthStateProvider, (prev, next) {
    final prevUser = prev?.valueOrNull;
    final nextUser = next.valueOrNull;
    if (prevUser?.uid != nextUser?.uid) {
      _hydrateSession(container);
    }
  });

  // Run initial session hydration.
  _hydrateSession(container);

  runApp(UncontrolledProviderScope(
    container: container,
    child: CoupleScheduleApp(router: router),
  ));
}

/// Restores user and couple state from Firestore when a Firebase user is
/// already signed in (persisted session) or when auth state changes.
bool _hydrating = false;

Future<void> _hydrateSession(ProviderContainer container) async {
  if (_hydrating) return;
  _hydrating = true;
  try {
    final authService = container.read(authServiceProvider);
    final firebaseUser = authService.currentUser;
    if (firebaseUser != null) {
      final userModel = await authService.fetchUserModel(firebaseUser.uid);
      if (authService.currentUser?.uid != firebaseUser.uid) return;
      if (userModel != null) {
        container.read(currentUserProvider.notifier).state = userModel;
        if (userModel.coupleId != null) {
          final couple =
              await authService.fetchCoupleForUser(firebaseUser.uid);
          container.read(currentCoupleProvider.notifier).state = couple;
        }
        container
            .read(authNotifierProvider.notifier)
            .setStatus(AuthStatus.authenticated);
      }
    } else {
      container.read(currentUserProvider.notifier).state = null;
      container.read(currentCoupleProvider.notifier).state = null;
    }
  } catch (e) {
    debugPrint('Session hydration failed: $e');
  } finally {
    _hydrating = false;
    container.read(hydrationCompleteProvider.notifier).state = true;
  }
}

class CoupleScheduleApp extends StatelessWidget {
  const CoupleScheduleApp({super.key, required this.router});
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Couple Schedule',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
