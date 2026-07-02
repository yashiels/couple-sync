import 'dart:async';

import 'package:couple_sync/services/notification_service.dart';
import 'package:couple_sync/services/sync_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([
  FirebaseMessaging,
  LocalNotificationDisplay,
  NotificationSettings,
  SyncService,
])
import 'notification_service_test.mocks.dart';

void main() {
  late MockFirebaseMessaging mockMessaging;
  late MockLocalNotificationDisplay mockDisplay;
  late MockSyncService mockSyncService;
  late MockNotificationSettings mockSettings;

  setUp(() {
    mockMessaging = MockFirebaseMessaging();
    mockDisplay = MockLocalNotificationDisplay();
    mockSyncService = MockSyncService();
    mockSettings = MockNotificationSettings();

    // storeToken swallows errors in production; default to a no-op.
    when(mockSyncService.registerFcmToken(any)).thenAnswer((_) async {});
  });

  NotificationService createService({Stream<RemoteMessage>? messageStream}) {
    return NotificationService(
      messaging: mockMessaging,
      syncService: mockSyncService,
      display: mockDisplay,
      messageStream: messageStream ?? const Stream.empty(),
    );
  }

  group('NotificationService', () {
    group('initialize', () {
      setUp(() {
        when(mockMessaging.requestPermission(
          alert: anyNamed('alert'),
          badge: anyNamed('badge'),
          sound: anyNamed('sound'),
        )).thenAnswer((_) async => mockSettings);
        when(mockMessaging.onTokenRefresh)
            .thenAnswer((_) => const Stream.empty());
      });

      test('requests FCM permission with alert, badge, and sound enabled',
          () async {
        when(mockMessaging.getToken()).thenAnswer((_) async => null);
        final service = createService();

        await service.initialize('user-123');

        verify(mockMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        )).called(1);
      });

      test('stores FCM token when token is available', () async {
        when(mockMessaging.getToken())
            .thenAnswer((_) async => 'test-fcm-token');
        final service = createService();

        await service.initialize('user-123');

        verify(mockSyncService.registerFcmToken('test-fcm-token')).called(1);
      });

      test('skips token storage when FCM token is null', () async {
        when(mockMessaging.getToken()).thenAnswer((_) async => null);
        final service = createService();

        await service.initialize('user-123');

        verifyNever(mockSyncService.registerFcmToken(any));
      });

      test('forwards foreground messages to handleForegroundMessage', () async {
        when(mockMessaging.getToken()).thenAnswer((_) async => null);
        when(mockDisplay.show(
          title: anyNamed('title'),
          body: anyNamed('body'),
        )).thenAnswer((_) async {});

        final messageController = StreamController<RemoteMessage>();
        final service = createService(messageStream: messageController.stream);

        await service.initialize('user-123');

        messageController.add(RemoteMessage(
          notification: const RemoteNotification(
            title: 'New window!',
            body: 'You have free time',
          ),
        ));

        // Allow the stream listener to process
        await Future.microtask(() {});

        verify(mockDisplay.show(
          title: 'New window!',
          body: 'You have free time',
        )).called(1);

        await messageController.close();
      });
    });

    group('storeToken', () {
      test('calls registerFcmToken with the token', () async {
        final service = createService();

        await service.storeToken('user-456', 'my-token');

        verify(mockSyncService.registerFcmToken('my-token')).called(1);
      });
    });

    group('handleForegroundMessage', () {
      test('shows local notification when not suppressed', () {
        final service = createService();
        when(mockDisplay.show(
          title: anyNamed('title'),
          body: anyNamed('body'),
        )).thenAnswer((_) async {});

        service.handleForegroundMessage(RemoteMessage(
          notification: const RemoteNotification(
            title: 'New Free Time!',
            body: 'You have a new overlap window',
          ),
        ));

        verify(mockDisplay.show(
          title: 'New Free Time!',
          body: 'You have a new overlap window',
        )).called(1);
      });

      test('does not show notification when display is suppressed', () {
        final service = createService();
        service.setSuppressDisplay(true);

        service.handleForegroundMessage(RemoteMessage(
          notification: const RemoteNotification(
            title: 'New Free Time!',
            body: 'You have a new overlap window',
          ),
        ));

        verifyNever(mockDisplay.show(
          title: anyNamed('title'),
          body: anyNamed('body'),
        ));
      });

      test('uses fallback title when notification title is null', () {
        final service = createService();
        when(mockDisplay.show(
          title: anyNamed('title'),
          body: anyNamed('body'),
        )).thenAnswer((_) async {});

        service.handleForegroundMessage(RemoteMessage(
          notification: const RemoteNotification(
            title: null,
            body: 'Some body',
          ),
        ));

        verify(mockDisplay.show(
          title: 'New free time found!',
          body: 'Some body',
        )).called(1);
      });

      test('uses fallback body when notification body is null', () {
        final service = createService();
        when(mockDisplay.show(
          title: anyNamed('title'),
          body: anyNamed('body'),
        )).thenAnswer((_) async {});

        service.handleForegroundMessage(RemoteMessage(
          notification: const RemoteNotification(
            title: 'New window!',
            body: null,
          ),
        ));

        verify(mockDisplay.show(
          title: 'New window!',
          body: 'Check your overlap windows.',
        )).called(1);
      });

      test('skips display when message has no notification payload', () {
        final service = createService();

        service.handleForegroundMessage(RemoteMessage());

        verifyNever(mockDisplay.show(
          title: anyNamed('title'),
          body: anyNamed('body'),
        ));
      });
    });

    group('setSuppressDisplay', () {
      test('isSuppressed is false by default', () {
        final service = createService();
        expect(service.isSuppressed, isFalse);
      });

      test('setSuppressDisplay(true) makes isSuppressed true', () {
        final service = createService();
        service.setSuppressDisplay(true);
        expect(service.isSuppressed, isTrue);
      });

      test('setSuppressDisplay(false) after true makes isSuppressed false', () {
        final service = createService();
        service.setSuppressDisplay(true);
        service.setSuppressDisplay(false);
        expect(service.isSuppressed, isFalse);
      });
    });
  });
}
