import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firestore_service.dart';

/// Provider for the FirestoreService.
/// Use this to access Firestore operations throughout the app.
///
/// Example:
/// ```dart
/// final firestoreService = ref.watch(firestoreServiceProvider);
/// final user = await firestoreService.getUser(uid);
/// ```
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});
