import 'package:couple_sync/env/app_env.dart';
import 'package:couple_sync/services/sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the [SyncService] — the app's sole data layer after V7
/// (replaces the retired `firestoreServiceProvider`). The service is given a
/// [tokenProvider] that mints a fresh Firebase ID token on each call so the
/// backend can verify the caller. Backend URLs come from [AppEnv]
/// (`--dart-define=API_BASE_URL` / `WS_URL`). Constructed lazily; disposed
/// with the [ProviderContainer].
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    baseUrl: AppEnv.apiBaseUrl,
    wsUrl: AppEnv.wsUrl,
    tokenProvider: () async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return user.getIdToken();
    },
  );
  ref.onDispose(service.dispose);
  return service;
});
