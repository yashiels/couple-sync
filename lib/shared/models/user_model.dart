import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an authenticated user stored at `users/{uid}` in Firestore.
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String timezone;        // IANA timezone id, e.g. "America/New_York"
  final String? coupleId;
  final DateTime createdAt;

  // ── Calendar connection fields ─────────────────────────────────────────────
  final bool googleConnected;
  final bool microsoftConnected;
  final String? microsoftEmail;
  final String? defaultCoupleCalendarId;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.timezone,
    this.coupleId,
    required this.createdAt,
    this.googleConnected = false,
    this.microsoftConnected = false,
    this.microsoftEmail,
    this.defaultCoupleCalendarId,
  });

  /// Deserialises a [UserModel] from a Firestore [DocumentSnapshot].
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'] as String,
      displayName: data['displayName'] as String,
      photoUrl: data['photoUrl'] as String?,
      timezone: data['timezone'] as String? ?? 'UTC',
      coupleId: data['coupleId'] as String?,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      googleConnected: data['googleConnected'] as bool? ?? false,
      microsoftConnected: data['microsoftConnected'] as bool? ?? false,
      microsoftEmail: data['microsoftEmail'] as String?,
      defaultCoupleCalendarId: data['defaultCoupleCalendarId'] as String?,
    );
  }

  /// Serialises this user to a Firestore-compatible map.
  Map<String, dynamic> toFirestore() => {
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'timezone': timezone,
        'coupleId': coupleId,
        'createdAt': Timestamp.fromDate(createdAt),
        'googleConnected': googleConnected,
        'microsoftConnected': microsoftConnected,
        'microsoftEmail': microsoftEmail,
        'defaultCoupleCalendarId': defaultCoupleCalendarId,
      };

  /// Returns a copy of this user with the given fields replaced.
  UserModel copyWith({
    String? displayName,
    String? photoUrl,
    String? timezone,
    String? coupleId,
    bool? googleConnected,
    bool? microsoftConnected,
    String? microsoftEmail,
    String? defaultCoupleCalendarId,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      timezone: timezone ?? this.timezone,
      coupleId: coupleId ?? this.coupleId,
      createdAt: createdAt,
      googleConnected: googleConnected ?? this.googleConnected,
      microsoftConnected: microsoftConnected ?? this.microsoftConnected,
      microsoftEmail: microsoftEmail ?? this.microsoftEmail,
      defaultCoupleCalendarId:
          defaultCoupleCalendarId ?? this.defaultCoupleCalendarId,
    );
  }
}
