import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/time_block.dart';

/// Represents a connected calendar source for a user.
class CalendarSourceModel {
  final CalendarSource provider;
  final bool connected;
  final DateTime? lastSync;
  final String? accountEmail;

  const CalendarSourceModel({
    required this.provider,
    required this.connected,
    this.lastSync,
    this.accountEmail,
  });

  /// Serialises this model to a plain map for Firestore storage.
  Map<String, dynamic> toMap() {
    return {
      'provider': provider.name,
      'connected': connected,
      'lastSync':
          lastSync != null ? Timestamp.fromDate(lastSync!) : null,
      'accountEmail': accountEmail,
    };
  }

  /// Deserialises a [CalendarSourceModel] from a plain Firestore map.
  factory CalendarSourceModel.fromMap(Map<String, dynamic> map) {
    DateTime? lastSync;
    if (map['lastSync'] is Timestamp) {
      lastSync = (map['lastSync'] as Timestamp).toDate().toUtc();
    }

    return CalendarSourceModel(
      provider: CalendarSource.values.firstWhere(
        (e) => e.name == map['provider'],
        orElse: () => CalendarSource.manual,
      ),
      connected: map['connected'] as bool? ?? false,
      lastSync: lastSync,
      accountEmail: map['accountEmail'] as String?,
    );
  }

  /// Returns a copy of this model with the given fields replaced.
  CalendarSourceModel copyWith({
    CalendarSource? provider,
    bool? connected,
    DateTime? lastSync,
    String? accountEmail,
  }) {
    return CalendarSourceModel(
      provider: provider ?? this.provider,
      connected: connected ?? this.connected,
      lastSync: lastSync ?? this.lastSync,
      accountEmail: accountEmail ?? this.accountEmail,
    );
  }
}
