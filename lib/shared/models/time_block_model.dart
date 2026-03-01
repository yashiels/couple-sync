import 'package:cloud_firestore/cloud_firestore.dart';

enum BlockType { busy, free }

enum BlockCategory {
  commute,
  exercise,
  meals,
  sleep,
  personal,
  work,
  other,
}

enum CalendarSource { google, apple, outlook, manual }

enum TimeBlockVisibility { bothPartners, onlyMe }

class TimeBlock {
  final String id;
  final String userId;
  final String? coupleId;
  final BlockType type;
  final String title;
  final DateTime startUtc;
  final DateTime endUtc;
  final String timezone;       // IANA id of the block's local timezone
  final String? recurrenceRule; // RFC 5545 RRULE string, null = no recurrence
  final CalendarSource source;
  final TimeBlockVisibility visibility;
  final BlockCategory category;
  final DateTime createdAt;

  const TimeBlock({
    required this.id,
    required this.userId,
    this.coupleId,
    required this.type,
    required this.title,
    required this.startUtc,
    required this.endUtc,
    required this.timezone,
    this.recurrenceRule,
    required this.source,
    required this.visibility,
    required this.category,
    required this.createdAt,
  });

  Duration get duration => endUtc.difference(startUtc);

  factory TimeBlock.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return TimeBlock(
      id: doc.id,
      userId: d['userId'] as String,
      coupleId: d['coupleId'] as String?,
      type: BlockType.values.firstWhere((e) => e.name == d['type'], orElse: () => BlockType.busy),
      title: d['title'] as String,
      startUtc: (d['startUtc'] as Timestamp).toDate().toUtc(),
      endUtc: (d['endUtc'] as Timestamp).toDate().toUtc(),
      timezone: d['timezone'] as String? ?? 'UTC',
      recurrenceRule: d['recurrenceRule'] as String?,
      source: CalendarSource.values.firstWhere((e) => e.name == d['source'], orElse: () => CalendarSource.manual),
      visibility: TimeBlockVisibility.values.firstWhere((e) => e.name == d['visibility'], orElse: () => TimeBlockVisibility.bothPartners),
      category: BlockCategory.values.firstWhere((e) => e.name == d['category'], orElse: () => BlockCategory.other),
      createdAt: (d['createdAt'] as Timestamp).toDate().toUtc(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'coupleId': coupleId,
        'type': type.name,
        'title': title,
        'startUtc': Timestamp.fromDate(startUtc),
        'endUtc': Timestamp.fromDate(endUtc),
        'timezone': timezone,
        'recurrenceRule': recurrenceRule,
        'source': source.name,
        'visibility': visibility.name,
        'category': category.name,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  TimeBlock copyWith({
    String? title,
    DateTime? startUtc,
    DateTime? endUtc,
    String? timezone,
    String? recurrenceRule,
    BlockType? type,
    CalendarSource? source,
    TimeBlockVisibility? visibility,
    BlockCategory? category,
  }) {
    return TimeBlock(
      id: id,
      userId: userId,
      coupleId: coupleId,
      type: type ?? this.type,
      title: title ?? this.title,
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      timezone: timezone ?? this.timezone,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      source: source ?? this.source,
      visibility: visibility ?? this.visibility,
      category: category ?? this.category,
      createdAt: createdAt,
    );
  }
}
