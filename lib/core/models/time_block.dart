import 'package:cloud_firestore/cloud_firestore.dart';

/// Time block type enum
enum TimeBlockType { busy, free, tentative }

/// Time block category enum
enum TimeBlockCategory {
  work,
  study,
  commute,
  exercise,
  social,
  meals,
  sleep,
  personal,
  other,
}

/// Time block source enum
enum TimeBlockSource { google, manual }

/// Time block visibility enum
enum TimeBlockVisibility { bothPartners, onlyMe }

/// TimeBlock document model for timeblocks/{coupleId}/blocks/{blockId}
class TimeBlock {
  final String userId;
  final String title;
  final TimeBlockType type;
  final TimeBlockCategory category;
  final int startUtc; // Milliseconds since epoch (UTC)
  final int endUtc; // Milliseconds since epoch (UTC)
  final String timezone;
  final String? recurrenceRule; // RFC 5545 RRULE string
  final TimeBlockSource source;
  final TimeBlockVisibility visibility;
  final DateTime createdAt;

  const TimeBlock({
    required this.userId,
    required this.title,
    required this.type,
    required this.category,
    required this.startUtc,
    required this.endUtc,
    required this.timezone,
    this.recurrenceRule,
    required this.source,
    required this.visibility,
    required this.createdAt,
  });

  factory TimeBlock.fromJson(Map<String, dynamic> json) {
    return TimeBlock(
      userId: json['userId'] as String,
      title: json['title'] as String,
      type: TimeBlockType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TimeBlockType.busy,
      ),
      category: TimeBlockCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => TimeBlockCategory.other,
      ),
      startUtc: json['startUtc'] as int,
      endUtc: json['endUtc'] as int,
      timezone: json['timezone'] as String,
      recurrenceRule: json['recurrenceRule'] as String?,
      source: TimeBlockSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => TimeBlockSource.manual,
      ),
      visibility: TimeBlockVisibility.values.firstWhere(
        (e) => e.name == json['visibility'],
        orElse: () => TimeBlockVisibility.bothPartners,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'title': title,
      'type': type.name,
      'category': category.name,
      'startUtc': startUtc,
      'endUtc': endUtc,
      'timezone': timezone,
      'recurrenceRule': recurrenceRule,
      'source': source.name,
      'visibility': visibility.name,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  TimeBlock copyWith({
    String? userId,
    String? title,
    TimeBlockType? type,
    TimeBlockCategory? category,
    int? startUtc,
    int? endUtc,
    String? timezone,
    String? recurrenceRule,
    TimeBlockSource? source,
    TimeBlockVisibility? visibility,
    DateTime? createdAt,
    bool clearRecurrenceRule = false,
  }) {
    return TimeBlock(
      userId: userId ?? this.userId,
      title: title ?? this.title,
      type: type ?? this.type,
      category: category ?? this.category,
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      timezone: timezone ?? this.timezone,
      recurrenceRule:
          clearRecurrenceRule ? null : (recurrenceRule ?? this.recurrenceRule),
      source: source ?? this.source,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Get the duration in milliseconds
  int get durationMs => endUtc - startUtc;

  /// Get the duration in minutes
  int get durationMinutes => durationMs ~/ 60000;

  /// Get start time as DateTime
  DateTime get startDateTime => DateTime.fromMillisecondsSinceEpoch(startUtc, isUtc: true);

  /// Get end time as DateTime
  DateTime get endDateTime => DateTime.fromMillisecondsSinceEpoch(endUtc, isUtc: true);

  /// Check if this block is recurring
  bool get isRecurring => recurrenceRule != null && recurrenceRule!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeBlock &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          title == other.title &&
          type == other.type &&
          category == other.category &&
          startUtc == other.startUtc &&
          endUtc == other.endUtc &&
          timezone == other.timezone &&
          recurrenceRule == other.recurrenceRule &&
          source == other.source &&
          visibility == other.visibility &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        userId,
        title,
        type,
        category,
        startUtc,
        endUtc,
        timezone,
        recurrenceRule,
        source,
        visibility,
        createdAt,
      );

  @override
  String toString() =>
      'TimeBlock(userId: $userId, title: $title, type: $type, start: $startDateTime, end: $endDateTime)';
}
