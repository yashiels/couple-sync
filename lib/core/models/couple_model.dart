import 'package:cloud_firestore/cloud_firestore.dart';

/// Unpair history entry for couples
class UnpairHistoryEntry {
  final DateTime at;
  final String reason;

  const UnpairHistoryEntry({
    required this.at,
    required this.reason,
  });

  factory UnpairHistoryEntry.fromJson(Map<String, dynamic> json) {
    return UnpairHistoryEntry(
      at: (json['at'] as Timestamp).toDate(),
      reason: json['reason'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'at': Timestamp.fromDate(at),
      'reason': reason,
    };
  }

  UnpairHistoryEntry copyWith({
    DateTime? at,
    String? reason,
  }) {
    return UnpairHistoryEntry(
      at: at ?? this.at,
      reason: reason ?? this.reason,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnpairHistoryEntry &&
          runtimeType == other.runtimeType &&
          at == other.at &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(at, reason);

  @override
  String toString() => 'UnpairHistoryEntry(at: $at, reason: $reason)';
}

/// Couple status enum
enum CoupleStatus { active, inactive }

/// Couple document model for couples/{coupleId}
class CoupleModel {
  final String userAUid;
  final String userBUid;
  final CoupleStatus status;
  final DateTime pairedAt;
  final List<UnpairHistoryEntry> unpairHistory;
  final DateTime createdAt;

  const CoupleModel({
    required this.userAUid,
    required this.userBUid,
    required this.status,
    required this.pairedAt,
    required this.unpairHistory,
    required this.createdAt,
  });

  factory CoupleModel.fromJson(Map<String, dynamic> json) {
    return CoupleModel(
      userAUid: json['userAUid'] as String,
      userBUid: json['userBUid'] as String,
      status: CoupleStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => CoupleStatus.inactive,
      ),
      pairedAt: (json['pairedAt'] as Timestamp).toDate(),
      unpairHistory: (json['unpairHistory'] as List<dynamic>?)
              ?.map((e) => UnpairHistoryEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userAUid': userAUid,
      'userBUid': userBUid,
      'status': status.name,
      'pairedAt': Timestamp.fromDate(pairedAt),
      'unpairHistory': unpairHistory.map((e) => e.toJson()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  CoupleModel copyWith({
    String? userAUid,
    String? userBUid,
    CoupleStatus? status,
    DateTime? pairedAt,
    List<UnpairHistoryEntry>? unpairHistory,
    DateTime? createdAt,
  }) {
    return CoupleModel(
      userAUid: userAUid ?? this.userAUid,
      userBUid: userBUid ?? this.userBUid,
      status: status ?? this.status,
      pairedAt: pairedAt ?? this.pairedAt,
      unpairHistory: unpairHistory ?? List.from(this.unpairHistory),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Get the partner UID for a given user UID
  String? getPartnerUid(String uid) {
    if (uid == userAUid) return userBUid;
    if (uid == userBUid) return userAUid;
    return null;
  }

  /// Check if a user is part of this couple
  bool hasMember(String uid) => uid == userAUid || uid == userBUid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoupleModel &&
          runtimeType == other.runtimeType &&
          userAUid == other.userAUid &&
          userBUid == other.userBUid &&
          status == other.status &&
          pairedAt == other.pairedAt &&
          _listEquals(unpairHistory, other.unpairHistory) &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        userAUid,
        userBUid,
        status,
        pairedAt,
        Object.hashAll(unpairHistory),
        createdAt,
      );

  @override
  String toString() =>
      'CoupleModel(userAUid: $userAUid, userBUid: $userBUid, status: $status)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
