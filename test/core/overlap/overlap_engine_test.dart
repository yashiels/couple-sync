import 'package:flutter_test/flutter_test.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';

void main() {
  group('mergeIntervals', () {
    test('empty returns empty', () {
      expect(mergeIntervals([]), isEmpty);
    });
    test('overlapping merge', () {
      expect(
        mergeIntervals([
          [1, 5],
          [3, 8],
          [10, 12],
        ]),
        [
          [1, 8],
          [10, 12],
        ],
      );
    });
    test('unsorted input gets sorted', () {
      expect(
        mergeIntervals([
          [10, 12],
          [1, 5],
        ]),
        [
          [1, 5],
          [10, 12],
        ],
      );
    });
  });

  group('intersectIntervals', () {
    test('no overlap returns empty', () {
      expect(
        intersectIntervals([
          [1, 5]
        ], [
          [6, 10]
        ]),
        isEmpty,
      );
    });
    test('partial overlap', () {
      expect(
        intersectIntervals([
          [1, 10]
        ], [
          [5, 15]
        ]),
        [
          [5, 10]
        ],
      );
    });
    test('multiple walking', () {
      expect(
        intersectIntervals([
          [1, 4],
          [8, 12]
        ], [
          [2, 10]
        ]),
        [
          [2, 4],
          [8, 10]
        ],
      );
    });
  });
}
