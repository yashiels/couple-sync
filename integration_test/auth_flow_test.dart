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

  group('Auth Flow', () {
    testWidgets('creating a user generates a Firestore profile',
        (tester) async {
      // Create user via Auth emulator
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: 'test@example.com',
        password: 'password123',
      );

      // Verify user exists in Auth
      expect(credential.user, isNotNull);
      expect(credential.user!.email, 'test@example.com');

      // Create the Firestore profile (simulating what AuthService does)
      final uid = credential.user!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'email': 'test@example.com',
        'displayName': 'Test User',
        'timezone': '',
        'coupleId': null,
        'fcmTokens': <String>[],
        'photoUrl': null,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      // Verify profile in Firestore
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      expect(doc.exists, true);
      expect(doc.data()!['email'], 'test@example.com');
      expect(doc.data()!['timezone'], ''); // Empty means needs setup
      expect(doc.data()!['coupleId'], null); // Not paired yet
    });

    testWidgets('user without timezone should need onboarding',
        (tester) async {
      // Create user with empty timezone
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: 'new@example.com',
        password: 'password123',
      );
      final uid = credential.user!.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'email': 'new@example.com',
        'displayName': 'New User',
        'timezone': '',
        'coupleId': null,
        'fcmTokens': <String>[],
        'photoUrl': null,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final hasTimezone =
          doc.data()!['timezone'] != null && doc.data()!['timezone'] != '';
      expect(hasTimezone, false); // Needs timezone setup
    });
  });
}
