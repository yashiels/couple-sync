import 'package:couple_sync/services/sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Backend base URLs. Override at build time via `--dart-define` so release
/// builds point at prod and dev can target a local tunnel. Defaults assume the
/// VPS production host.
const _kDefaultBaseUrl = String.fromEnvironment(
  'SYNC_BASE_URL',
  defaultValue: 'https://api.coupleschedule.app',
);

const _kDefaultWsUrl = String.fromEnvironment(
  'SYNC_WS_URL',
  defaultValue: 'wss://api.coupleschedule.app/sync',
);

/// Provider for the [SyncService] — the app's sole data layer after V7
/// (replaces the retired `firestoreServiceProvider`). The service is given a
/// [tokenProvider] that mints a fresh Firebase ID token on each call so the
/// backend can verify the caller. Constructed lazily; disposed with the
/// [ProviderContainer].
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    baseUrl: _kDefaultBaseUrl,
    wsUrl: _kDefaultWsUrl,
    tokenProvider: () async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return user.getIdToken();
    },
  );
  ref.onDispose(service.dispose);
  return service;
});
