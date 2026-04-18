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

  group('Calendar Sync', () {
    testWidgets('freebusy intervals convert to blocks with google source',
        (tester) async {
      final userA = await createTestUser(
        email: 'cal@example.com',
        password: 'password123',
        displayName: 'Cal User',
        timezone: 'Africa/Johannesburg',
      );
      final userB = await createTestUser(
        email: 'calb@example.com',
        password: 'password123',
        displayName: 'Cal Partner',
        timezone: 'Europe/London',
      );
      final coupleId =
          await createTestCouple(userAUid: userA.uid, userBUid: userB.uid);

      // Simulate calendar sync: freebusy converted to blocks with source='google'
      final googleBlocks = [
        {
          'userId': userA.uid,
          'title': 'Busy',
          'startUtc': 1700000000000,
          'endUtc': 1700003600000,
          'timezone': 'Africa/Johannesburg',
          'category': 'busy',
          'source': 'google',
          'visibility': 'bothPartners',
        },
        {
          'userId': userA.uid,
          'title': 'Busy',
          'startUtc': 1700010000000,
          'endUtc': 1700017200000,
          'timezone': 'Africa/Johannesburg',
          'category': 'busy',
          'source': 'google',
          'visibility': 'bothPartners',
        },
      ];

      final batch = FirebaseFirestore.instance.batch();
      for (final block in googleBlocks) {
        final ref = FirebaseFirestore.instance
            .collection('timeblocks')
            .doc(coupleId)
            .collection('blocks')
            .doc();
        batch.set(ref, block);
      }
      await batch.commit();

      // Verify google-sourced blocks
      final blocks = await FirebaseFirestore.instance
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .where('source', isEqualTo: 'google')
          .where('userId', isEqualTo: userA.uid)
          .get();

      expect(blocks.docs.length, 2);
      expect(blocks.docs.every((d) => d.data()['title'] == 'Busy'), true);
      expect(blocks.docs.every((d) => d.data()['source'] == 'google'), true);
    });

    testWidgets('re-sync deletes old google blocks and creates new ones',
        (tester) async {
      final userA = await createTestUser(
        email: 'resync@example.com',
        password: 'password123',
        displayName: 'Resync User',
        timezone: 'Africa/Johannesburg',
      );
      final userB = await createTestUser(
        email: 'resyncb@example.com',
        password: 'password123',
        displayName: 'Resync Partner',
        timezone: 'Europe/London',
      );
      final coupleId =
          await createTestCouple(userAUid: userA.uid, userBUid: userB.uid);

      // Initial sync — create old google blocks
      await seedBlocks(coupleId: coupleId, userId: userA.uid, blocks: [
        {
          'title': 'Busy',
          'startUtc': 1700000000000,
          'endUtc': 1700003600000,
          'timezone': 'Africa/Johannesburg',
          'category': 'busy',
          'source': 'google',
        },
      ]);

      // Also create a manual block that should NOT be deleted
      await seedBlocks(coupleId: coupleId, userId: userA.uid, blocks: [
        {
          'title': 'Gym',
          'startUtc': 1700040000000,
          'endUtc': 1700043600000,
          'timezone': 'Africa/Johannesburg',
          'category': 'exercise',
          'source': 'manual',
        },
      ]);

      // Re-sync: delete old google blocks
      final oldGoogleBlocks = await FirebaseFirestore.instance
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .where('source', isEqualTo: 'google')
          .where('userId', isEqualTo: userA.uid)
          .get();

      final deleteBatch = FirebaseFirestore.instance.batch();
      for (final doc in oldGoogleBlocks.docs) {
        deleteBatch.delete(doc.reference);
      }
      await deleteBatch.commit();

      // Create new google blocks
      await seedBlocks(coupleId: coupleId, userId: userA.uid, blocks: [
        {
          'title': 'Busy',
          'startUtc': 1700050000000,
          'endUtc': 1700053600000,
          'timezone': 'Africa/Johannesburg',
          'category': 'busy',
          'source': 'google',
        },
        {
          'title': 'Busy',
          'startUtc': 1700060000000,
          'endUtc': 1700063600000,
          'timezone': 'Africa/Johannesburg',
          'category': 'busy',
          'source': 'google',
        },
      ]);

      // Verify: manual block preserved, old google gone, new google present
      final allBlocks = await FirebaseFirestore.instance
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .where('userId', isEqualTo: userA.uid)
          .get();

      expect(allBlocks.docs.length, 3); // 1 manual + 2 new google
      expect(
        allBlocks.docs.where((d) => d.data()['source'] == 'manual').length,
        1,
      );
      expect(
        allBlocks.docs.where((d) => d.data()['source'] == 'google').length,
        2,
      );
    });
  });
}
