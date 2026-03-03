import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recurring_window.dart';

final recurringWindowsProvider = StreamProvider.family<List<RecurringWindow>, String>((ref, coupleId) {
  return FirebaseFirestore.instance
      .collection('couples')
      .doc(coupleId)
      .collection('recurringWindows')
      .snapshots()
      .map((snap) => snap.docs.map(RecurringWindow.fromFirestore).toList());
});

final confirmedPatternsProvider = Provider.family<List<RecurringWindow>, String>((ref, coupleId) {
  return ref.watch(recurringWindowsProvider(coupleId)).valueOrNull
      ?.where((w) => w.confirmed).toList() ?? [];
});

final suggestedPatternsProvider = Provider.family<List<RecurringWindow>, String>((ref, coupleId) {
  return ref.watch(recurringWindowsProvider(coupleId)).valueOrNull
      ?.where((w) => !w.confirmed).toList() ?? [];
});
