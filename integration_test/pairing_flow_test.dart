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

  group('Pairing Flow', () {
    testWidgets('invite creation stores document in Firestore',
        (tester) async {
      final user = await createTestUser(
        email: 'creator@example.com',
        password: 'password123',
        displayName: 'Creator',
        timezone: 'Africa/Johannesburg',
      );

      await seedInvite(code: 'TEST-CODE-123', createdByUid: user.uid);

      final invite = await FirebaseFirestore.instance
          .collection('invites')
          .doc('TEST-CODE-123')
          .get();
      expect(invite.exists, true);
      expect(invite.data()!['createdByUid'], user.uid);
      expect(invite.data()!['status'], 'pending');
    });

    testWidgets('couple creation links both users', (tester) async {
      final userA = await createTestUser(
        email: 'usera@example.com',
        password: 'password123',
        displayName: 'User A',
        timezone: 'Africa/Johannesburg',
      );
      final userB = await createTestUser(
        email: 'userb@example.com',
        password: 'password123',
        displayName: 'User B',
        timezone: 'Europe/London',
      );

      final coupleId =
          await createTestCouple(userAUid: userA.uid, userBUid: userB.uid);

      // Verify couple document
      final couple = await FirebaseFirestore.instance
          .collection('couples')
          .doc(coupleId)
          .get();
      expect(couple.exists, true);
      expect(couple.data()!['userAUid'], userA.uid);
      expect(couple.data()!['userBUid'], userB.uid);

      // Verify both users linked
      final userADoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userA.uid)
          .get();
      final userBDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userB.uid)
          .get();
      expect(userADoc.data()!['coupleId'], coupleId);
      expect(userBDoc.data()!['coupleId'], coupleId);
    });

    testWidgets('invite status updated after redemption', (tester) async {
      final creator = await createTestUser(
        email: 'inv-creator@example.com',
        password: 'password123',
        displayName: 'Invite Creator',
        timezone: 'Africa/Johannesburg',
      );

      await seedInvite(code: 'REDEEM-CODE', createdByUid: creator.uid);

      // Simulate redemption — update invite status
      await FirebaseFirestore.instance
          .collection('invites')
          .doc('REDEEM-CODE')
          .update({
        'status': 'accepted',
        'redeemedByUid': 'some-redeemer-uid',
        'redeemedAt': DateTime.now().millisecondsSinceEpoch,
      });

      final invite = await FirebaseFirestore.instance
          .collection('invites')
          .doc('REDEEM-CODE')
          .get();
      expect(invite.data()!['status'], 'accepted');
    });
  });
}
