import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_sync/core/models/models.dart';
import 'package:couple_sync/services/firestore_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([
  FirebaseFirestore,
  CollectionReference,
  DocumentReference,
  DocumentSnapshot,
  QuerySnapshot,
  QueryDocumentSnapshot,
  Query,
  WriteBatch,
], customMocks: [
  MockSpec<CollectionReference<Map<String, dynamic>>>(
    as: #MockCollectionReferenceMap,
  ),
  MockSpec<DocumentReference<Map<String, dynamic>>>(
    as: #MockDocumentReferenceMap,
  ),
  MockSpec<DocumentSnapshot<Map<String, dynamic>>>(
    as: #MockDocumentSnapshotMap,
  ),
  MockSpec<QuerySnapshot<Map<String, dynamic>>>(
    as: #MockQuerySnapshotMap,
  ),
  MockSpec<QueryDocumentSnapshot<Map<String, dynamic>>>(
    as: #MockQueryDocumentSnapshotMap,
  ),
  MockSpec<Query<Map<String, dynamic>>>(
    as: #MockQueryMap,
  ),
])
import 'firestore_service_test.mocks.dart';

void main() {
  late MockFirebaseFirestore mockFirestore;
  late FirestoreService service;

  late MockCollectionReferenceMap mockCollection;
  late MockDocumentReferenceMap mockDocRef;
  late MockDocumentSnapshotMap mockDocSnapshot;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    service = FirestoreService(firestore: mockFirestore);

    mockCollection = MockCollectionReferenceMap();
    mockDocRef = MockDocumentReferenceMap();
    mockDocSnapshot = MockDocumentSnapshotMap();
  });

  final now = DateTime(2026, 1, 1);
  final timestamp = Timestamp.fromDate(now);

  Map<String, dynamic> userJson() => {
        'email': 'test@example.com',
        'displayName': 'Test User',
        'photoUrl': null,
        'timezone': 'America/New_York',
        'coupleId': null,
        'fcmTokens': <String>[],
        'createdAt': timestamp,
      };

  Map<String, dynamic> coupleJson() => {
        'userAUid': 'uid-a',
        'userBUid': 'uid-b',
        'status': 'active',
        'pairedAt': timestamp,
        'unpairHistory': <dynamic>[],
        'createdAt': timestamp,
      };

  Map<String, dynamic> inviteJson() => {
        'code': 'ABC123',
        'createdByUid': 'uid-a',
        'coupleId': null,
        'expiresAt': timestamp,
        'status': 'pending',
        'deepLinkUrl': null,
      };

  Map<String, dynamic> timeBlockJson() => {
        'userId': 'uid-a',
        'title': 'Work',
        'type': 'busy',
        'category': 'work',
        'startUtc': 1704067200000,
        'endUtc': 1704096800000,
        'timezone': 'America/New_York',
        'recurrenceRule': null,
        'source': 'manual',
        'visibility': 'bothPartners',
        'createdAt': timestamp,
      };

  Map<String, dynamic> overlapJson() => {
        'windows': <dynamic>[
          {
            'startUtc': 1704067200000,
            'endUtc': 1704096800000,
            'durationMinutes': 60,
            'score': 0.9,
            'reasonableBoth': true,
          },
        ],
        'computedAt': timestamp,
        'blockHashA': 'hash-a',
        'blockHashB': 'hash-b',
      };

  void stubCollection(String name) {
    when(mockFirestore.collection(name)).thenReturn(mockCollection);
  }

  void stubDoc(String id) {
    when(mockCollection.doc(id)).thenReturn(mockDocRef);
  }

  void stubDocGet({required bool exists, Map<String, dynamic>? data}) {
    when(mockDocRef.get()).thenAnswer((_) async => mockDocSnapshot);
    when(mockDocSnapshot.exists).thenReturn(exists);
    if (data != null) {
      when(mockDocSnapshot.data()).thenReturn(data);
    }
  }

  // ============================================================
  // USERS
  // ============================================================

  group('getUser', () {
    test('returns UserModel when document exists', () async {
      stubCollection('users');
      stubDoc('uid-1');
      stubDocGet(exists: true, data: userJson());

      final result = await service.getUser('uid-1');

      expect(result, isNotNull);
      expect(result!.email, 'test@example.com');
      expect(result.displayName, 'Test User');
      expect(result.timezone, 'America/New_York');
    });

    test('returns null when document does not exist', () async {
      stubCollection('users');
      stubDoc('uid-1');
      stubDocGet(exists: false);

      final result = await service.getUser('uid-1');

      expect(result, isNull);
    });

    test('throws FirestoreException on FirebaseException', () async {
      stubCollection('users');
      stubDoc('uid-1');
      when(mockDocRef.get()).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );

      expect(
        () => service.getUser('uid-1'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'permission-denied',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      stubCollection('users');
      stubDoc('uid-1');
      when(mockDocRef.get()).thenThrow(Exception('unexpected'));

      expect(
        () => service.getUser('uid-1'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  group('createUser', () {
    test('sets document with data and server timestamp', () async {
      stubCollection('users');
      stubDoc('uid-1');
      when(mockDocRef.set(any)).thenAnswer((_) async {});

      final data = {'email': 'test@example.com', 'displayName': 'Test'};
      await service.createUser('uid-1', data);

      final captured =
          verify(mockDocRef.set(captureAny)).captured.single as Map;
      expect(captured['email'], 'test@example.com');
      expect(captured['displayName'], 'Test');
      expect(captured['createdAt'], isA<FieldValue>());
    });

    test('throws FirestoreException on FirebaseException', () async {
      stubCollection('users');
      stubDoc('uid-1');
      when(mockDocRef.set(any)).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'unavailable'),
      );

      expect(
        () => service.createUser('uid-1', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unavailable',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      stubCollection('users');
      stubDoc('uid-1');
      when(mockDocRef.set(any)).thenThrow(Exception('unexpected'));

      expect(
        () => service.createUser('uid-1', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  group('updateUser', () {
    test('updates document with provided data', () async {
      stubCollection('users');
      stubDoc('uid-1');
      when(mockDocRef.update(any)).thenAnswer((_) async {});

      await service.updateUser('uid-1', {'timezone': 'Europe/London'});

      verify(mockDocRef.update({'timezone': 'Europe/London'})).called(1);
    });

    test('throws FirestoreException on FirebaseException', () async {
      stubCollection('users');
      stubDoc('uid-1');
      when(mockDocRef.update(any)).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'not-found'),
      );

      expect(
        () => service.updateUser('uid-1', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'not-found',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      stubCollection('users');
      stubDoc('uid-1');
      when(mockDocRef.update(any)).thenThrow(Exception('unexpected'));

      expect(
        () => service.updateUser('uid-1', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  // ============================================================
  // COUPLES
  // ============================================================

  group('getCouple', () {
    test('returns CoupleModel when document exists', () async {
      stubCollection('couples');
      stubDoc('couple-1');
      stubDocGet(exists: true, data: coupleJson());

      final result = await service.getCouple('couple-1');

      expect(result, isNotNull);
      expect(result!.userAUid, 'uid-a');
      expect(result.userBUid, 'uid-b');
      expect(result.status, CoupleStatus.active);
    });

    test('returns null when document does not exist', () async {
      stubCollection('couples');
      stubDoc('couple-1');
      stubDocGet(exists: false);

      final result = await service.getCouple('couple-1');

      expect(result, isNull);
    });

    test('throws FirestoreException on FirebaseException', () async {
      stubCollection('couples');
      stubDoc('couple-1');
      when(mockDocRef.get()).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'unauthenticated'),
      );

      expect(
        () => service.getCouple('couple-1'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unauthenticated',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      stubCollection('couples');
      stubDoc('couple-1');
      when(mockDocRef.get()).thenThrow(Exception('unexpected'));

      expect(
        () => service.getCouple('couple-1'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  group('createCouple', () {
    test('adds document and returns generated ID', () async {
      stubCollection('couples');
      when(mockCollection.add(any)).thenAnswer((_) async => mockDocRef);
      when(mockDocRef.id).thenReturn('generated-id');

      final couple = CoupleModel(
        userAUid: 'uid-a',
        userBUid: 'uid-b',
        status: CoupleStatus.active,
        pairedAt: now,
        unpairHistory: [],
        createdAt: now,
      );

      final id = await service.createCouple(couple);

      expect(id, 'generated-id');
      final captured =
          verify(mockCollection.add(captureAny)).captured.single as Map;
      expect(captured['userAUid'], 'uid-a');
      expect(captured['createdAt'], isA<FieldValue>());
    });

    test('throws FirestoreException on FirebaseException', () async {
      stubCollection('couples');
      when(mockCollection.add(any)).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'already-exists'),
      );

      final couple = CoupleModel(
        userAUid: 'uid-a',
        userBUid: 'uid-b',
        status: CoupleStatus.active,
        pairedAt: now,
        unpairHistory: [],
        createdAt: now,
      );

      expect(
        () => service.createCouple(couple),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'already-exists',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      stubCollection('couples');
      when(mockCollection.add(any)).thenThrow(Exception('unexpected'));

      final couple = CoupleModel(
        userAUid: 'uid-a',
        userBUid: 'uid-b',
        status: CoupleStatus.active,
        pairedAt: now,
        unpairHistory: [],
        createdAt: now,
      );

      expect(
        () => service.createCouple(couple),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  // ============================================================
  // INVITES
  // ============================================================

  group('createInvite', () {
    test('sets document with data and server timestamp', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      when(mockDocRef.set(any)).thenAnswer((_) async {});

      final data = {'createdByUid': 'uid-a', 'status': 'pending'};
      await service.createInvite('ABC123', data);

      final captured =
          verify(mockDocRef.set(captureAny)).captured.single as Map;
      expect(captured['createdByUid'], 'uid-a');
      expect(captured['createdAt'], isA<FieldValue>());
    });

    test('throws FirestoreException on FirebaseException', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      when(mockDocRef.set(any)).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'resource-exhausted'),
      );

      expect(
        () => service.createInvite('ABC123', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'resource-exhausted',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      when(mockDocRef.set(any)).thenThrow(Exception('unexpected'));

      expect(
        () => service.createInvite('ABC123', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  group('getInvite', () {
    test('returns InviteModel when document exists', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      stubDocGet(exists: true, data: inviteJson());

      final result = await service.getInvite('ABC123');

      expect(result, isNotNull);
      expect(result!.code, 'ABC123');
      expect(result.createdByUid, 'uid-a');
      expect(result.status, InviteStatus.pending);
    });

    test('returns null when document does not exist', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      stubDocGet(exists: false);

      final result = await service.getInvite('ABC123');

      expect(result, isNull);
    });

    test('throws FirestoreException on FirebaseException', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      when(mockDocRef.get()).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'deadline-exceeded'),
      );

      expect(
        () => service.getInvite('ABC123'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'deadline-exceeded',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      when(mockDocRef.get()).thenThrow(Exception('unexpected'));

      expect(
        () => service.getInvite('ABC123'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  group('updateInvite', () {
    test('updates document with provided data', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      when(mockDocRef.update(any)).thenAnswer((_) async {});

      await service.updateInvite('ABC123', {'status': 'accepted'});

      verify(mockDocRef.update({'status': 'accepted'})).called(1);
    });

    test('throws FirestoreException on FirebaseException', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      when(mockDocRef.update(any)).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'cancelled'),
      );

      expect(
        () => service.updateInvite('ABC123', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'cancelled',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      stubCollection('invites');
      stubDoc('ABC123');
      when(mockDocRef.update(any)).thenThrow(Exception('unexpected'));

      expect(
        () => service.updateInvite('ABC123', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  // ============================================================
  // TIME BLOCKS
  // ============================================================

  group('getBlocks', () {
    test('returns list of TimeBlock for a user', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockQuery = MockQueryMap();
      final mockQuerySnapshot = MockQuerySnapshotMap();
      final mockQueryDoc = MockQueryDocumentSnapshotMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.where('userId', isEqualTo: 'uid-a'))
          .thenReturn(mockQuery);
      when(mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);
      when(mockQuerySnapshot.docs).thenReturn([mockQueryDoc]);
      when(mockQueryDoc.data()).thenReturn(timeBlockJson());
      when(mockQueryDoc.id).thenReturn('block-doc-id');

      final result = await service.getBlocks('couple-1', 'uid-a');

      expect(result, hasLength(1));
      expect(result.first.id, 'block-doc-id');
      expect(result.first.userId, 'uid-a');
      expect(result.first.title, 'Work');
      expect(result.first.type, TimeBlockType.busy);
    });

    test('returns empty list when no blocks exist', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockQuery = MockQueryMap();
      final mockQuerySnapshot = MockQuerySnapshotMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.where('userId', isEqualTo: 'uid-a'))
          .thenReturn(mockQuery);
      when(mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);
      when(mockQuerySnapshot.docs).thenReturn([]);

      final result = await service.getBlocks('couple-1', 'uid-a');

      expect(result, isEmpty);
    });

    test('throws FirestoreException on FirebaseException', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockQuery = MockQueryMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.where('userId', isEqualTo: 'uid-a'))
          .thenReturn(mockQuery);
      when(mockQuery.get()).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );

      expect(
        () => service.getBlocks('couple-1', 'uid-a'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'permission-denied',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockQuery = MockQueryMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.where('userId', isEqualTo: 'uid-a'))
          .thenReturn(mockQuery);
      when(mockQuery.get()).thenThrow(Exception('unexpected'));

      expect(
        () => service.getBlocks('couple-1', 'uid-a'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  group('watchBlocks', () {
    test('emits list of TimeBlock with correct doc ID for a user', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockQuery = MockQueryMap();
      final mockQuerySnapshot = MockQuerySnapshotMap();
      final mockQueryDoc = MockQueryDocumentSnapshotMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.where('userId', isEqualTo: 'uid-a'))
          .thenReturn(mockQuery);
      when(mockQuery.snapshots())
          .thenAnswer((_) => Stream.value(mockQuerySnapshot));
      when(mockQuerySnapshot.docs).thenReturn([mockQueryDoc]);
      when(mockQueryDoc.data()).thenReturn(timeBlockJson());
      when(mockQueryDoc.id).thenReturn('block-doc-id');

      final result = await service
          .watchBlocks('couple-1', userId: 'uid-a')
          .first;

      expect(result, hasLength(1));
      expect(result.first.id, 'block-doc-id');
      expect(result.first.userId, 'uid-a');
      expect(result.first.title, 'Work');
      expect(result.first.type, TimeBlockType.busy);
    });

    test('emits empty list when no blocks exist', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockQuery = MockQueryMap();
      final mockQuerySnapshot = MockQuerySnapshotMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.where('userId', isEqualTo: 'uid-a'))
          .thenReturn(mockQuery);
      when(mockQuery.snapshots())
          .thenAnswer((_) => Stream.value(mockQuerySnapshot));
      when(mockQuerySnapshot.docs).thenReturn([]);

      final result = await service
          .watchBlocks('couple-1', userId: 'uid-a')
          .first;

      expect(result, isEmpty);
    });
  });

  group('createBlock', () {
    test('adds block and returns generated ID', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockNewDocRef = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.add(any)).thenAnswer((_) async => mockNewDocRef);
      when(mockNewDocRef.id).thenReturn('block-id');

      final block = TimeBlock(
        userId: 'uid-a',
        title: 'Work',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.work,
        startUtc: 1704067200000,
        endUtc: 1704096800000,
        timezone: 'America/New_York',
        source: TimeBlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      );

      final id = await service.createBlock('couple-1', block);

      expect(id, 'block-id');
      final captured =
          verify(mockSubCollection.add(captureAny)).captured.single as Map;
      expect(captured['userId'], 'uid-a');
      expect(captured['createdAt'], isA<FieldValue>());
    });

    test('throws FirestoreException on FirebaseException', () async {
      final mockSubCollection = MockCollectionReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.add(any)).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'unavailable'),
      );

      final block = TimeBlock(
        userId: 'uid-a',
        title: 'Work',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.work,
        startUtc: 1704067200000,
        endUtc: 1704096800000,
        timezone: 'America/New_York',
        source: TimeBlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      );

      expect(
        () => service.createBlock('couple-1', block),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unavailable',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      final mockSubCollection = MockCollectionReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.add(any)).thenThrow(Exception('unexpected'));

      final block = TimeBlock(
        userId: 'uid-a',
        title: 'Work',
        type: TimeBlockType.busy,
        category: TimeBlockCategory.work,
        startUtc: 1704067200000,
        endUtc: 1704096800000,
        timezone: 'America/New_York',
        source: TimeBlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        createdAt: now,
      );

      expect(
        () => service.createBlock('couple-1', block),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  group('updateBlock', () {
    test('updates block document with provided data', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockBlockDoc = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('block-1')).thenReturn(mockBlockDoc);
      when(mockBlockDoc.update(any)).thenAnswer((_) async {});

      await service.updateBlock('couple-1', 'block-1', {'title': 'Updated'});

      verify(mockBlockDoc.update({'title': 'Updated'})).called(1);
    });

    test('throws FirestoreException on FirebaseException', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockBlockDoc = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('block-1')).thenReturn(mockBlockDoc);
      when(mockBlockDoc.update(any)).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'not-found'),
      );

      expect(
        () => service.updateBlock('couple-1', 'block-1', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'not-found',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockBlockDoc = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('block-1')).thenReturn(mockBlockDoc);
      when(mockBlockDoc.update(any)).thenThrow(Exception('unexpected'));

      expect(
        () => service.updateBlock('couple-1', 'block-1', {}),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  group('deleteBlock', () {
    test('deletes block document', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockBlockDoc = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('block-1')).thenReturn(mockBlockDoc);
      when(mockBlockDoc.delete()).thenAnswer((_) async {});

      await service.deleteBlock('couple-1', 'block-1');

      verify(mockBlockDoc.delete()).called(1);
    });

    test('throws FirestoreException on FirebaseException', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockBlockDoc = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('block-1')).thenReturn(mockBlockDoc);
      when(mockBlockDoc.delete()).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );

      expect(
        () => service.deleteBlock('couple-1', 'block-1'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'permission-denied',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockBlockDoc = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      when(mockDocRef.collection('blocks')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('block-1')).thenReturn(mockBlockDoc);
      when(mockBlockDoc.delete()).thenThrow(Exception('unexpected'));

      expect(
        () => service.deleteBlock('couple-1', 'block-1'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  // ============================================================
  // ATOMIC REPLACE GOOGLE-SOURCED BLOCKS
  // ============================================================

  group('atomicReplaceGoogleSourcedBlocks', () {
    TimeBlock makeGoogleBlock() => TimeBlock(
          userId: 'uid-a',
          title: 'Busy',
          type: TimeBlockType.busy,
          category: TimeBlockCategory.work,
          startUtc: 1704067200000,
          endUtc: 1704096800000,
          timezone: 'America/New_York',
          source: TimeBlockSource.google,
          visibility: TimeBlockVisibility.bothPartners,
          createdAt: now,
        );

    /// Wires up the sub-collection query chain for the google-sourced fetch.
    void stubFetch({
      required MockCollectionReferenceMap subCollection,
      required List<MockQueryDocumentSnapshotMap> existingDocs,
    }) {
      final userQuery = MockQueryMap();
      final googleQuery = MockQueryMap();
      final querySnapshot = MockQuerySnapshotMap();

      when(mockDocRef.collection('blocks')).thenReturn(subCollection);
      when(subCollection.where('userId', isEqualTo: 'uid-a'))
          .thenReturn(userQuery);
      when(userQuery.where('source', isEqualTo: 'google'))
          .thenReturn(googleQuery);
      when(googleQuery.get()).thenAnswer((_) async => querySnapshot);
      when(querySnapshot.docs).thenReturn(existingDocs);
    }

    test('normal replace: deletes existing google blocks and creates new ones',
        () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockBatch = MockWriteBatch();
      final existingDoc = MockQueryDocumentSnapshotMap();
      final existingRef = MockDocumentReferenceMap();
      final newDocRef = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      stubFetch(
        subCollection: mockSubCollection,
        existingDocs: [existingDoc],
      );
      when(existingDoc.reference).thenReturn(existingRef);

      when(mockFirestore.batch()).thenReturn(mockBatch);
      when(mockBatch.delete(any)).thenReturn(null);
      when(mockBatch.set(any, any)).thenReturn(null);
      when(mockBatch.commit()).thenAnswer((_) async {});

      // Stub collection.doc() used to allocate IDs for new blocks.
      when(mockSubCollection.doc()).thenReturn(newDocRef);

      final newBlock = makeGoogleBlock();
      final result = await service.atomicReplaceGoogleSourcedBlocks(
        'couple-1',
        'uid-a',
        [newBlock],
      );

      expect(result.deletedCount, 1);
      expect(result.createdCount, 1);
      verify(mockBatch.delete(existingRef)).called(1);
      verify(mockBatch.set(newDocRef, any)).called(1);
      verify(mockBatch.commit()).called(1);
    });

    test('first sync (zero existing blocks): creates new blocks without error',
        () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockBatch = MockWriteBatch();
      final newDocRef = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      stubFetch(
        subCollection: mockSubCollection,
        existingDocs: [], // no pre-existing google blocks
      );

      when(mockFirestore.batch()).thenReturn(mockBatch);
      when(mockBatch.set(any, any)).thenReturn(null);
      when(mockBatch.commit()).thenAnswer((_) async {});
      when(mockSubCollection.doc()).thenReturn(newDocRef);

      final newBlock = makeGoogleBlock();
      final result = await service.atomicReplaceGoogleSourcedBlocks(
        'couple-1',
        'uid-a',
        [newBlock],
      );

      expect(result.deletedCount, 0);
      expect(result.createdCount, 1);
      verifyNever(mockBatch.delete(any));
      verify(mockBatch.set(newDocRef, any)).called(1);
      verify(mockBatch.commit()).called(1);
    });

    test('empty new blocks: deletes existing blocks and creates nothing',
        () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockBatch = MockWriteBatch();
      final existingDoc = MockQueryDocumentSnapshotMap();
      final existingRef = MockDocumentReferenceMap();

      stubCollection('timeblocks');
      stubDoc('couple-1');
      stubFetch(
        subCollection: mockSubCollection,
        existingDocs: [existingDoc],
      );
      when(existingDoc.reference).thenReturn(existingRef);

      when(mockFirestore.batch()).thenReturn(mockBatch);
      when(mockBatch.delete(any)).thenReturn(null);
      when(mockBatch.commit()).thenAnswer((_) async {});

      final result = await service.atomicReplaceGoogleSourcedBlocks(
        'couple-1',
        'uid-a',
        [], // no new blocks — calendar cleared
      );

      expect(result.deletedCount, 1);
      expect(result.createdCount, 0);
      verify(mockBatch.delete(existingRef)).called(1);
      verifyNever(mockBatch.set(any, any));
      verify(mockBatch.commit()).called(1);
    });
  });

  // ============================================================
  // OVERLAP
  // ============================================================

  group('getOverlap', () {
    test('returns OverlapResult when document exists', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockWindowsDoc = MockDocumentReferenceMap();
      final mockWindowsSnapshot = MockDocumentSnapshotMap();

      stubCollection('overlaps');
      stubDoc('couple-1');
      when(mockDocRef.collection('windows')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('latest')).thenReturn(mockWindowsDoc);
      when(mockWindowsDoc.get()).thenAnswer((_) async => mockWindowsSnapshot);
      when(mockWindowsSnapshot.exists).thenReturn(true);
      when(mockWindowsSnapshot.data()).thenReturn(overlapJson());

      final result = await service.getOverlap('couple-1');

      expect(result, isNotNull);
      expect(result!.windows, hasLength(1));
      expect(result.blockHashA, 'hash-a');
      expect(result.blockHashB, 'hash-b');
    });

    test('returns null when document does not exist', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockWindowsDoc = MockDocumentReferenceMap();
      final mockWindowsSnapshot = MockDocumentSnapshotMap();

      stubCollection('overlaps');
      stubDoc('couple-1');
      when(mockDocRef.collection('windows')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('latest')).thenReturn(mockWindowsDoc);
      when(mockWindowsDoc.get()).thenAnswer((_) async => mockWindowsSnapshot);
      when(mockWindowsSnapshot.exists).thenReturn(false);

      final result = await service.getOverlap('couple-1');

      expect(result, isNull);
    });

    test('throws FirestoreException on FirebaseException', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockWindowsDoc = MockDocumentReferenceMap();

      stubCollection('overlaps');
      stubDoc('couple-1');
      when(mockDocRef.collection('windows')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('latest')).thenReturn(mockWindowsDoc);
      when(mockWindowsDoc.get()).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'unavailable'),
      );

      expect(
        () => service.getOverlap('couple-1'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unavailable',
        )),
      );
    });

    test('throws FirestoreException on unknown error', () async {
      final mockSubCollection = MockCollectionReferenceMap();
      final mockWindowsDoc = MockDocumentReferenceMap();

      stubCollection('overlaps');
      stubDoc('couple-1');
      when(mockDocRef.collection('windows')).thenReturn(mockSubCollection);
      when(mockSubCollection.doc('latest')).thenReturn(mockWindowsDoc);
      when(mockWindowsDoc.get()).thenThrow(Exception('unexpected'));

      expect(
        () => service.getOverlap('couple-1'),
        throwsA(isA<FirestoreException>().having(
          (e) => e.code,
          'code',
          'unknown',
        )),
      );
    });
  });

  // ============================================================
  // ERROR MAPPING
  // ============================================================

  group('_mapFirebaseException', () {
    test('maps all known error codes to user-friendly messages', () async {
      final errorCodes = {
        'permission-denied': 'You do not have permission',
        'not-found': 'The requested document was not found',
        'already-exists': 'The document already exists',
        'unavailable': 'Service temporarily unavailable',
        'deadline-exceeded': 'Operation timed out',
        'resource-exhausted': 'Too many requests',
        'cancelled': 'Operation was cancelled',
        'unauthenticated': 'Authentication required',
      };

      for (final entry in errorCodes.entries) {
        stubCollection('users');
        stubDoc('uid-1');
        when(mockDocRef.get()).thenThrow(
          FirebaseException(plugin: 'firestore', code: entry.key),
        );

        try {
          await service.getUser('uid-1');
          fail('Should have thrown');
        } on FirestoreException catch (e) {
          expect(e.code, entry.key);
          expect(e.message, contains(entry.value));
        }
      }
    });

    test('maps unknown error code to generic message', () async {
      stubCollection('users');
      stubDoc('uid-1');
      when(mockDocRef.get()).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'internal'),
      );

      try {
        await service.getUser('uid-1');
        fail('Should have thrown');
      } on FirestoreException catch (e) {
        expect(e.code, 'internal');
        expect(e.message, contains('Failed to get user'));
      }
    });
  });

  // ============================================================
  // FirestoreException
  // ============================================================

  group('FirestoreException', () {
    test('toString returns formatted string', () {
      const exception = FirestoreException(
        code: 'test-code',
        message: 'test message',
      );

      expect(exception.toString(), 'FirestoreException(test-code): test message');
    });

    test('preserves originalError', () {
      final original = Exception('original');
      final exception = FirestoreException(
        code: 'test',
        message: 'msg',
        originalError: original,
      );

      expect(exception.originalError, original);
    });
  });
}
