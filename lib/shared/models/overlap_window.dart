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

  const OverlapWindow({
    required this.startUtc,
    required this.endUtc,
    required this.durationMinutes,
    required this.score,
    required this.reasonableBoth,
  });

  /// Wall-clock length of the window.
  Duration get duration => endUtc.difference(startUtc);

  /// Deserialises an [OverlapWindow] from a Firestore array element map.
  factory OverlapWindow.fromMap(Map<String, dynamic> map) {
    return OverlapWindow(
      startUtc: DateTime.fromMillisecondsSinceEpoch(
        (map['startUtc'] as int),
        isUtc: true,
      ),
      endUtc: DateTime.fromMillisecondsSinceEpoch(
        (map['endUtc'] as int),
        isUtc: true,
      ),
      durationMinutes: (map['durationMinutes'] as num).toInt(),
      score: (map['score'] as num).toDouble(),
      reasonableBoth: map['reasonableBoth'] as bool? ?? false,
    );
  }

  /// Serialises this window to a plain map for Firestore array storage.
  Map<String, dynamic> toMap() => {
        'startUtc': startUtc.millisecondsSinceEpoch,
        'endUtc': endUtc.millisecondsSinceEpoch,
        'durationMinutes': durationMinutes,
        'score': score,
        'reasonableBoth': reasonableBoth,
      };
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
      coupleId: doc.id,
      windows: rawWindows
          .map((w) => OverlapWindow.fromMap(w as Map<String, dynamic>))
          .toList(),
      computedAt: data['computedAt'] != null
          ? (data['computedAt'] as Timestamp).toDate().toUtc()
          : DateTime.now().toUtc(),
    );
  }
}
