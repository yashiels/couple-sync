/// Overlap window representing a mutual free time period
class OverlapWindow {
  final int startUtc; // Milliseconds since epoch (UTC)
  final int endUtc; // Milliseconds since epoch (UTC)
  final int durationMinutes;
  final double score;
  final bool reasonableBoth;

  const OverlapWindow({
    required this.startUtc,
    required this.endUtc,
    required this.durationMinutes,
    required this.score,
    required this.reasonableBoth,
  });

  factory OverlapWindow.fromJson(Map<String, dynamic> json) {
    return OverlapWindow(
      startUtc: json['startUtc'] as int,
      endUtc: json['endUtc'] as int,
      durationMinutes: json['durationMinutes'] as int,
      score: (json['score'] as num).toDouble(),
      reasonableBoth: json['reasonableBoth'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startUtc': startUtc,
      'endUtc': endUtc,
      'durationMinutes': durationMinutes,
      'score': score,
      'reasonableBoth': reasonableBoth,
    };
  }

  OverlapWindow copyWith({
    int? startUtc,
    int? endUtc,
    int? durationMinutes,
    double? score,
    bool? reasonableBoth,
  }) {
    return OverlapWindow(
      startUtc: startUtc ?? this.startUtc,
      endUtc: endUtc ?? this.endUtc,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      score: score ?? this.score,
      reasonableBoth: reasonableBoth ?? this.reasonableBoth,
    );
  }

  /// Get start time as DateTime (UTC)
  DateTime get startDateTime =>
      DateTime.fromMillisecondsSinceEpoch(startUtc, isUtc: true);

  /// Get end time as DateTime (UTC)
  DateTime get endDateTime =>
      DateTime.fromMillisecondsSinceEpoch(endUtc, isUtc: true);

  /// Get duration as hours (decimal)
  double get durationHours => durationMinutes / 60.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlapWindow &&
          runtimeType == other.runtimeType &&
          startUtc == other.startUtc &&
          endUtc == other.endUtc &&
          durationMinutes == other.durationMinutes &&
          score == other.score &&
          reasonableBoth == other.reasonableBoth;

  @override
  int get hashCode => Object.hash(
        startUtc,
        endUtc,
        durationMinutes,
        score,
        reasonableBoth,
      );

  @override
  String toString() =>
      'OverlapWindow(start: $startDateTime, end: $endDateTime, duration: ${durationMinutes}m, score: $score)';
}

/// Overlap result model for overlaps/{coupleId}/windows/latest
class OverlapResult {
  final List<OverlapWindow> windows;
  final DateTime computedAt;
  final String inputHash;
  final String? computedBy;

  const OverlapResult({
    required this.windows,
    required this.computedAt,
    required this.inputHash,
    this.computedBy,
  });

  factory OverlapResult.fromJson(Map<String, dynamic> json) {
    return OverlapResult(
      windows: (json['windows'] as List<dynamic>?)
              ?.map((e) => OverlapWindow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      computedAt: _parseDateTime(json['computedAt']),
      inputHash: json['inputHash'] as String? ?? '',
      computedBy: json['computedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'windows': windows.map((e) => e.toJson()).toList(),
      'computedAt': computedAt.millisecondsSinceEpoch, // int, not Timestamp
      'inputHash': inputHash,
      'computedBy': computedBy,
    };
  }

  OverlapResult copyWith({
    List<OverlapWindow>? windows,
    DateTime? computedAt,
    String? inputHash,
    String? computedBy,
  }) {
    return OverlapResult(
      windows: windows ?? List.from(this.windows),
      computedAt: computedAt ?? this.computedAt,
      inputHash: inputHash ?? this.inputHash,
      computedBy: computedBy ?? this.computedBy,
    );
  }

  /// Get the next upcoming window (first window that hasn't passed)
  OverlapWindow? get nextWindow {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    try {
      return windows.firstWhere((w) => w.startUtc > now);
    } catch (_) {
      return null;
    }
  }

  /// Get windows sorted by score (descending)
  List<OverlapWindow> get windowsByScore =>
      List.from(windows)..sort((a, b) => b.score.compareTo(a.score));

  /// Get windows sorted by start time (ascending)
  List<OverlapWindow> get windowsByTime =>
      List.from(windows)..sort((a, b) => a.startUtc.compareTo(b.startUtc));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlapResult &&
          runtimeType == other.runtimeType &&
          _listEquals(windows, other.windows) &&
          computedAt == other.computedAt &&
          inputHash == other.inputHash &&
          computedBy == other.computedBy;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(windows),
        computedAt,
        inputHash,
        computedBy,
      );

  @override
  String toString() =>
      'OverlapResult(windows: ${windows.length}, computedAt: $computedAt)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Parse a DateTime from int ms since epoch, an ISO-8601 string, or a DateTime.
DateTime _parseDateTime(dynamic value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  return DateTime.now().toUtc();
}
