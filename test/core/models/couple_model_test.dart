import 'package:couple_sync/core/models/couple_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pairedAt = DateTime.utc(2026, 1, 15, 10, 0, 0);
  final createdAt = DateTime.utc(2026, 1, 15, 10, 0, 0);
  final unpairAt = DateTime.utc(2026, 3, 1, 8, 0, 0);

  CoupleModel createTestCouple({
    CoupleStatus status = CoupleStatus.active,
    List<UnpairHistoryEntry>? unpairHistory,
  }) {
    return CoupleModel(
      userAUid: 'user-a-123',
      userBUid: 'user-b-456',
      status: status,
      pairedAt: pairedAt,
      unpairHistory: unpairHistory ?? [],
      createdAt: createdAt,
    );
  }

  group('UnpairHistoryEntry', () {
    group('toJson / fromJson roundtrip', () {
      test('serializes and deserializes correctly', () {
        final entry = UnpairHistoryEntry(at: unpairAt, reason: 'test reason');
        final json = entry.toJson();
        final restored = UnpairHistoryEntry.fromJson(json);

        expect(restored.at.toUtc(), entry.at.toUtc());
        expect(restored.reason, entry.reason);
      });
    });

    group('copyWith', () {
      test('copies with new reason', () {
        final entry = UnpairHistoryEntry(at: unpairAt, reason: 'old reason');
        final copy = entry.copyWith(reason: 'new reason');
        expect(copy.reason, 'new reason');
        expect(copy.at.toUtc(), unpairAt.toUtc());
      });

      test('copies with new date', () {
        final entry = UnpairHistoryEntry(at: unpairAt, reason: 'reason');
        final newDate = DateTime.utc(2026, 4, 1);
        final copy = entry.copyWith(at: newDate);
        expect(copy.at.toUtc(), newDate.toUtc());
        expect(copy.reason, entry.reason);
      });
    });

    group('equality', () {
      test('equal entries are equal', () {
        final a = UnpairHistoryEntry(at: unpairAt, reason: 'reason');
        final b = UnpairHistoryEntry(at: unpairAt, reason: 'reason');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different reasons are not equal', () {
        final a = UnpairHistoryEntry(at: unpairAt, reason: 'reason A');
        final b = UnpairHistoryEntry(at: unpairAt, reason: 'reason B');
        expect(a, isNot(equals(b)));
      });
    });
  });

  group('CoupleModel', () {
    group('toJson / fromJson roundtrip', () {
      test('serializes and deserializes correctly', () {
        final couple = createTestCouple();
        final json = couple.toJson();
        final restored = CoupleModel.fromJson(json);

        expect(restored.userAUid, couple.userAUid);
        expect(restored.userBUid, couple.userBUid);
        expect(restored.status, couple.status);
        expect(restored.pairedAt.toUtc(), couple.pairedAt.toUtc());
        expect(restored.createdAt.toUtc(), couple.createdAt.toUtc());
        expect(restored.unpairHistory, isEmpty);
      });

      test('serializes and deserializes with unpairHistory', () {
        final entry = UnpairHistoryEntry(at: unpairAt, reason: 'moved on');
        final couple = createTestCouple(unpairHistory: [entry]);
        final json = couple.toJson();
        final restored = CoupleModel.fromJson(json);

        expect(restored.unpairHistory.length, 1);
        expect(restored.unpairHistory.first.reason, 'moved on');
        expect(
          restored.unpairHistory.first.at.toUtc(),
          entry.at.toUtc(),
        );
      });

      test('handles null unpairHistory field as empty list', () {
        final couple = createTestCouple();
        final json = couple.toJson();
        json.remove('unpairHistory');
        final restored = CoupleModel.fromJson(json);
        expect(restored.unpairHistory, isEmpty);
      });
    });

    group('fromJson defaults', () {
      test('defaults to inactive for unknown status', () {
        final json = createTestCouple().toJson();
        json['status'] = 'nonexistent';
        final couple = CoupleModel.fromJson(json);
        expect(couple.status, CoupleStatus.inactive);
      });

      test('active status roundtrips correctly', () {
        final json = createTestCouple(status: CoupleStatus.active).toJson();
        final couple = CoupleModel.fromJson(json);
        expect(couple.status, CoupleStatus.active);
      });

      test('inactive status roundtrips correctly', () {
        final json = createTestCouple(status: CoupleStatus.inactive).toJson();
        final couple = CoupleModel.fromJson(json);
        expect(couple.status, CoupleStatus.inactive);
      });
    });

    group('copyWith', () {
      test('copies with new status', () {
        final couple = createTestCouple(status: CoupleStatus.active);
        final copy = couple.copyWith(status: CoupleStatus.inactive);
        expect(copy.status, CoupleStatus.inactive);
        expect(copy.userAUid, couple.userAUid);
      });

      test('copies with new unpairHistory', () {
        final couple = createTestCouple();
        final entry = UnpairHistoryEntry(at: unpairAt, reason: 'split');
        final copy = couple.copyWith(unpairHistory: [entry]);
        expect(copy.unpairHistory.length, 1);
        expect(copy.unpairHistory.first.reason, 'split');
      });

      test('preserves existing unpairHistory when not updating', () {
        final entry = UnpairHistoryEntry(at: unpairAt, reason: 'old');
        final couple = createTestCouple(unpairHistory: [entry]);
        final copy = couple.copyWith(status: CoupleStatus.inactive);
        expect(copy.unpairHistory.length, 1);
      });
    });

    group('equality', () {
      test('equal couples are equal', () {
        final a = createTestCouple();
        final b = createTestCouple();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different status is not equal', () {
        final a = createTestCouple(status: CoupleStatus.active);
        final b = createTestCouple(status: CoupleStatus.inactive);
        expect(a, isNot(equals(b)));
      });

      test('different unpairHistory is not equal', () {
        final a = createTestCouple();
        final b = createTestCouple(
          unpairHistory: [
            UnpairHistoryEntry(at: unpairAt, reason: 'reason'),
          ],
        );
        expect(a, isNot(equals(b)));
      });
    });

    group('helper methods', () {
      test('getPartnerUid returns userB when userA is provided', () {
        final couple = createTestCouple();
        expect(couple.getPartnerUid('user-a-123'), 'user-b-456');
      });

      test('getPartnerUid returns userA when userB is provided', () {
        final couple = createTestCouple();
        expect(couple.getPartnerUid('user-b-456'), 'user-a-123');
      });

      test('getPartnerUid returns null for non-member', () {
        final couple = createTestCouple();
        expect(couple.getPartnerUid('stranger'), isNull);
      });

      test('hasMember returns true for userA', () {
        final couple = createTestCouple();
        expect(couple.hasMember('user-a-123'), isTrue);
      });

      test('hasMember returns true for userB', () {
        final couple = createTestCouple();
        expect(couple.hasMember('user-b-456'), isTrue);
      });

      test('hasMember returns false for non-member', () {
        final couple = createTestCouple();
        expect(couple.hasMember('stranger'), isFalse);
      });
    });
  });
}
