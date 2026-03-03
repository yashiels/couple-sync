import 'package:cloud_firestore/cloud_firestore.dart';

import 'calendar_connection.dart';

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
  final List<CalendarConnection> calendarConnections;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.timezone,
    this.coupleId,
    required this.createdAt,
    this.calendarConnections = const [],
  });

  // ── Convenience getters (backward-compatible) ─────────────────────────────
  bool get googleConnected =>
      calendarConnections.any((c) => c.provider == CalendarProvider.google);
  bool get microsoftConnected =>
      calendarConnections.any((c) => c.provider == CalendarProvider.microsoft);
  List<String> get googleEmails => calendarConnections
      .where((c) => c.provider == CalendarProvider.google)
      .map((c) => c.email)
      .toList();

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
      calendarConnections: (data['calendarConnections'] as List<dynamic>?)
          ?.map((e) => CalendarConnection.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
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
        'calendarConnections': calendarConnections.map((c) => c.toMap()).toList(),
      };

  /// Returns a copy of this user with the given fields replaced.
  UserModel copyWith({
    String? displayName,
    String? photoUrl,
    String? timezone,
    String? coupleId,
    List<CalendarConnection>? calendarConnections,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      timezone: timezone ?? this.timezone,
      coupleId: coupleId ?? this.coupleId,
      createdAt: createdAt,
      calendarConnections: calendarConnections ?? this.calendarConnections,
    );
  }
}
