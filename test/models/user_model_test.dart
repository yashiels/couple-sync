import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/shared/models/user_model.dart';
import 'package:couple_schedule/shared/models/calendar_connection.dart';

void main() {
  group('UserModel', () {
    test('new fields have defaults', () {
      final user = UserModel(
        uid: 'test',
        email: 'test@test.com',
        displayName: 'Test',
        timezone: 'Africa/Johannesburg',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(user.googleConnected, false);
      expect(user.microsoftConnected, false);
      expect(user.calendarConnections, isEmpty);
    });

    test('toFirestore includes calendarConnections', () {
      final user = UserModel(
        uid: 'test',
        email: 'test@test.com',
        displayName: 'Test',
        timezone: 'UTC',
        createdAt: DateTime.utc(2026, 1, 1),
        calendarConnections: [
          CalendarConnection(
            id: 'conn-1',
            provider: CalendarProvider.google,
            email: 'test@gmail.com',
            connectedAt: DateTime.utc(2026, 1, 1),
          ),
          CalendarConnection(
            id: 'conn-2',
            provider: CalendarProvider.microsoft,
            email: 'test@outlook.com',
            connectedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      final map = user.toFirestore();
      expect(map['calendarConnections'], isList);
      expect((map['calendarConnections'] as List).length, 2);
      expect(user.googleConnected, true);
      expect(user.microsoftConnected, true);
      expect(user.googleEmails, ['test@gmail.com']);
    });

    test('empty calendarConnections yields disconnected getters', () {
      final user = UserModel(
        uid: 'test',
        email: 'test@test.com',
        displayName: 'Test',
        timezone: 'UTC',
        createdAt: DateTime.utc(2026, 1, 1),
        calendarConnections: [],
      );
      expect(user.googleConnected, false);
      expect(user.microsoftConnected, false);
      expect(user.googleEmails, isEmpty);
    });
  });
}
