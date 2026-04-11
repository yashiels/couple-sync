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

  group('Overlap Display', () {
    testWidgets('blocks for both users can be queried', (tester) async {
      final userA = await createTestUser(
        email: 'overlapa@example.com',
        password: 'password123',
        displayName: 'Overlap A',
        timezone: 'Africa/Johannesburg',
      );
      final userB = await createTestUser(
        email: 'overlapb@example.com',
        password: 'password123',
        displayName: 'Overlap B',
        timezone: 'Europe/London',
      );
      final coupleId =
          await createTestCouple(userAUid: userA.uid, userBUid: userB.uid);

      // Seed blocks for both users
      await seedBlocks(coupleId: coupleId, userId: userA.uid, blocks: [
        {
          'title': 'Work A',
          'startUtc': 1700028000000,
          'endUtc': 1700060400000,
          'timezone': 'Africa/Johannesburg',
          'category': 'work',
          'source': 'manual',
        },
      ]);
      await seedBlocks(coupleId: coupleId, userId: userB.uid, blocks: [
        {
          'title': 'Work B',
          'startUtc': 1700035200000,
          'endUtc': 1700064000000,
          'timezone': 'Europe/London',
          'category': 'work',
          'source': 'manual',
        },
      ]);

      // Verify both users' blocks exist
      final allBlocks = await FirebaseFirestore.instance
          .collection('timeblocks')
          .doc(coupleId)
          .collection('blocks')
          .get();
      expect(allBlocks.docs.length, 2);
    });

    testWidgets('overlap result document can be written and read',
        (tester) async {
      final userA = await createTestUser(
        email: 'ov2a@example.com',
        password: 'password123',
        displayName: 'OV A',
        timezone: 'Africa/Johannesburg',
      );
      final userB = await createTestUser(
        email: 'ov2b@example.com',
        password: 'password123',
        displayName: 'OV B',
        timezone: 'Europe/London',
      );
      final coupleId =
          await createTestCouple(userAUid: userA.uid, userBUid: userB.uid);

      // Simulate Cloud Function writing overlap result
      await FirebaseFirestore.instance
          .collection('overlaps')
          .doc(coupleId)
          .collection('windows')
          .doc('latest')
          .set({
        'computedAt': DateTime.now().millisecondsSinceEpoch,
        'userAUid': userA.uid,
        'userBUid': userB.uid,
        'windows': [
          {
            'startUtc': 1700060400000,
            'endUtc': 1700064000000,
            'durationMinutes': 60,
            'score': 0.85,
            'blockHashA': 'hash_a',
            'blockHashB': 'hash_b',
            'reasonableBoth': true,
          }
        ],
      });

      // Verify overlap result readable
      final doc = await FirebaseFirestore.instance
          .collection('overlaps')
          .doc(coupleId)
          .collection('windows')
          .doc('latest')
          .get();
      expect(doc.exists, true);
      final windows = doc.data()!['windows'] as List;
      expect(windows.length, 1);
      expect(windows[0]['durationMinutes'], 60);
      expect(windows[0]['score'], 0.85);
    });
  });
}
