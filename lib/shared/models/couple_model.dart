import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of the couple invite flow.
enum InviteStatus { pending, accepted, declined, expired }

/// A Firestore invite document (collection: `invites/{code}`).
class InviteModel {
  final String code;           // 6-char upper-case invite code
  final String createdByUid;   // uid of the person who generated it
  final DateTime expiresAt;
  final InviteStatus status;

  const InviteModel({
    required this.code,
    required this.createdByUid,
    required this.expiresAt,
    required this.status,
  });

  /// Deserialises an [InviteModel] from a Firestore [DocumentSnapshot].
  factory InviteModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InviteModel(
      code: doc.id,
      createdByUid: data['createdByUid'] as String,
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      status: InviteStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => InviteStatus.pending,
      ),
    );
  }

  /// Serialises this invite to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() => {
        'createdByUid': createdByUid,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'status': status.name,
      };
}

/// Firestore document: `couples/{coupleId}`.
class CoupleModel {
  final String coupleId;
  final String userAUid;
  final String userBUid;
  final DateTime pairedAt;

  const CoupleModel({
    required this.coupleId,
    required this.userAUid,
    required this.userBUid,
    required this.pairedAt,
  });

  /// Deserialises a [CoupleModel] from a Firestore [DocumentSnapshot].
  factory CoupleModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CoupleModel(
      coupleId: doc.id,
      userAUid: data['userAUid'] as String,
      userBUid: data['userBUid'] as String,
      pairedAt: (data['pairedAt'] as Timestamp).toDate(),
    );
  }

  /// Serialises this couple to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() => {
        'userAUid': userAUid,
        'userBUid': userBUid,
        'pairedAt': Timestamp.fromDate(pairedAt),
      };

  /// Returns the partner uid for the given user.
  String partnerUid(String myUid) => myUid == userAUid ? userBUid : userAUid;
}
