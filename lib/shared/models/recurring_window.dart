import 'package:cloud_firestore/cloud_firestore.dart';

class RecurringWindow {
  final String id;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final String consistency;
  final int weeksDetected;
  final String? suggestedActivity;
  final bool confirmed;
  final String? meetLink;

  const RecurringWindow({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.consistency,
    required this.weeksDetected,
    this.suggestedActivity,
    required this.confirmed,
    this.meetLink,
  });

  factory RecurringWindow.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return RecurringWindow(
      id: doc.id,
      dayOfWeek: d['dayOfWeek'] as String,
      startTime: d['startTime'] as String,
      endTime: d['endTime'] as String,
      consistency: d['consistency'] as String? ?? 'moderate',
      weeksDetected: d['weeksDetected'] as int? ?? 0,
      suggestedActivity: d['suggestedActivity'] as String?,
      confirmed: d['confirmed'] as bool? ?? false,
      meetLink: d['meetLink'] as String?,
    );
  }
}
