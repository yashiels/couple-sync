import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'shared/providers/auth_providers.dart';
import 'shared/providers/pairing_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
  }
  runApp(const ProviderScope(child: CoupleScheduleApp()));
}

class CoupleScheduleApp extends ConsumerStatefulWidget {
  const CoupleScheduleApp({super.key});

  @override
  ConsumerState<CoupleScheduleApp> createState() => _CoupleScheduleAppState();
}

class _CoupleScheduleAppState extends ConsumerState<CoupleScheduleApp> {
  @override
  void initState() {
    super.initState();
    _hydrateSession();
  }

  Future<void> _hydrateSession() async {
    try {
      final authService = ref.read(authServiceProvider);
      final firebaseUser = authService.currentUser;
      if (firebaseUser != null) {
        final userModel = await authService.fetchUserModel(firebaseUser.uid);
        if (!mounted || authService.currentUser?.uid != firebaseUser.uid) return;
        if (userModel != null) {
          ref.read(currentUserProvider.notifier).state = userModel;
          if (userModel.coupleId != null) {
            final couple = await authService.fetchCoupleForUser(firebaseUser.uid);
            if (mounted) {
              ref.read(currentCoupleProvider.notifier).state = couple;
            }
          }
        }
      } else {
        ref.read(currentUserProvider.notifier).state = null;
        ref.read(currentCoupleProvider.notifier).state = null;
      }
    } catch (e) {
      debugPrint('Session hydration failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state changes to re-hydrate on sign-in/sign-out
    ref.listen(firebaseAuthStateProvider, (prev, next) {
      final prevUser = prev?.valueOrNull;
      final nextUser = next.valueOrNull;
      if (prevUser?.uid != nextUser?.uid) {
        _hydrateSession();
      }
    });

    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Couple Schedule',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
