import 'package:flutter_test/flutter_test.dart';
import 'package:couple_sync/core/overlap/overlap_controller.dart';
import 'package:couple_sync/core/overlap/overlap_engine.dart';
import 'package:couple_sync/core/models/time_block.dart';

void main() {
  test('floorToHour rounds down to the hour', () {
    const ms = 1704067200000; // 2024-01-01T00:00:00Z
    expect(floorToHour(ms + 59 * 60 * 1000), ms);
  });

  test('floorToHour floors to hour boundary across day', () {
    // 2024-01-01T23:59:59Z -> 2024-01-01T23:00:00Z
    const base = 1704067200000;
    const hourBeforeMidnight = base + 23 * 60 * 60 * 1000;
    expect(
      floorToHour(base + 23 * 60 * 60 * 1000 + 59 * 1000),
      hourBeforeMidnight,
    );
  });

  test('computeOverlapInputHash is deterministic for identical inputs', () {
    final h1 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final h2 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(h1, h2);
  });

  test('inputHash changes when a pref changes', () {
    final base = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final toggled = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: true),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(base, isNot(toggled));
  });

  test('inputHash changes when nowBucket changes', () {
    final h1 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final h2 = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000 + 60 * 60 * 1000,
    );
    expect(h1, isNot(h2));
  });

  test('inputHash is order-independent within each partner list', () {
    final a = TimeBlock(
      userId: 'u',
      title: 'a',
      type: TimeBlockType.busy,
      category: TimeBlockCategory.other,
      startUtc: 1000,
      endUtc: 2000,
      timezone: 'UTC',
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final b = TimeBlock(
      userId: 'u',
      title: 'b',
      type: TimeBlockType.busy,
      category: TimeBlockCategory.other,
      startUtc: 3000,
      endUtc: 4000,
      timezone: 'UTC',
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final h1 = computeOverlapInputHash(
      blocksA: [a, b],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    final h2 = computeOverlapInputHash(
      blocksA: [b, a],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(h1, h2);
  });

  test('computeOverlapInputHash does not mutate caller block lists', () {
    final a = TimeBlock(
      userId: 'u',
      title: 'a',
      type: TimeBlockType.busy,
      category: TimeBlockCategory.other,
      startUtc: 3000,
      endUtc: 4000,
      timezone: 'UTC',
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final b = TimeBlock(
      userId: 'u',
      title: 'b',
      type: TimeBlockType.busy,
      category: TimeBlockCategory.other,
      startUtc: 1000,
      endUtc: 2000,
      timezone: 'UTC',
      source: TimeBlockSource.manual,
      visibility: TimeBlockVisibility.bothPartners,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final list = [a, b];
    computeOverlapInputHash(
      blocksA: list,
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(list[0], same(a));
    expect(list[1], same(b));
  });

  test('inputHash is 16 hex characters', () {
    final h = computeOverlapInputHash(
      blocksA: const [],
      blocksB: const [],
      tzA: 'UTC',
      tzB: 'UTC',
      prefsA: const PartnerPrefs(showLateNightWindows: false),
      prefsB: const PartnerPrefs(showLateNightWindows: false),
      nowBucket: 1704067200000,
    );
    expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(h), isTrue);
  });
}
