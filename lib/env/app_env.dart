/// Build-time app configuration.
///
/// Values are baked in via `--dart-define` (or `--dart-define-from-file`),
/// so they MUST be `const` — without `const`, `String.fromEnvironment`
/// silently returns the default on AOT/release builds.
///
///   flutter run --dart-define=API_BASE_URL=http://localhost:3000 \
///               --dart-define=WS_URL=ws://localhost:3000
///   flutter build apk --dart-define-from-file=env/prod.json
class AppEnv {
  AppEnv._();

  /// Base URL of the self-hosted backend (no trailing slash), e.g.
  /// `https://api.coupleschedule.app`. Behind the platform proxy (Traefik).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// WebSocket URL for the `/sync` endpoint, e.g.
  /// `wss://api.coupleschedule.app/sync` (prod, TLS) or
  /// `ws://localhost:3000/sync` (dev).
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://localhost:3000/sync',
  );

  /// Fail fast if the build didn't define the API URLs (catches a release
  /// build shipped without `--dart-define`).
  static void validate() {
    if (apiBaseUrl.isEmpty || wsUrl.isEmpty) {
      throw AssertionError(
        'API_BASE_URL/WS_URL must be set via --dart-define '
        '(or --dart-define-from-file=env/prod.json).',
      );
    }
  }
}
