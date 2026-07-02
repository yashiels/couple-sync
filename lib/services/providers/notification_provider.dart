import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../notification_service.dart';
import 'auth_state_provider.dart';
import 'sync_provider.dart';

/// Provider for the NotificationService singleton.
///
/// Wires [NotificationService.dispose] to Riverpod's lifecycle so that the
/// underlying [StreamSubscription]s are cancelled when the provider scope is
/// destroyed — preventing subscription leaks in production.
///
/// [NotificationService.initialize] is called automatically once the user is
/// authenticated. If the provider is created before auth resolves, initialize
/// is a no-op until [authStateProvider] emits an authenticated state.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(
    syncService: ref.watch(syncServiceProvider),
  );
  ref.onDispose(service.dispose);

  // Initialize as soon as a userId is available. Re-runs whenever auth state
  // changes so the service tracks the correct user after sign-in.
  ref.listen<AuthState>(authStateProvider, (previous, next) {
    final uid = next.uid;
    if (uid != null && previous?.uid != uid) {
      service.initialize(uid);
    }
  }, fireImmediately: true);

  return service;
});
