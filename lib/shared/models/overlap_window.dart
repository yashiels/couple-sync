import 'package:cloud_firestore/cloud_firestore.dart';

/// A ranked free-time window where both partners are simultaneously available.
class OverlapWindow {
  /// UTC start time of the window.
  final DateTime startUtc;

  /// UTC end time of the window.
  final DateTime endUtc;

  /// Duration in minutes (precomputed server-side for convenience).
  final int durationMinutes;

  /// Engine-assigned score (higher = better). Based on duration, time-of-day,
  /// and whether both partners are in reasonable hours.
  final double score;

  /// Whether the window falls within reasonable waking hours for both users.
  final bool reasonableBoth;

  /// Gemini-suggested activity for this window (optional).
  final String? suggestedActivity;

  /// Google Meet link generated for this window (optional).
  final String? meetLink;

  const OverlapWindow({
    required this.startUtc,
    required this.endUtc,
    required this.durationMinutes,
    required this.score,
    required this.reasonableBoth,
    this.suggestedActivity,
    this.meetLink,
  });

  /// Wall-clock length of the window.
  Duration get duration => endUtc.difference(startUtc);

  /// Deserialises an [OverlapWindow] from a Firestore array element map.
  factory OverlapWindow.fromMap(Map<String, dynamic> map) {
    return OverlapWindow(
      startUtc: DateTime.fromMillisecondsSinceEpoch(
        (map['startUtc'] as num).toInt(),
        isUtc: true,
      ),
      endUtc: DateTime.fromMillisecondsSinceEpoch(
        (map['endUtc'] as num).toInt(),
        isUtc: true,
      ),
      durationMinutes: (map['durationMinutes'] as num).toInt(),
      score: (map['score'] as num).toDouble(),
      reasonableBoth: map['reasonableBoth'] as bool? ?? false,
      suggestedActivity: map['suggestedActivity'] as String?,
      meetLink: map['meetLink'] as String?,
    );
  }

  /// Serialises this window to a plain map for Firestore array storage.
  Map<String, dynamic> toMap() => {
        'startUtc': startUtc.millisecondsSinceEpoch,
        'endUtc': endUtc.millisecondsSinceEpoch,
        'durationMinutes': durationMinutes,
        'score': score,
        'reasonableBoth': reasonableBoth,
        if (suggestedActivity != null) 'suggestedActivity': suggestedActivity,
        if (meetLink != null) 'meetLink': meetLink,
      };

  /// Returns a copy of this window with the given fields overridden.
  OverlapWindow copyWith({
    DateTime? startUtc,
    DateTime? endUtc,
    int? durationMinutes,
    double? score,
    bool? reasonableBoth,
    String? suggestedActivity,
    String? meetLink,
  }) =>
      OverlapWindow(
        startUtc: startUtc ?? this.startUtc,
        endUtc: endUtc ?? this.endUtc,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        score: score ?? this.score,
        reasonableBoth: reasonableBoth ?? this.reasonableBoth,
        suggestedActivity: suggestedActivity ?? this.suggestedActivity,
        meetLink: meetLink ?? this.meetLink,
      );
}

/// Top-level Firestore document: `overlapWindows/{coupleId}`
class OverlapResult {
  final String coupleId;
  final List<OverlapWindow> windows;
  final DateTime computedAt;

  const OverlapResult({
    required this.coupleId,
    required this.windows,
    required this.computedAt,
  });

  /// Deserialises an [OverlapResult] from a Firestore [DocumentSnapshot].
  factory OverlapResult.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawWindows = data['windows'] as List<dynamic>? ?? [];
    return OverlapResult(
      coupleId: (data['coupleId'] as String?) ?? doc.reference.parent.parent!.id,
      windows: rawWindows
          .map((w) => OverlapWindow.fromMap(w as Map<String, dynamic>))
          .toList(),
      computedAt: data['computedAt'] != null
          ? (data['computedAt'] as Timestamp).toDate().toUtc()
          : DateTime.now().toUtc(),
    );
  }
}
