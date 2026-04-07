import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:couple_sync/core/models/invite_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final futureExpiry = DateTime.utc(2026, 12, 31, 23, 59, 59);
  final pastExpiry = DateTime.utc(2025, 1, 1, 0, 0, 0);

  InviteModel createTestInvite({
    String? coupleId,
    String? deepLinkUrl,
    InviteStatus status = InviteStatus.pending,
    DateTime? expiresAt,
  }) {
    return InviteModel(
      code: 'ABC123',
      createdByUid: 'user-123',
      coupleId: coupleId,
      expiresAt: expiresAt ?? futureExpiry,
      status: status,
      deepLinkUrl: deepLinkUrl,
    );
  }

  group('InviteModel', () {
    group('toJson / fromJson roundtrip', () {
      test('serializes and deserializes correctly', () {
        final invite = createTestInvite(coupleId: 'couple-789');
        final json = invite.toJson();
        final restored = InviteModel.fromJson(json);

        expect(restored.code, invite.code);
        expect(restored.createdByUid, invite.createdByUid);
        expect(restored.coupleId, invite.coupleId);
        expect(restored.expiresAt.toUtc(), invite.expiresAt.toUtc());
        expect(restored.status, invite.status);
        expect(restored.deepLinkUrl, invite.deepLinkUrl);
      });

      test('handles null coupleId', () {
        final invite = createTestInvite(coupleId: null);
        final json = invite.toJson();
        expect(json['coupleId'], isNull);

        final restored = InviteModel.fromJson(json);
        expect(restored.coupleId, isNull);
      });

      test('handles null deepLinkUrl', () {
        final invite = createTestInvite(deepLinkUrl: null);
        final json = invite.toJson();
        expect(json['deepLinkUrl'], isNull);

        final restored = InviteModel.fromJson(json);
        expect(restored.deepLinkUrl, isNull);
      });

      test('handles deepLinkUrl present', () {
        final invite =
            createTestInvite(deepLinkUrl: 'https://app.example.com/invite/ABC123');
        final json = invite.toJson();
        final restored = InviteModel.fromJson(json);
        expect(restored.deepLinkUrl, 'https://app.example.com/invite/ABC123');
      });
    });

    group('fromJson defaults', () {
      test('defaults to pending for unknown status', () {
        final json = createTestInvite().toJson();
        json['status'] = 'nonexistent';
        final invite = InviteModel.fromJson(json);
        expect(invite.status, InviteStatus.pending);
      });

      test('accepted status roundtrips correctly', () {
        final json =
            createTestInvite(status: InviteStatus.accepted).toJson();
        final invite = InviteModel.fromJson(json);
        expect(invite.status, InviteStatus.accepted);
      });

      test('expired status roundtrips correctly', () {
        final json =
            createTestInvite(status: InviteStatus.expired).toJson();
        final invite = InviteModel.fromJson(json);
        expect(invite.status, InviteStatus.expired);
      });
    });

    group('copyWith', () {
      test('copies with new status', () {
        final invite = createTestInvite(status: InviteStatus.pending);
        final copy = invite.copyWith(status: InviteStatus.accepted);
        expect(copy.status, InviteStatus.accepted);
        expect(copy.code, invite.code);
      });

      test('clears coupleId with clearCoupleId flag', () {
        final invite = createTestInvite(coupleId: 'couple-789');
        final copy = invite.copyWith(clearCoupleId: true);
        expect(copy.coupleId, isNull);
        expect(copy.code, invite.code);
      });

      test('clears deepLinkUrl with clearDeepLinkUrl flag', () {
        final invite = createTestInvite(
          deepLinkUrl: 'https://app.example.com/invite/ABC123',
        );
        final copy = invite.copyWith(clearDeepLinkUrl: true);
        expect(copy.deepLinkUrl, isNull);
      });

      test('updates expiresAt', () {
        final invite = createTestInvite();
        final newExpiry = DateTime.utc(2027, 6, 1);
        final copy = invite.copyWith(expiresAt: newExpiry);
        expect(copy.expiresAt.toUtc(), newExpiry.toUtc());
        expect(copy.code, invite.code);
      });
    });

    group('equality', () {
      test('equal invites are equal', () {
        final a = createTestInvite(coupleId: 'couple-789');
        final b = createTestInvite(coupleId: 'couple-789');
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different status is not equal', () {
        final a = createTestInvite(status: InviteStatus.pending);
        final b = createTestInvite(status: InviteStatus.accepted);
        expect(a, isNot(equals(b)));
      });

      test('different coupleId is not equal', () {
        final a = createTestInvite(coupleId: 'couple-A');
        final b = createTestInvite(coupleId: 'couple-B');
        expect(a, isNot(equals(b)));
      });
    });

    group('isValid', () {
      test('returns true for pending invite with future expiry', () {
        final invite = createTestInvite(
          status: InviteStatus.pending,
          expiresAt: futureExpiry,
        );
        expect(invite.isValid, isTrue);
      });

      test('returns false for accepted invite', () {
        final invite = createTestInvite(
          status: InviteStatus.accepted,
          expiresAt: futureExpiry,
        );
        expect(invite.isValid, isFalse);
      });

      test('returns false for expired status', () {
        final invite = createTestInvite(
          status: InviteStatus.expired,
          expiresAt: futureExpiry,
        );
        expect(invite.isValid, isFalse);
      });

      test('returns false for pending invite with past expiry', () {
        final invite = createTestInvite(
          status: InviteStatus.pending,
          expiresAt: pastExpiry,
        );
        expect(invite.isValid, isFalse);
      });
    });
  });
}
