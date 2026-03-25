class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String timezone;
  final DateTime createdAt;
  final String? coupleId;

  UserModel({required this.uid, required this.email, required this.displayName, required this.timezone, required this.createdAt, this.coupleId});

  Map<String, dynamic> toFirestore() {
    return {
      uid: uid,
      email: email,
      displayName: displayName,
      timezone: timezone,
      createdAt: createdAt.millisecondsSinceEpoch,
      coupleId: coupleId,
    };
  }

  factory UserModel.fromFirestore(Map<String, dynamic> map) {
    return UserModel(
      uid: map[uid],
      email: map[email],
      displayName: map[displayName],
      timezone: map[timezone],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map[createdAt] ?? 0),
      coupleId: map[coupleId],
    );
  }
}
