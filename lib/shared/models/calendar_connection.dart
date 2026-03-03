import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

enum CalendarProvider { google, microsoft }

class CalendarConnection {
  final String id;
  final CalendarProvider provider;
  final String email;
  final DateTime connectedAt;
  final DateTime? lastSync;

  CalendarConnection({
    String? id,
    required this.provider,
    required this.email,
    required this.connectedAt,
    this.lastSync,
  }) : id = id ?? const Uuid().v4();

  factory CalendarConnection.fromMap(Map<String, dynamic> map) {
    return CalendarConnection(
      id: map['id'] as String,
      provider: CalendarProvider.values.byName(map['provider'] as String),
      email: map['email'] as String,
      connectedAt: (map['connectedAt'] as Timestamp).toDate(),
      lastSync: map['lastSync'] != null
          ? (map['lastSync'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'provider': provider.name,
        'email': email,
        'connectedAt': Timestamp.fromDate(connectedAt),
        if (lastSync != null) 'lastSync': Timestamp.fromDate(lastSync!),
      };

  CalendarConnection copyWith({DateTime? lastSync}) => CalendarConnection(
        id: id,
        provider: provider,
        email: email,
        connectedAt: connectedAt,
        lastSync: lastSync ?? this.lastSync,
      );
}
