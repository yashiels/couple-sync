import 'package:cloud_firestore/cloud_firestore.dart';

/// User document model for users/{uid}
class UserModel {
  final String email;
  final String displayName;
  final String? photoUrl;
  final String timezone;
  final String? coupleId;
  final List<String> fcmTokens;
  final DateTime createdAt;

  const UserModel({
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.timezone,
    this.coupleId,
    required this.fcmTokens,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      photoUrl: json['photoUrl'] as String?,
      timezone: json['timezone'] as String,
      coupleId: json['coupleId'] as String?,
      fcmTokens: (json['fcmTokens'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: (json['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'timezone': timezone,
      'coupleId': coupleId,
      'fcmTokens': fcmTokens,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  UserModel copyWith({
    String? email,
    String? displayName,
    String? photoUrl,
    String? timezone,
    String? coupleId,
    List<String>? fcmTokens,
    DateTime? createdAt,
    bool clearPhotoUrl = false,
    bool clearCoupleId = false,
  }) {
    return UserModel(
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      timezone: timezone ?? this.timezone,
      coupleId: clearCoupleId ? null : (coupleId ?? this.coupleId),
      fcmTokens: fcmTokens ?? List.from(this.fcmTokens),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel &&
          runtimeType == other.runtimeType &&
          email == other.email &&
          displayName == other.displayName &&
          photoUrl == other.photoUrl &&
          timezone == other.timezone &&
          coupleId == other.coupleId &&
          _listEquals(fcmTokens, other.fcmTokens) &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        email,
        displayName,
        photoUrl,
        timezone,
        coupleId,
        Object.hashAll(fcmTokens),
        createdAt,
      );

  @override
  String toString() =>
      'UserModel(email: $email, displayName: $displayName, timezone: $timezone, coupleId: $coupleId)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
