import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_sync/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([
  FirebaseMessaging,
  FirebaseFirestore,
  LocalNotificationDisplay,
  NotificationSettings,
], customMocks: [
  MockSpec<CollectionReference<Map<String, dynamic>>>(
    as: #MockCollectionReferenceMap,
  ),
  MockSpec<DocumentReference<Map<String, dynamic>>>(
    as: #MockDocumentReferenceMap,
  ),
])
import 'notification_service_test.mocks.dart';

void main() {
  late MockFirebaseMessaging mockMessaging;
  late MockFirebaseFirestore mockFirestore;
  late MockLocalNotificationDisplay mockDisplay;
  late MockCollectionReferenceMap mockUsersCollection;
  late MockDocumentReferenceMap mockUserDoc;
  late MockNotificationSettings mockSettings;

  setUp(() {
    mockMessaging = MockFirebaseMessaging();
    mockFirestore = MockFirebaseFirestore();
    mockDisplay = MockLocalNotificationDisplay();
    mockUsersCollection = MockCollectionReferenceMap();
    mockUserDoc = MockDocumentReferenceMap();
    mockSettings = MockNotificationSettings();

    when(mockFirestore.collection('users')).thenReturn(mockUsersCollection);
    when(mockUsersCollection.doc(any)).thenReturn(mockUserDoc);
    when(mockUserDoc.update(any)).thenAnswer((_) async {});
  });

  NotificationService createService({Stream<RemoteMessage>? messageStream}) {
    return NotificationService(
      messaging: mockMessaging,
      firestore: mockFirestore,
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

        verify(mockUserDoc.update(any)).called(1);
        final captured =
            verify(mockUsersCollection.doc(captureAny)).captured;
        expect(captured.last, 'user-123');
      });

      test('skips token storage when FCM token is null', () async {
        when(mockMessaging.getToken()).thenAnswer((_) async => null);
        final service = createService();

        await service.initialize('user-123');

        verifyNever(mockUserDoc.update(any));
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
      test('calls Firestore update on user doc with fcmTokens key', () async {
        final service = createService();

        await service.storeToken('user-456', 'my-token');

        verify(mockFirestore.collection('users')).called(1);
        verify(mockUsersCollection.doc('user-456')).called(1);
        final captured = verify(mockUserDoc.update(captureAny)).captured;
        expect(captured.length, 1);
        final data = captured.first as Map;
        expect(data.containsKey('fcmTokens'), isTrue);
      });

      test('uses FieldValue.arrayUnion (update, not set)', () async {
        final service = createService();

        await service.storeToken('user-456', 'my-token');

        // Verify update() was called, not set()
        verify(mockUserDoc.update(any)).called(1);
        verifyNever(mockUserDoc.set(any));
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
