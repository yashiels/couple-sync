import 'package:couple_sync/core/models/overlap_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final computedAt = DateTime.utc(2026, 4, 7, 12, 0, 0);

  // Fixed epoch values for predictable tests
  final windowStartUtc =
      DateTime.utc(2026, 4, 8, 9, 0, 0).millisecondsSinceEpoch;
  final windowEndUtc =
      DateTime.utc(2026, 4, 8, 10, 0, 0).millisecondsSinceEpoch;

  OverlapWindow createTestWindow({
    int? startUtc,
    int? endUtc,
    int durationMinutes = 60,
    double score = 0.8,
    bool reasonableBoth = true,
  }) {
    return OverlapWindow(
      startUtc: startUtc ?? windowStartUtc,
      endUtc: endUtc ?? windowEndUtc,
      durationMinutes: durationMinutes,
      score: score,
      reasonableBoth: reasonableBoth,
    );
  }

  OverlapResult createTestResult({
    List<OverlapWindow>? windows,
    String blockHashA = 'hash-a-111',
    String blockHashB = 'hash-b-222',
  }) {
    return OverlapResult(
      windows: windows ?? [createTestWindow()],
      computedAt: computedAt,
      blockHashA: blockHashA,
      blockHashB: blockHashB,
    );
  }

  group('OverlapWindow', () {
    group('toJson / fromJson roundtrip', () {
      test('serializes and deserializes correctly', () {
        final window = createTestWindow();
        final json = window.toJson();
        final restored = OverlapWindow.fromJson(json);

        expect(restored.startUtc, window.startUtc);
        expect(restored.endUtc, window.endUtc);
        expect(restored.durationMinutes, window.durationMinutes);
        expect(restored.score, window.score);
        expect(restored.reasonableBoth, window.reasonableBoth);
      });

      test('handles reasonableBoth false', () {
        final window = createTestWindow(reasonableBoth: false);
        final json = window.toJson();
        final restored = OverlapWindow.fromJson(json);
        expect(restored.reasonableBoth, isFalse);
      });

      test('handles integer score in json (num coercion)', () {
        final window = createTestWindow(score: 1.0);
        final json = window.toJson();
        json['score'] = 1; // simulate integer from Firestore
        final restored = OverlapWindow.fromJson(json);
        expect(restored.score, 1.0);
      });
    });

    group('copyWith', () {
      test('copies with new score', () {
        final window = createTestWindow(score: 0.5);
        final copy = window.copyWith(score: 0.9);
        expect(copy.score, 0.9);
        expect(copy.startUtc, window.startUtc);
      });

      test('copies with new durationMinutes', () {
        final window = createTestWindow(durationMinutes: 60);
        final copy = window.copyWith(durationMinutes: 90);
        expect(copy.durationMinutes, 90);
        expect(copy.score, window.score);
      });

      test('copies with new reasonableBoth', () {
        final window = createTestWindow(reasonableBoth: true);
        final copy = window.copyWith(reasonableBoth: false);
        expect(copy.reasonableBoth, isFalse);
      });
    });

    group('equality', () {
      test('equal windows are equal', () {
        final a = createTestWindow();
        final b = createTestWindow();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different score is not equal', () {
        final a = createTestWindow(score: 0.5);
        final b = createTestWindow(score: 0.9);
        expect(a, isNot(equals(b)));
      });

      test('different startUtc is not equal', () {
        final a = createTestWindow(
          startUtc: DateTime.utc(2026, 4, 8, 9, 0, 0).millisecondsSinceEpoch,
        );
        final b = createTestWindow(
          startUtc: DateTime.utc(2026, 4, 8, 10, 0, 0).millisecondsSinceEpoch,
        );
        expect(a, isNot(equals(b)));
      });
    });

    group('computed properties', () {
      test('startDateTime returns local DateTime for the correct instant', () {
        final window = createTestWindow();
        expect(window.startDateTime.millisecondsSinceEpoch, windowStartUtc);
        expect(window.startDateTime.isUtc, isFalse);
      });

      test('endDateTime returns local DateTime for the correct instant', () {
        final window = createTestWindow();
        expect(window.endDateTime.millisecondsSinceEpoch, windowEndUtc);
        expect(window.endDateTime.isUtc, isFalse);
      });

      test('durationHours returns correct decimal hours', () {
        final window = createTestWindow(durationMinutes: 90);
        expect(window.durationHours, 1.5);
      });

      test('durationHours returns 1.0 for 60-minute window', () {
        final window = createTestWindow(durationMinutes: 60);
        expect(window.durationHours, 1.0);
      });
    });
  });

  group('OverlapResult', () {
    group('toJson / fromJson roundtrip', () {
      test('serializes and deserializes correctly', () {
        final result = createTestResult();
        final json = result.toJson();
        final restored = OverlapResult.fromJson(json);

        expect(restored.windows.length, 1);
        expect(restored.windows.first, result.windows.first);
        expect(restored.computedAt.toUtc(), result.computedAt.toUtc());
        expect(restored.blockHashA, result.blockHashA);
        expect(restored.blockHashB, result.blockHashB);
      });

      test('handles empty windows list', () {
        final result = createTestResult(windows: []);
        final json = result.toJson();
        final restored = OverlapResult.fromJson(json);
        expect(restored.windows, isEmpty);
      });

      test('handles null windows field as empty list', () {
        final result = createTestResult(windows: []);
        final json = result.toJson();
        json.remove('windows');
        final restored = OverlapResult.fromJson(json);
        expect(restored.windows, isEmpty);
      });

      test('serializes multiple windows correctly', () {
        final w1 = createTestWindow(score: 0.9);
        final w2 = createTestWindow(
          startUtc:
              DateTime.utc(2026, 4, 9, 14, 0, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2026, 4, 9, 15, 0, 0).millisecondsSinceEpoch,
          score: 0.6,
        );
        final result = createTestResult(windows: [w1, w2]);
        final json = result.toJson();
        final restored = OverlapResult.fromJson(json);

        expect(restored.windows.length, 2);
        expect(restored.windows.first.score, 0.9);
        expect(restored.windows.last.score, 0.6);
      });
    });

    group('copyWith', () {
      test('copies with new blockHashA', () {
        final result = createTestResult();
        final copy = result.copyWith(blockHashA: 'new-hash-a');
        expect(copy.blockHashA, 'new-hash-a');
        expect(copy.blockHashB, result.blockHashB);
      });

      test('copies with new windows list', () {
        final result = createTestResult(windows: [createTestWindow()]);
        final newWindow = createTestWindow(score: 0.1);
        final copy = result.copyWith(windows: [newWindow]);
        expect(copy.windows.length, 1);
        expect(copy.windows.first.score, 0.1);
      });

      test('preserves windows when not updating', () {
        final result =
            createTestResult(windows: [createTestWindow(), createTestWindow()]);
        final copy = result.copyWith(blockHashA: 'updated');
        expect(copy.windows.length, 2);
      });
    });

    group('equality', () {
      test('equal results are equal', () {
        final a = createTestResult();
        final b = createTestResult();
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different blockHashA is not equal', () {
        final a = createTestResult(blockHashA: 'hash-a');
        final b = createTestResult(blockHashA: 'hash-b');
        expect(a, isNot(equals(b)));
      });

      test('different windows list is not equal', () {
        final a = createTestResult(windows: []);
        final b = createTestResult(windows: [createTestWindow()]);
        expect(a, isNot(equals(b)));
      });
    });

    group('computed properties', () {
      test('nextWindow returns first window starting after now', () {
        final futureWindow = createTestWindow(
          startUtc:
              DateTime.now().toUtc().add(const Duration(hours: 1)).millisecondsSinceEpoch,
          endUtc:
              DateTime.now().toUtc().add(const Duration(hours: 2)).millisecondsSinceEpoch,
        );
        final result = createTestResult(windows: [futureWindow]);
        expect(result.nextWindow, equals(futureWindow));
      });

      test('nextWindow returns null when all windows are in the past', () {
        final pastWindow = createTestWindow(
          startUtc:
              DateTime.utc(2025, 1, 1, 9, 0, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2025, 1, 1, 10, 0, 0).millisecondsSinceEpoch,
        );
        final result = createTestResult(windows: [pastWindow]);
        expect(result.nextWindow, isNull);
      });

      test('nextWindow returns null for empty windows', () {
        final result = createTestResult(windows: []);
        expect(result.nextWindow, isNull);
      });

      test('windowsByScore sorts descending', () {
        final low = createTestWindow(score: 0.3);
        final high = createTestWindow(
          startUtc:
              DateTime.utc(2026, 4, 9, 9, 0, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2026, 4, 9, 10, 0, 0).millisecondsSinceEpoch,
          score: 0.9,
        );
        final result = createTestResult(windows: [low, high]);
        final sorted = result.windowsByScore;
        expect(sorted.first.score, 0.9);
        expect(sorted.last.score, 0.3);
      });

      test('windowsByTime sorts ascending by startUtc', () {
        final later = createTestWindow(
          startUtc:
              DateTime.utc(2026, 4, 9, 14, 0, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2026, 4, 9, 15, 0, 0).millisecondsSinceEpoch,
        );
        final earlier = createTestWindow(
          startUtc: windowStartUtc,
          endUtc: windowEndUtc,
        );
        final result = createTestResult(windows: [later, earlier]);
        final sorted = result.windowsByTime;
        expect(sorted.first.startUtc, windowStartUtc);
        expect(sorted.last.startUtc, later.startUtc);
      });

      test('windowsByScore does not mutate original list', () {
        final w1 = createTestWindow(score: 0.3);
        final w2 = createTestWindow(
          startUtc:
              DateTime.utc(2026, 4, 9, 9, 0, 0).millisecondsSinceEpoch,
          endUtc: DateTime.utc(2026, 4, 9, 10, 0, 0).millisecondsSinceEpoch,
          score: 0.9,
        );
        final result = createTestResult(windows: [w1, w2]);
        result.windowsByScore; // trigger sort
        expect(result.windows.first.score, 0.3); // original unchanged
      });
    });
  });
}
