import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Top-level handler for background/terminated FCM messages.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs (via the plugin).
  debugPrint('FCM background message: ${message.messageId}');
}

/// Singleton service that initialises FCM and local notifications, and saves
/// the device token to Firestore for server-side push delivery.
class NotificationService {
  NotificationService._();

  /// The global [NotificationService] singleton.
  static final NotificationService instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'couple_schedule_default',
    'Couple Schedule',
    description: 'General notifications for Couple Schedule',
    importance: Importance.high,
  );

  /// Call once from main() after Firebase.initializeApp().
  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _initLocalNotifications();
    await _requestPermission();
    _listenForeground();
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(settings);

    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');
  }

  void _listenForeground() {
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _showLocalNotification(
        id: message.hashCode,
        title: notification.title ?? '',
        body: notification.body ?? '',
      );
    });
  }

  void _showLocalNotification({
    required int id,
    required String title,
    required String body,
  }) {
    _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Fetches the current FCM token and persists it to the user's Firestore
  /// document at `users/{uid}`.
  Future<void> saveTokenToFirestore(String uid) async {
    final token = await _messaging.getToken();
    if (token == null) return;

    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'fcmToken': token, 'tokenUpdatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    // Refresh whenever the token rotates.
    _messaging.onTokenRefresh.listen((newToken) {
      FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmToken': newToken, 'tokenUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    });
  }
}
