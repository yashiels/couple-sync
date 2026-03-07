import 'package:flutter_test/flutter_test.dart';
import 'package:couple_schedule/shared/models/overlap_window.dart';

void main() {
  group('OverlapWindow', () {
    test('fromMap deserializes UTC milliseconds correctly', () {
      final map = {
        'startUtc': 1709280000000, // 2024-03-01 08:00 UTC
        'endUtc': 1709283600000, // 2024-03-01 09:00 UTC
        'durationMinutes': 60,
        'score': 45.5,
        'reasonableBoth': true,
        'suggestedActivity': 'Video call',
      };

      final window = OverlapWindow.fromMap(map);

      expect(window.startUtc.isUtc, isTrue);
      expect(window.endUtc.isUtc, isTrue);
      expect(window.durationMinutes, 60);
      expect(window.score, 45.5);
      expect(window.reasonableBoth, isTrue);
      expect(window.suggestedActivity, 'Video call');
      expect(window.duration.inMinutes, 60);
    });

    test('toMap serializes to milliseconds since epoch', () {
      final window = OverlapWindow(
        startUtc: DateTime.utc(2026, 3, 10, 14, 0),
        endUtc: DateTime.utc(2026, 3, 10, 15, 30),
        durationMinutes: 90,
        score: 72.3,
        reasonableBoth: true,
      );

      final map = window.toMap();

      expect(map['startUtc'], DateTime.utc(2026, 3, 10, 14, 0).millisecondsSinceEpoch);
      expect(map['endUtc'], DateTime.utc(2026, 3, 10, 15, 30).millisecondsSinceEpoch);
      expect(map['durationMinutes'], 90);
      expect(map['score'], 72.3);
      expect(map.containsKey('suggestedActivity'), isFalse);
      expect(map.containsKey('meetLink'), isFalse);
    });

    test('round-trip fromMap → toMap preserves data', () {
      final original = OverlapWindow(
        startUtc: DateTime.utc(2026, 6, 15, 18, 0),
        endUtc: DateTime.utc(2026, 6, 15, 20, 0),
        durationMinutes: 120,
        score: 88.0,
        reasonableBoth: true,
        suggestedActivity: 'Cook dinner together over video',
      );

      final roundTripped = OverlapWindow.fromMap(original.toMap());

      expect(roundTripped.startUtc, original.startUtc);
      expect(roundTripped.endUtc, original.endUtc);
      expect(roundTripped.durationMinutes, original.durationMinutes);
      expect(roundTripped.score, original.score);
      expect(roundTripped.reasonableBoth, original.reasonableBoth);
      expect(roundTripped.suggestedActivity, original.suggestedActivity);
    });

    test('reasonableBoth defaults to false when missing', () {
      final map = {
        'startUtc': 1709280000000,
        'endUtc': 1709283600000,
        'durationMinutes': 60,
        'score': 10.0,
      };

      final window = OverlapWindow.fromMap(map);
      expect(window.reasonableBoth, isFalse);
    });

    test('copyWith overrides specific fields', () {
      final window = OverlapWindow(
        startUtc: DateTime.utc(2026, 3, 10, 14, 0),
        endUtc: DateTime.utc(2026, 3, 10, 15, 0),
        durationMinutes: 60,
        score: 50.0,
        reasonableBoth: true,
      );

      final updated = window.copyWith(
        score: 99.0,
        suggestedActivity: 'Watch a movie',
      );

      expect(updated.score, 99.0);
      expect(updated.suggestedActivity, 'Watch a movie');
      expect(updated.startUtc, window.startUtc);
      expect(updated.durationMinutes, 60);
    });
  });

  group('OverlapWindow cross-timezone fixtures', () {
    test('window spanning US-Eastern and UK time renders correctly', () {
      // Partner A: New York (UTC-5), Partner B: London (UTC+0)
      // Free window: 2026-03-10 19:00 UTC to 21:00 UTC
      // = 2:00 PM - 4:00 PM New York / 7:00 PM - 9:00 PM London
      final window = OverlapWindow(
        startUtc: DateTime.utc(2026, 3, 10, 19, 0),
        endUtc: DateTime.utc(2026, 3, 10, 21, 0),
        durationMinutes: 120,
        score: 75.0,
        reasonableBoth: true,
      );

      // Verify UTC times are correct
      expect(window.startUtc.hour, 19);
      expect(window.endUtc.hour, 21);
      expect(window.duration.inHours, 2);

      // Simulate local-time display (what the app does)
      final nyOffset = const Duration(hours: -5);
      final londonOffset = Duration.zero;

      final nyStart = window.startUtc.add(nyOffset);
      final londonStart = window.startUtc.add(londonOffset);

      expect(nyStart.hour, 14); // 2 PM New York
      expect(londonStart.hour, 19); // 7 PM London
    });

    test('window spanning Asia/Tokyo and US-Pacific', () {
      // Partner A: Tokyo (UTC+9), Partner B: LA (UTC-8)
      // The only overlap for reasonable hours is narrow.
      // Free window: 2026-03-11 01:00 UTC to 03:00 UTC
      // = 10:00 AM - 12:00 PM Tokyo / 5:00 PM - 7:00 PM LA (prev day)
      final window = OverlapWindow(
        startUtc: DateTime.utc(2026, 3, 11, 1, 0),
        endUtc: DateTime.utc(2026, 3, 11, 3, 0),
        durationMinutes: 120,
        score: 60.0,
        reasonableBoth: true,
      );

      final tokyoOffset = const Duration(hours: 9);
      final laOffset = const Duration(hours: -8);

      final tokyoStart = window.startUtc.add(tokyoOffset);
      final laStart = window.startUtc.add(laOffset);

      expect(tokyoStart.hour, 10); // 10 AM Tokyo
      expect(laStart.hour, 17); // 5 PM LA (previous day)
    });

    test('same-timezone couple has straightforward overlap', () {
      // Both in UTC+2 (SAST)
      final window = OverlapWindow(
        startUtc: DateTime.utc(2026, 3, 10, 16, 0),
        endUtc: DateTime.utc(2026, 3, 10, 18, 0),
        durationMinutes: 120,
        score: 90.0,
        reasonableBoth: true,
      );

      final sastOffset = const Duration(hours: 2);
      final localStartA = window.startUtc.add(sastOffset);
      final localStartB = window.startUtc.add(sastOffset);

      expect(localStartA.hour, 18); // 6 PM SAST
      expect(localStartB.hour, 18); // Same
      expect(localStartA, localStartB);
    });
  });
}
