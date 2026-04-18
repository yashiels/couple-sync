import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'helpers/emulator_setup.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await setupEmulators();
  });

  tearDown(() async {
    await clearEmulatorData();
  });

  group('Onboarding Flow', () {
    testWidgets('setting timezone updates user profile', (tester) async {
      // Create user
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: 'onboard@example.com',
        password: 'password123',
      );
      final uid = credential.user!.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'email': 'onboard@example.com',
        'displayName': 'Onboard User',
        'timezone': '',
        'coupleId': null,
        'fcmTokens': <String>[],
        'photoUrl': null,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // Simulate timezone selection
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'timezone': 'Africa/Johannesburg',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // Verify
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      expect(doc.data()!['timezone'], 'Africa/Johannesburg');
    });

    testWidgets('manual blocks saved to pendingBlocks for unpaired user',
        (tester) async {
      // Create unpaired user
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: 'pending@example.com',
        password: 'password123',
      );
      final uid = credential.user!.uid;

      // Save manual blocks to pendingBlocks (since no coupleId)
      final batch = FirebaseFirestore.instance.batch();
      final blocks = [
        {
          'title': 'Work',
          'startUtc': 1700000000000,
          'endUtc': 1700032400000,
          'timezone': 'Africa/Johannesburg',
          'category': 'work',
          'source': 'manual',
        },
        {
          'title': 'Gym',
          'startUtc': 1700040000000,
          'endUtc': 1700043600000,
          'timezone': 'Africa/Johannesburg',
          'category': 'exercise',
          'source': 'manual',
        },
      ];

      for (final block in blocks) {
        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('pendingBlocks')
            .doc();
        batch.set(ref, block);
      }
      await batch.commit();

      // Verify pendingBlocks exist
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('pendingBlocks')
          .get();
      expect(snapshot.docs.length, 2);
      expect(
          snapshot.docs.any((d) => d.data()['title'] == 'Work'), true);
      expect(
          snapshot.docs.any((d) => d.data()['title'] == 'Gym'), true);
    });
  });
}
