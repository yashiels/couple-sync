import 'package:cloud_firestore/cloud_firestore.dart';

enum BlockOwner { me, partner }

enum BlockType { calendarEvent, customBlock, recurring }

enum CalendarSource { google, apple, outlook, manual }

enum TimeBlockVisibility { busy, free, tentative }

class TimeBlock {
  final String id;
  final String? title;
  final DateTime startUtc;
  final DateTime endUtc;
  final BlockOwner owner;
  final BlockType type;
  final String timezone;
  final String? userId;
  final String? coupleId;
  final CalendarSource? source;
  final TimeBlockVisibility? visibility;

  const TimeBlock({
    required this.id,
    this.title,
    required this.startUtc,
    required this.endUtc,
    required this.owner,
    required this.type,
    required this.timezone,
    this.userId,
    this.coupleId,
    this.source,
    this.visibility,
  });

  Duration get duration => endUtc.difference(startUtc);

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'coupleId': coupleId,
      'type': type.name,
      'title': title,
      'startUtc': Timestamp.fromDate(startUtc),
      'endUtc': Timestamp.fromDate(endUtc),
      'timezone': timezone,
      'source': source?.name,
      'visibility': (visibility ?? TimeBlockVisibility.busy).name,
    };
  }

  factory TimeBlock.fromFirestore(Map<String, dynamic> data, String docId) {
    CalendarSource? source;
    if (data['source'] != null) {
      source = CalendarSource.values.firstWhere(
        (e) => e.name == data['source'],
        orElse: () => CalendarSource.manual,
      );
    }

    TimeBlockVisibility? visibility;
    if (data['visibility'] != null) {
      visibility = TimeBlockVisibility.values.firstWhere(
        (e) => e.name == data['visibility'],
        orElse: () => TimeBlockVisibility.busy,
      );
    }

    DateTime parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate().toUtc();
      if (value is String) return DateTime.parse(value).toUtc();
      throw ArgumentError('Cannot parse date from $value');
    }

    return TimeBlock(
      id: docId,
      userId: data['userId'] as String?,
      coupleId: data['coupleId'] as String?,
      type: BlockType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => BlockType.calendarEvent,
      ),
      title: data['title'] as String?,
      startUtc: parseDate(data['startUtc']),
      endUtc: parseDate(data['endUtc']),
      owner: BlockOwner.me,
      timezone: data['timezone'] as String? ?? 'UTC',
      source: source,
      visibility: visibility,
    );
  }
}

class FreeWindow {
  final String id;
  final DateTime startUtc;
  final DateTime endUtc;
  final String timezoneA;
  final String timezoneB;
  final String cityA;
  final String cityB;
  final String? suggestedActivity;

  const FreeWindow({
    required this.id,
    required this.startUtc,
    required this.endUtc,
    required this.timezoneA,
    required this.timezoneB,
    required this.cityA,
    required this.cityB,
    this.suggestedActivity,
  });

  Duration get duration => endUtc.difference(startUtc);

  String get durationLabel {
    final mins = duration.inMinutes;
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
