import 'package:cloud_firestore/cloud_firestore.dart';

/// A single mutual free window surfaced by the overlap engine.
class OverlapWindow {
  final DateTime startUtc;
  final DateTime endUtc;
  final int durationMinutes;
  final double score;
  final bool reasonableBoth;
  final bool seen;

  const OverlapWindow({
    required this.startUtc,
    required this.endUtc,
    required this.durationMinutes,
    required this.score,
    required this.reasonableBoth,
    this.seen = false,
  });

  Duration get duration => Duration(minutes: durationMinutes);

  /// The top-level Firestore document stores a `windows` array; each element
  /// is deserialized via this factory.
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
      reasonableBoth: (map['reasonableBoth'] as bool?) ?? false,
      seen: (map['seen'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'startUtc': startUtc.millisecondsSinceEpoch,
        'endUtc': endUtc.millisecondsSinceEpoch,
        'durationMinutes': durationMinutes,
        'score': score,
        'reasonableBoth': reasonableBoth,
        'seen': seen,
      };

  OverlapWindow copyWith({bool? seen}) => OverlapWindow(
        startUtc: startUtc,
        endUtc: endUtc,
        durationMinutes: durationMinutes,
        score: score,
        reasonableBoth: reasonableBoth,
        seen: seen ?? this.seen,
      );

  @override
  String toString() =>
      'OverlapWindow(start: $startUtc, end: $endUtc, duration: ${durationMinutes}min, score: $score)';
}

/// The Firestore document stored at `overlaps/{coupleId}/windows/latest`.
class OverlapWindowsDoc {
  final List<OverlapWindow> windows;
  final DateTime? computedAt;
  final String coupleId;

  const OverlapWindowsDoc({
    required this.windows,
    required this.coupleId,
    this.computedAt,
  });

  factory OverlapWindowsDoc.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? {};
    final rawWindows = (data['windows'] as List<dynamic>?) ?? [];
    return OverlapWindowsDoc(
      coupleId: (data['coupleId'] as String?) ?? snap.id,
      computedAt: data['computedAt'] != null
          ? (data['computedAt'] as Timestamp).toDate()
          : null,
      windows: rawWindows
          .map((e) => OverlapWindow.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
