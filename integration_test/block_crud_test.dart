import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'helpers/emulator_setup.dart';
import 'helpers/test_users.dart';
import 'helpers/firestore_seeder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupEmulators();
  });

  tearDown(() async {
    await clearEmulatorData();
  });

  group('Block CRUD', () {
    late String coupleId;
    late String userAUid;

    setUp(() async {
      final userA = await createTestUser(
        email: 'blocka@example.com',
        password: 'password123',
        displayName: 'Block User A',
        timezone: 'Africa/Johannesburg',
      );
      final userB = await createTestUser(
        email: 'blockb@example.com',
        password: 'password123',
        displayName: 'Block User B',
        timezone: 'Europe/London',
      );
      coupleId =
          await createTestCouple(userAUid: userA.uid, userBUid: userB.uid);
      userAUid = userA.uid;
    });

    testWidgets('create block appears in Firestore', (tester) async {
      final ref = FirebaseFirestore.instance
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .doc();

      await ref.set({
        'userId': userAUid,
        'title': 'Work',
        'startUtc': 1700000000000,
        'endUtc': 1700032400000,
        'timezone': 'Africa/Johannesburg',
        'category': 'work',
        'source': 'manual',
        'visibility': 'bothPartners',
      });

      final doc = await ref.get();
      expect(doc.exists, true);
      expect(doc.data()!['title'], 'Work');
      expect(doc.data()!['userId'], userAUid);
    });

    testWidgets('update block modifies Firestore document', (tester) async {
      // Create
      final ref = FirebaseFirestore.instance
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .doc();
      await ref.set({
        'userId': userAUid,
        'title': 'Gym',
        'startUtc': 1700040000000,
        'endUtc': 1700043600000,
        'timezone': 'Africa/Johannesburg',
        'category': 'exercise',
        'source': 'manual',
        'visibility': 'bothPartners',
      });

      // Update
      await ref.update({'title': 'Yoga', 'category': 'wellness'});

      final doc = await ref.get();
      expect(doc.data()!['title'], 'Yoga');
      expect(doc.data()!['category'], 'wellness');
    });

    testWidgets('delete block removes from Firestore', (tester) async {
      final ref = FirebaseFirestore.instance
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .doc();
      await ref.set({
        'userId': userAUid,
        'title': 'Temp Block',
        'startUtc': 1700050000000,
        'endUtc': 1700053600000,
        'timezone': 'Africa/Johannesburg',
        'category': 'other',
        'source': 'manual',
        'visibility': 'bothPartners',
      });

      // Verify exists
      expect((await ref.get()).exists, true);

      // Delete
      await ref.delete();

      // Verify gone
      expect((await ref.get()).exists, false);
    });

    testWidgets('query blocks by userId returns correct subset',
        (tester) async {
      // Seed blocks for both users
      await seedBlocks(coupleId: coupleId, userId: userAUid, blocks: [
        {
          'title': 'My Block',
          'startUtc': 1700000000000,
          'endUtc': 1700003600000,
          'timezone': 'Africa/Johannesburg',
          'category': 'work',
          'source': 'manual',
        },
      ]);
      await seedBlocks(coupleId: coupleId, userId: 'partner-uid', blocks: [
        {
          'title': 'Partner Block',
          'startUtc': 1700010000000,
          'endUtc': 1700013600000,
          'timezone': 'Europe/London',
          'category': 'work',
          'source': 'manual',
        },
      ]);

      // Query only my blocks
      final myBlocks = await FirebaseFirestore.instance
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .where('userId', isEqualTo: userAUid)
          .get();

      expect(myBlocks.docs.length, 1);
      expect(myBlocks.docs.first.data()['title'], 'My Block');
    });
  });
}
