class CoupleModel {
  final String id;
  final String userAUid;
  final String userBUid;
  final String status;
  final DateTime? pairedAt;

  CoupleModel({required this.id, required this.userAUid, required this.userBUid, required this.status, this.pairedAt});

  Map<String, dynamic> toFirestore() {
    return {
      id: id,
      userAUid: userAUid,
      userBUid: userBUid,
      status: status,
      pairedAt: pairedAt?.millisecondsSinceEpoch,
    };
  }

  factory CoupleModel.fromFirestore(Map<String, dynamic> map) {
    return CoupleModel(
      id: map[id],
      userAUid: map[userAUid],
      userBUid: map[userBUid],
      status: map[status],
      pairedAt: map[pairedAt] != null ? DateTime.fromMillisecondsSinceEpoch(map[pairedAt]) : null,
    );
  }
}
