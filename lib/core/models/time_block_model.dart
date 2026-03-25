// Lightweight foundation TimeBlock model for DEV-83 foundation
enum BlockType { busy, free, tentative }

enum BlockSource { google, microsoft, manual }

enum BlockCategory { work, study, commute, exercise, social, meals, sleep, personal, other }

enum TimeBlockVisibility { bothPartners, onlyMe }

class TimeBlock {
  final String id;
  final String userId;
  final String? coupleId;
  final BlockType type;
  final String title;
  final DateTime startUtc;
  final DateTime endUtc;
  final String timezone;
  final BlockSource source;
  final TimeBlockVisibility visibility;
  final BlockCategory category;
  final DateTime createdAt;

  TimeBlock({required this.id,
    required this.userId,
    this.coupleId,
    required this.type,
    required this.title,
    required this.startUtc,
    required this.endUtc,
    required this.timezone,
    required this.source,
    required this.visibility,
    required this.category,
    required this.createdAt
  });

  Map<String, dynamic> toFirestore() {
    return {
      id: id,
      userId: userId,
      coupleId: coupleId,
      type: type.toString().split(.).last,
      title: title,
      startUtc: startUtc.millisecondsSinceEpoch,
      endUtc: endUtc.millisecondsSinceEpoch,
      timezone: timezone,
      source: source.toString().split(.).last,
      visibility: visibility.toString().split(.).last,
      category: category.toString().split(.).last,
      createdAt: createdAt.millisecondsSinceEpoch,
    };
  }

  factory TimeBlock.fromFirestore(Map<String, dynamic> map) {
    return TimeBlock(
      id: map[id],
      userId: map[userId],
      coupleId: map[coupleId],
      type: BlockType.values.firstWhere((e) => e.toString().split(.).last == map[type], orElse: () => BlockType.busy),
      title: map[title],
      startUtc: DateTime.fromMillisecondsSinceEpoch(map[startUtc]),
      endUtc: DateTime.fromMillisecondsSinceEpoch(map[endUtc]),
      timezone: map[timezone],
      source: BlockSource.values.firstWhere((e) => e.toString().split(.).last == map[source], orElse: () => BlockSource.manual),
      visibility: TimeBlockVisibility.values.firstWhere((e) => e.toString().split(.).last == map[visibility], orElse: () => TimeBlockVisibility.bothPartners),
      category: BlockCategory.values.firstWhere((e) => e.toString().split(.).last == map[category], orElse: () => BlockCategory.other),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map[createdAt]),
    );
  }

  Duration get duration => endUtc.difference(startUtc);
  TimeBlock copyWith({String? id, String? title, DateTime? startUtc, DateTime? endUtc, BlockCategory? category}) {
    return TimeBlock(
      id: id ?? this.id,
      userId: userId,
      coupleId: coupleId,
      type: type,
      title: title ?? this.title,
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      timezone: timezone,
      source: source,
      visibility: visibility,
      category: category ?? this.category,
      createdAt: createdAt,
    );
  }
}
