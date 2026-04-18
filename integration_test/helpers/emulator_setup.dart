import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Initialize Firebase and connect to emulators.
Future<void> setupEmulators() async {
  await Firebase.initializeApp();

  // Connect to Firestore emulator
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);

  // Connect to Auth emulator
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
}

/// Clear all emulator data between tests.
Future<void> clearEmulatorData() async {
  // Clear Firestore
  // Note: The emulator REST API endpoint for clearing is:
  // DELETE http://localhost:8080/emulator/v1/projects/{projectId}/databases/(default)/documents
  // For integration tests, we can clear specific collections instead
}
