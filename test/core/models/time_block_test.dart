import 'package:couple_sync/core/models/time_block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 4, 7, 12, 0, 0);
  final startUtc = DateTime.utc(2026, 4, 7, 9, 0, 0).millisecondsSinceEpoch;
  final endUtc = DateTime.utc(2026, 4, 7, 10, 0, 0).millisecondsSinceEpoch;

  TimeBlock createTestBlock({
    String? recurrenceRule,
    TimeBlockType type = TimeBlockType.busy,
  }) {
    return TimeBlock(
      userId: 'user-123',
      title: 'Test Block',
      type: type,
      category: TimeBlockCategory.work,
      startUtc: startUtc,
      endUtc: endUtc,
      timezone: 'Africa/Johannesburg',
      recurrenceRule: recurrenceRule,
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: now,
    );
  }

  group('TimeBlock', () {
    group('toJson / fromJson roundtrip', () {
      test('serializes and deserializes correctly', () {
        final block = createTestBlock();
        final json = block.toJson();
        final restored = TimeBlock.fromJson(json);

        expect(restored.userId, block.userId);
        expect(restored.title, block.title);
        expect(restored.type, block.type);
        expect(restored.category, block.category);
        expect(restored.startUtc, block.startUtc);
        expect(restored.endUtc, block.endUtc);
        expect(restored.timezone, block.timezone);
        expect(restored.source, block.source);
        expect(restored.visibility, block.visibility);
      });

      test('handles null recurrenceRule', () {
        final block = createTestBlock(recurrenceRule: null);
        final json = block.toJson();
        expect(json['recurrenceRule'], isNull);

        final restored = TimeBlock.fromJson(json);
        expect(restored.recurrenceRule, isNull);
        expect(restored.isRecurring, isFalse);
      });

      test('handles recurrenceRule present', () {
        final block =
            createTestBlock(recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO,WE,FR');
        final json = block.toJson();
        expect(json['recurrenceRule'], 'FREQ=WEEKLY;BYDAY=MO,WE,FR');

        final restored = TimeBlock.fromJson(json);
        expect(restored.recurrenceRule, 'FREQ=WEEKLY;BYDAY=MO,WE,FR');
        expect(restored.isRecurring, isTrue);
      });
    });

    group('fromJson defaults', () {
      test('defaults to busy for unknown type', () {
        final json = createTestBlock().toJson();
        json['type'] = 'nonexistent';
        final block = TimeBlock.fromJson(json);
        expect(block.type, TimeBlockType.busy);
      });

      test('defaults to other for unknown category', () {
        final json = createTestBlock().toJson();
        json['category'] = 'nonexistent';
        final block = TimeBlock.fromJson(json);
        expect(block.category, TimeBlockCategory.other);
      });

      test('defaults to manual for unknown source', () {
        final json = createTestBlock().toJson();
        json['source'] = 'nonexistent';
        final block = TimeBlock.fromJson(json);
        expect(block.source, TimeBlockSource.manual);
      });

      test('defaults to bothPartners for unknown visibility', () {
        final json = createTestBlock().toJson();
        json['visibility'] = 'nonexistent';
        final block = TimeBlock.fromJson(json);
        expect(block.visibility, TimeBlockVisibility.bothPartners);
      });
    });

    group('computed properties', () {
      test('durationMs returns correct value', () {
        final block = createTestBlock();
        expect(block.durationMs, endUtc - startUtc);
      });

      test('durationMinutes returns 60 for 1-hour block', () {
        final block = createTestBlock();
        expect(block.durationMinutes, 60);
      });

      test('startDateTime returns local DateTime for the correct instant', () {
        final block = createTestBlock();
        expect(block.startDateTime.millisecondsSinceEpoch, startUtc);
        expect(block.startDateTime.isUtc, isFalse);
      });

      test('endDateTime returns local DateTime for the correct instant', () {
        final block = createTestBlock();
        expect(block.endDateTime.millisecondsSinceEpoch, endUtc);
        expect(block.endDateTime.isUtc, isFalse);
      });

      test('isRecurring false when null', () {
        expect(createTestBlock(recurrenceRule: null).isRecurring, isFalse);
      });

      test('isRecurring false when empty', () {
        expect(createTestBlock(recurrenceRule: '').isRecurring, isFalse);
      });

      test('isRecurring true when set', () {
        expect(
          createTestBlock(recurrenceRule: 'FREQ=DAILY').isRecurring,
          isTrue,
        );
      });
    });

    group('copyWith', () {
      test('copies with new title', () {
        final block = createTestBlock();
        final copy = block.copyWith(title: 'New Title');
        expect(copy.title, 'New Title');
        expect(copy.userId, block.userId);
      });

      test('clearRecurrenceRule removes rule', () {
        final block =
            createTestBlock(recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO');
        final copy = block.copyWith(clearRecurrenceRule: true);
        expect(copy.recurrenceRule, isNull);
      });

      test('preserves recurrenceRule when not clearing', () {
        final block =
            createTestBlock(recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO');
        final copy = block.copyWith(title: 'Updated');
        expect(copy.recurrenceRule, 'FREQ=WEEKLY;BYDAY=MO');
      });
    });

    group('equality', () {
      test('equal blocks are equal', () {
        final a = createTestBlock();
        final b = createTestBlock();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different blocks are not equal', () {
        final a = createTestBlock();
        final b = createTestBlock(type: TimeBlockType.free);
        expect(a, isNot(equals(b)));
      });
    });
  });
}
