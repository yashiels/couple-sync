import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a request to schedule a Google Meet event for a couple.
///
/// Tracks the lifecycle from initial request through calendar event creation.
class SchedulingRequest {
  final String id;
  final String coupleId;
  final String requestedByUid;
  final DateTime windowStartUtc;
  final DateTime windowEndUtc;
  final String title;

  /// One of: `pending`, `created`, `failed`.
  final String status;

  final String? meetLink;
  final String? calendarEventId;
  final DateTime createdAt;

  const SchedulingRequest({
    required this.id,
    required this.coupleId,
    required this.requestedByUid,
    required this.windowStartUtc,
    required this.windowEndUtc,
    required this.title,
    required this.status,
    this.meetLink,
    this.calendarEventId,
    required this.createdAt,
  });

  factory SchedulingRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SchedulingRequest(
      id: doc.id,
      coupleId: d['coupleId'] as String,
      requestedByUid: d['requestedByUid'] as String,
      windowStartUtc: (d['windowStartUtc'] as Timestamp).toDate().toUtc(),
      windowEndUtc: (d['windowEndUtc'] as Timestamp).toDate().toUtc(),
      title: d['title'] as String,
      status: d['status'] as String? ?? 'pending',
      meetLink: d['meetLink'] as String?,
      calendarEventId: d['calendarEventId'] as String?,
      createdAt: (d['createdAt'] as Timestamp).toDate().toUtc(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'coupleId': coupleId,
        'requestedByUid': requestedByUid,
        'windowStartUtc': Timestamp.fromDate(windowStartUtc),
        'windowEndUtc': Timestamp.fromDate(windowEndUtc),
        'title': title,
        'status': status,
        'meetLink': meetLink,
        'calendarEventId': calendarEventId,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
