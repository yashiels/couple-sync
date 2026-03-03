import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/shared/models/user_model.dart';

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
      expect(user.microsoftEmail, isNull);
      expect(user.defaultCoupleCalendarId, isNull);
    });

    test('toFirestore includes new fields', () {
      final user = UserModel(
        uid: 'test',
        email: 'test@test.com',
        displayName: 'Test',
        timezone: 'UTC',
        createdAt: DateTime.utc(2026, 1, 1),
        googleConnected: true,
        microsoftConnected: true,
        microsoftEmail: 'test@outlook.com',
      );
      final map = user.toFirestore();
      expect(map['googleConnected'], true);
      expect(map['microsoftConnected'], true);
      expect(map['microsoftEmail'], 'test@outlook.com');
    });
  });
}
