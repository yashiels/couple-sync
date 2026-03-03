import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/shared/models/time_block_model.dart';

void main() {
  group('BlockType', () {
    test('has busy, free, tentative values', () {
      expect(BlockType.values, containsAll([BlockType.busy, BlockType.free, BlockType.tentative]));
    });
  });

  group('BlockSource', () {
    test('has google, microsoft, manual values', () {
      expect(BlockSource.values, containsAll([
        BlockSource.google,
        BlockSource.microsoft,
        BlockSource.manual,
      ]));
    });
  });

  group('BlockCategory', () {
    test('has study and social categories', () {
      expect(BlockCategory.values, contains(BlockCategory.study));
      expect(BlockCategory.values, contains(BlockCategory.social));
    });
  });

  group('TimeBlock', () {
    test('duration calculates correctly', () {
      final block = TimeBlock(
        id: 'test',
        userId: 'u1',
        type: BlockType.busy,
        title: 'Test',
        startUtc: DateTime.utc(2026, 3, 10, 9, 0),
        endUtc: DateTime.utc(2026, 3, 10, 11, 30),
        timezone: 'UTC',
        source: BlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.other,
        createdAt: DateTime.utc(2026, 3, 1),
      );
      expect(block.duration.inMinutes, 150);
    });

    test('copyWith preserves unchanged fields', () {
      final block = TimeBlock(
        id: 'test',
        userId: 'u1',
        type: BlockType.busy,
        title: 'Original',
        startUtc: DateTime.utc(2026, 3, 10, 9, 0),
        endUtc: DateTime.utc(2026, 3, 10, 10, 0),
        timezone: 'UTC',
        source: BlockSource.manual,
        visibility: TimeBlockVisibility.bothPartners,
        category: BlockCategory.work,
        createdAt: DateTime.utc(2026, 3, 1),
      );

      final updated = block.copyWith(title: 'Updated', category: BlockCategory.study);
      expect(updated.title, 'Updated');
      expect(updated.category, BlockCategory.study);
      expect(updated.userId, 'u1');
      expect(updated.source, BlockSource.manual);
    });
  });
}
