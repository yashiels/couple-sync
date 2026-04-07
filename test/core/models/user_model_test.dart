import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_sync/core/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 4, 7, 12, 0, 0);

  UserModel createTestUser({
    String? coupleId,
    String? photoUrl,
    List<String>? fcmTokens,
  }) {
    return UserModel(
      email: 'test@example.com',
      displayName: 'Test User',
      photoUrl: photoUrl,
      timezone: 'Africa/Johannesburg',
      coupleId: coupleId,
      fcmTokens: fcmTokens ?? ['token1', 'token2'],
      createdAt: now,
    );
  }

  group('UserModel', () {
    group('toJson / fromJson roundtrip', () {
      test('serializes and deserializes correctly', () {
        final user = createTestUser(coupleId: 'couple-123');
        final json = user.toJson();
        final restored = UserModel.fromJson(json);

        expect(restored.email, user.email);
        expect(restored.displayName, user.displayName);
        expect(restored.photoUrl, user.photoUrl);
        expect(restored.timezone, user.timezone);
        expect(restored.coupleId, user.coupleId);
        expect(restored.fcmTokens, user.fcmTokens);
        expect(restored.createdAt.toUtc(), user.createdAt.toUtc());
      });

      test('handles null coupleId', () {
        final user = createTestUser(coupleId: null);
        final json = user.toJson();
        expect(json['coupleId'], isNull);

        final restored = UserModel.fromJson(json);
        expect(restored.coupleId, isNull);
      });

      test('handles null photoUrl', () {
        final user = createTestUser(photoUrl: null);
        final json = user.toJson();
        expect(json['photoUrl'], isNull);

        final restored = UserModel.fromJson(json);
        expect(restored.photoUrl, isNull);
      });

      test('handles empty fcmTokens list', () {
        final user = createTestUser(fcmTokens: []);
        final json = user.toJson();
        expect(json['fcmTokens'], isEmpty);

        final restored = UserModel.fromJson(json);
        expect(restored.fcmTokens, isEmpty);
      });
    });

    group('copyWith', () {
      test('copies with new timezone', () {
        final user = createTestUser();
        final copy = user.copyWith(timezone: 'America/New_York');
        expect(copy.timezone, 'America/New_York');
        expect(copy.email, user.email);
      });

      test('clears coupleId with clearCoupleId flag', () {
        final user = createTestUser(coupleId: 'couple-123');
        final copy = user.copyWith(clearCoupleId: true);
        expect(copy.coupleId, isNull);
      });

      test('clears photoUrl with clearPhotoUrl flag', () {
        final user = createTestUser(photoUrl: 'https://example.com/photo.jpg');
        final copy = user.copyWith(clearPhotoUrl: true);
        expect(copy.photoUrl, isNull);
      });
    });

    group('equality', () {
      test('equal users are equal', () {
        final a = createTestUser();
        final b = createTestUser();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different emails are not equal', () {
        final a = createTestUser();
        final b = UserModel(
          email: 'different@example.com',
          displayName: 'Test User',
          timezone: 'Africa/Johannesburg',
          fcmTokens: ['token1', 'token2'],
          createdAt: now,
        );
        expect(a, isNot(equals(b)));
      });
    });
  });
}
