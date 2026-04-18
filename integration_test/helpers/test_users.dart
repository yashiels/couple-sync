import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Create a test user in Auth emulator and Firestore.
Future<User> createTestUser({
  required String email,
  required String password,
  required String displayName,
  required String timezone,
}) async {
  final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
    email: email,
    password: password,
  );
  final user = credential.user!;

  await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
    'email': email,
    'displayName': displayName,
    'timezone': timezone,
    'coupleId': null,
    'fcmTokens': <String>[],
    'photoUrl': null,
    'createdAt': DateTime.now().millisecondsSinceEpoch,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  });

  return user;
}

/// Create a couple linking two users.
Future<String> createTestCouple({
  required String userAUid,
  required String userBUid,
}) async {
  final coupleRef = await FirebaseFirestore.instance.collection('couples').add({
    'userAUid': userAUid,
    'userBUid': userBUid,
    'createdAt': DateTime.now().millisecondsSinceEpoch,
  });

  // Link both users to the couple
  final batch = FirebaseFirestore.instance.batch();
  batch.update(
    FirebaseFirestore.instance.collection('users').doc(userAUid),
    {'coupleId': coupleRef.id},
  );
  batch.update(
    FirebaseFirestore.instance.collection('users').doc(userBUid),
    {'coupleId': coupleRef.id},
  );
  await batch.commit();

  return coupleRef.id;
}
