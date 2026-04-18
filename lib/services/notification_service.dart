import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Abstract interface for displaying local notifications in the foreground.
/// Implementations can use flutter_local_notifications or any other backend.
abstract class LocalNotificationDisplay {
  Future<void> show({required String title, required String body});
}

/// Service for managing FCM push notifications.
///
/// Responsibilities:
/// - Request notification permissions on iOS
/// - Register and refresh FCM token in Firestore
/// - Handle foreground messages (show local notification unless suppressed)
/// - Background messages are handled natively by the OS
///
/// Usage:
/// ```dart
/// final service = NotificationService(display: MyDisplayImpl());
/// await service.initialize(currentUserId);
/// ```
class NotificationService {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final LocalNotificationDisplay? _display;
  final Stream<RemoteMessage> _messageStream;
  bool _suppressDisplay = false;

  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    LocalNotificationDisplay? display,
    Stream<RemoteMessage>? messageStream,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _display = display,
        _messageStream = messageStream ?? FirebaseMessaging.onMessage;

  /// Initialize FCM: request permissions, register token, set up handlers.
  ///
  /// Must be called after Firebase.initializeApp() and after the user is
  /// authenticated so the token can be stored against their UID.
  Future<void> initialize(String userId) async {
    // Request permissions — required on iOS, no-op on Android
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get current token and store in Firestore
    final token = await _messaging.getToken();
    if (token != null) {
      await storeToken(userId, token);
    }

    // Handle token refresh (device rotation, reinstall, etc.)
    _messaging.onTokenRefresh.listen((newToken) {
      storeToken(userId, newToken);
    });

    // Handle messages received while app is in the foreground
    _messageStream.listen(handleForegroundMessage);
  }

  /// Store or refresh an FCM token in the user's Firestore document.
  /// Uses arrayUnion so duplicate tokens are never written.
  Future<void> storeToken(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
    } catch (_) {
      // Silently fail if user doc doesn't exist yet — token will be stored on next refresh
    }
  }

  /// Handle a message received while the app is in the foreground.
  /// Delegates to [_display] unless [_suppressDisplay] is true.
  void handleForegroundMessage(RemoteMessage message) {
    if (_suppressDisplay) return;

    final notification = message.notification;
    if (notification == null) return;

    _display?.show(
      title: notification.title ?? 'New free time found!',
      body: notification.body ?? 'Check your overlap windows.',
    );
  }

  /// Set whether foreground notification display is suppressed.
  /// When suppressed, FCM messages still arrive but are not shown to the user.
  void setSuppressDisplay(bool suppress) {
    _suppressDisplay = suppress;
  }

  /// Whether foreground notification display is currently suppressed.
  bool get isSuppressed => _suppressDisplay;
}
