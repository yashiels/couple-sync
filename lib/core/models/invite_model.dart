import 'package:cloud_firestore/cloud_firestore.dart';

/// Invite status enum
enum InviteStatus { pending, accepted, expired }

/// Invite document model for invites/{code}
class InviteModel {
  final String code;
  final String createdByUid;
  final String? coupleId;
  final DateTime expiresAt;
  final InviteStatus status;
  final String? deepLinkUrl;

  const InviteModel({
    required this.code,
    required this.createdByUid,
    this.coupleId,
    required this.expiresAt,
    required this.status,
    this.deepLinkUrl,
  });

  factory InviteModel.fromJson(Map<String, dynamic> json) {
    return InviteModel(
      code: json['code'] as String,
      createdByUid: json['createdByUid'] as String,
      coupleId: json['coupleId'] as String?,
      expiresAt: (json['expiresAt'] as Timestamp).toDate(),
      status: InviteStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => InviteStatus.pending,
      ),
      deepLinkUrl: json['deepLinkUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'createdByUid': createdByUid,
      'coupleId': coupleId,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'status': status.name,
      'deepLinkUrl': deepLinkUrl,
    };
  }

  InviteModel copyWith({
    String? code,
    String? createdByUid,
    String? coupleId,
    DateTime? expiresAt,
    InviteStatus? status,
    String? deepLinkUrl,
    bool clearCoupleId = false,
    bool clearDeepLinkUrl = false,
  }) {
    return InviteModel(
      code: code ?? this.code,
      createdByUid: createdByUid ?? this.createdByUid,
      coupleId: clearCoupleId ? null : (coupleId ?? this.coupleId),
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      deepLinkUrl: clearDeepLinkUrl ? null : (deepLinkUrl ?? this.deepLinkUrl),
    );
  }

  /// Check if the invite is still valid (not expired and not yet accepted)
  bool get isValid =>
      status == InviteStatus.pending && DateTime.now().isBefore(expiresAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InviteModel &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          createdByUid == other.createdByUid &&
          coupleId == other.coupleId &&
          expiresAt == other.expiresAt &&
          status == other.status &&
          deepLinkUrl == other.deepLinkUrl;

  @override
  int get hashCode => Object.hash(
        code,
        createdByUid,
        coupleId,
        expiresAt,
        status,
        deepLinkUrl,
      );

  @override
  String toString() =>
      'InviteModel(code: $code, createdByUid: $createdByUid, status: $status, expiresAt: $expiresAt)';
}
