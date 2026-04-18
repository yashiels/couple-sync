import { DateTime } from 'luxon';
import {
  mergeIntervals,
  intersectIntervals,
  computeFreeIntervals,
  expandBlock,
  clipIntervalToWakingHours,
  clipToWakingHours,
  scoreWindow,
  computeBlockHash,
  computeOverlap,
} from '../lib/overlap';
import { TimeBlock } from '../lib/types';

const makeBlock = (overrides: Partial<TimeBlock> & { startUtc: number; endUtc: number }): TimeBlock => ({
  userId: 'user1',
  title: 'Test',
  type: 'busy',
  timezone: 'UTC',
  source: 'manual',
  visibility: 'bothPartners',
  ...overrides,
});

// Fixed reference time: Monday 2024-01-15 12:00:00 UTC
const REF_MS = DateTime.fromISO('2024-01-15T12:00:00.000Z').toMillis();
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

describe('mergeIntervals', () => {
  test('returns empty array for empty input', () => {
    expect(mergeIntervals([])).toEqual([]);
  });

  test('returns single interval unchanged', () => {
    expect(mergeIntervals([[10, 20]])).toEqual([[10, 20]]);
  });

  test('merges two overlapping intervals', () => {
    expect(mergeIntervals([[10, 20], [15, 25]])).toEqual([[10, 25]]);
  });

  test('merges adjacent intervals', () => {
    expect(mergeIntervals([[10, 20], [20, 30]])).toEqual([[10, 30]]);
  });

  test('keeps non-overlapping intervals separate', () => {
    expect(mergeIntervals([[10, 20], [30, 40]])).toEqual([[10, 20], [30, 40]]);
  });

  test('handles unsorted input', () => {
    expect(mergeIntervals([[30, 40], [10, 20], [15, 25]])).toEqual([[10, 25], [30, 40]]);
  });

  test('merges multiple overlapping intervals into one', () => {
    expect(mergeIntervals([[0, 5], [2, 8], [6, 10]])).toEqual([[0, 10]]);
  });
});

describe('intersectIntervals', () => {
  test('returns empty for non-overlapping sets', () => {
    expect(intersectIntervals([[0, 5]], [[10, 15]])).toEqual([]);
  });

  test('intersects fully overlapping intervals', () => {
    expect(intersectIntervals([[0, 10]], [[3, 7]])).toEqual([[3, 7]]);
  });

  test('intersects partially overlapping intervals', () => {
    expect(intersectIntervals([[0, 10], [15, 25]], [[5, 20]])).toEqual([[5, 10], [15, 20]]);
  });

  test('returns empty for empty inputs', () => {
    expect(intersectIntervals([], [[0, 10]])).toEqual([]);
    expect(intersectIntervals([[0, 10]], [])).toEqual([]);
  });

  test('handles identical intervals', () => {
    expect(intersectIntervals([[5, 15]], [[5, 15]])).toEqual([[5, 15]]);
  });
});

describe('computeFreeIntervals', () => {
  test('returns entire window when no blocks', () => {
    expect(computeFreeIntervals([], 0, 100)).toEqual([[0, 100]]);
  });

  test('excludes busy block in middle', () => {
    const blocks = [makeBlock({ startUtc: 30, endUtc: 70 })];
    expect(computeFreeIntervals(blocks, 0, 100)).toEqual([[0, 30], [70, 100]]);
  });

  test('excludes busy block at start', () => {
    const blocks = [makeBlock({ startUtc: 0, endUtc: 40 })];
    expect(computeFreeIntervals(blocks, 0, 100)).toEqual([[40, 100]]);
  });

  test('excludes busy block at end', () => {
    const blocks = [makeBlock({ startUtc: 60, endUtc: 100 })];
    expect(computeFreeIntervals(blocks, 0, 100)).toEqual([[0, 60]]);
  });

  test('returns empty when entire window is blocked', () => {
    const blocks = [makeBlock({ startUtc: 0, endUtc: 100 })];
    expect(computeFreeIntervals(blocks, 0, 100)).toEqual([]);
  });

  test('merges overlapping busy blocks', () => {
    const blocks = [
      makeBlock({ startUtc: 10, endUtc: 50 }),
      makeBlock({ startUtc: 30, endUtc: 70 }),
    ];
    expect(computeFreeIntervals(blocks, 0, 100)).toEqual([[0, 10], [70, 100]]);
  });

  test('ignores free-type blocks', () => {
    const blocks = [makeBlock({ type: 'free', startUtc: 20, endUtc: 60 })];
    expect(computeFreeIntervals(blocks, 0, 100)).toEqual([[0, 100]]);
  });

  test('treats tentative blocks as busy', () => {
    const blocks = [makeBlock({ type: 'tentative', startUtc: 20, endUtc: 60 })];
    expect(computeFreeIntervals(blocks, 0, 100)).toEqual([[0, 20], [60, 100]]);
  });
});

describe('expandBlock', () => {
  test('returns single occurrence for non-recurring block within window', () => {
    const block = makeBlock({ startUtc: 50, endUtc: 80 });
    expect(expandBlock(block, 0, 100)).toEqual([[50, 80]]);
  });

  test('returns empty when block is outside window', () => {
    const block = makeBlock({ startUtc: 200, endUtc: 300 });
    expect(expandBlock(block, 0, 100)).toEqual([]);
  });

  test('clips block partially outside window', () => {
    const block = makeBlock({ startUtc: 80, endUtc: 120 });
    const result = expandBlock(block, 0, 100);
    expect(result.length).toBe(1);
    expect(result[0][0]).toBe(80);
    expect(result[0][1]).toBe(100);
  });

  test('expands weekly recurrence within window', () => {
    // Monday 10am UTC, recurs every week
    const startMs = DateTime.fromISO('2024-01-15T10:00:00.000Z').toMillis();
    const endMs = startMs + HOUR_MS;
    const block = makeBlock({
      startUtc: startMs,
      endUtc: endMs,
      recurrenceRule: 'FREQ=WEEKLY',
    });
    const windowEnd = startMs + 21 * DAY_MS; // 3 weeks
    const occurrences = expandBlock(block, startMs, windowEnd);
    expect(occurrences.length).toBe(3); // 3 Mondays
    expect(occurrences[1][0]).toBeCloseTo(startMs + 7 * DAY_MS, -3);
  });

  test('expands daily recurrence correctly', () => {
    const startMs = DateTime.fromISO('2024-01-15T09:00:00.000Z').toMillis();
    const block = makeBlock({
      startUtc: startMs,
      endUtc: startMs + HOUR_MS,
      recurrenceRule: 'FREQ=DAILY',
    });
    const windowEnd = startMs + 5 * DAY_MS;
    const occurrences = expandBlock(block, startMs, windowEnd);
    expect(occurrences.length).toBe(5);
  });
});

describe('clipIntervalToWakingHours', () => {
  test('keeps interval fully within waking hours unchanged', () => {
    // 10am-2pm UTC
    const start = DateTime.fromISO('2024-01-15T10:00:00.000Z').toMillis();
    const end = DateTime.fromISO('2024-01-15T14:00:00.000Z').toMillis();
    const result = clipIntervalToWakingHours(start, end, 'UTC');
    expect(result).toEqual([[start, end]]);
  });

  test('returns empty for interval entirely in sleeping hours', () => {
    // 2am-5am UTC - before wake time
    const start = DateTime.fromISO('2024-01-15T02:00:00.000Z').toMillis();
    const end = DateTime.fromISO('2024-01-15T05:00:00.000Z').toMillis();
    const result = clipIntervalToWakingHours(start, end, 'UTC');
    expect(result).toEqual([]);
  });

  test('clips start of interval that begins before wake time', () => {
    // 5am-11am UTC → clipped to 7am-11am
    const start = DateTime.fromISO('2024-01-15T05:00:00.000Z').toMillis();
    const end = DateTime.fromISO('2024-01-15T11:00:00.000Z').toMillis();
    const wake = DateTime.fromISO('2024-01-15T07:00:00.000Z').toMillis();
    const result = clipIntervalToWakingHours(start, end, 'UTC');
    expect(result).toEqual([[wake, end]]);
  });

  test('clips end of interval that runs past sleep time', () => {
    // 8pm-2am UTC → clipped to 8pm-11pm
    const start = DateTime.fromISO('2024-01-15T20:00:00.000Z').toMillis();
    const end = DateTime.fromISO('2024-01-16T02:00:00.000Z').toMillis();
    const sleep = DateTime.fromISO('2024-01-15T23:00:00.000Z').toMillis();
    const result = clipIntervalToWakingHours(start, end, 'UTC');
    expect(result).toEqual([[start, sleep]]);
  });

  test('splits multi-day interval into daily waking segments', () => {
    // Mon 8pm UTC to Wed 9am UTC
    const start = DateTime.fromISO('2024-01-15T20:00:00.000Z').toMillis();
    const end = DateTime.fromISO('2024-01-17T09:00:00.000Z').toMillis();
    const result = clipIntervalToWakingHours(start, end, 'UTC');

    const monSleep = DateTime.fromISO('2024-01-15T23:00:00.000Z').toMillis();
    const tueWake = DateTime.fromISO('2024-01-16T07:00:00.000Z').toMillis();
    const tueSleep = DateTime.fromISO('2024-01-16T23:00:00.000Z').toMillis();
    const wedWake = DateTime.fromISO('2024-01-17T07:00:00.000Z').toMillis();

    expect(result).toHaveLength(3);
    expect(result[0]).toEqual([start, monSleep]);
    expect(result[1]).toEqual([tueWake, tueSleep]);
    expect(result[2]).toEqual([wedWake, end]);
  });
});

describe('clipToWakingHours', () => {
  test('clips multiple intervals to waking hours', () => {
    const i1Start = DateTime.fromISO('2024-01-15T06:00:00.000Z').toMillis();
    const i1End = DateTime.fromISO('2024-01-15T10:00:00.000Z').toMillis();
    const i2Start = DateTime.fromISO('2024-01-15T22:00:00.000Z').toMillis();
    const i2End = DateTime.fromISO('2024-01-16T02:00:00.000Z').toMillis();

    const wake = DateTime.fromISO('2024-01-15T07:00:00.000Z').toMillis();
    const sleep = DateTime.fromISO('2024-01-15T23:00:00.000Z').toMillis();

    const result = clipToWakingHours([[i1Start, i1End], [i2Start, i2End]], 'UTC');

    expect(result).toHaveLength(2);
    expect(result[0]).toEqual([wake, i1End]);
    expect(result[1]).toEqual([i2Start, sleep]);
  });
});

describe('scoreWindow', () => {
  test('longer windows score higher', () => {
    const now = REF_MS;
    const shortScore = scoreWindow(now + HOUR_MS, now + 2 * HOUR_MS, 'UTC', 'UTC', now);
    const longScore = scoreWindow(now + HOUR_MS, now + 5 * HOUR_MS, 'UTC', 'UTC', now);
    expect(longScore).toBeGreaterThan(shortScore);
  });

  test('sooner windows score higher (time decay)', () => {
    const now = REF_MS;
    const soonScore = scoreWindow(now + DAY_MS, now + DAY_MS + 2 * HOUR_MS, 'UTC', 'UTC', now);
    const laterScore = scoreWindow(now + 10 * DAY_MS, now + 10 * DAY_MS + 2 * HOUR_MS, 'UTC', 'UTC', now);
    expect(soonScore).toBeGreaterThan(laterScore);
  });

  test('returns a non-negative score', () => {
    const score = scoreWindow(REF_MS, REF_MS + 2 * HOUR_MS, 'UTC', 'UTC', REF_MS);
    expect(score).toBeGreaterThanOrEqual(0);
  });
});

describe('computeBlockHash', () => {
  test('same blocks produce same hash', () => {
    const blocks = [makeBlock({ startUtc: 1000, endUtc: 2000 })];
    expect(computeBlockHash(blocks)).toBe(computeBlockHash(blocks));
  });

  test('different blocks produce different hash', () => {
    const blocksA = [makeBlock({ startUtc: 1000, endUtc: 2000 })];
    const blocksB = [makeBlock({ startUtc: 3000, endUtc: 4000 })];
    expect(computeBlockHash(blocksA)).not.toBe(computeBlockHash(blocksB));
  });

  test('order-independent (sorts before hashing)', () => {
    const b1 = makeBlock({ startUtc: 1000, endUtc: 2000 });
    const b2 = makeBlock({ startUtc: 3000, endUtc: 4000 });
    expect(computeBlockHash([b1, b2])).toBe(computeBlockHash([b2, b1]));
  });

  test('empty blocks list produces consistent hash', () => {
    expect(computeBlockHash([])).toBe(computeBlockHash([]));
  });
});

describe('computeOverlap', () => {
  test('finds overlap windows when both users have no blocks', () => {
    // Use a fixed "now" that's in the middle of the day (10am UTC)
    const now = DateTime.fromISO('2024-01-15T10:00:00.000Z').toMillis();
    const windows = computeOverlap([], [], 'UTC', 'UTC', now);
    expect(windows.length).toBeGreaterThan(0);
    expect(windows.every(w => w.durationMinutes >= 30)).toBe(true);
  });

  test('finds no overlap when user A is busy all day every day', () => {
    const now = DateTime.fromISO('2024-01-15T00:00:00.000Z').toMillis();
    const blocksA: TimeBlock[] = [];
    for (let i = 0; i < 14; i++) {
      blocksA.push(makeBlock({
        userId: 'userA',
        startUtc: now + i * DAY_MS,
        endUtc: now + (i + 1) * DAY_MS,
      }));
    }
    const windows = computeOverlap(blocksA, [], 'UTC', 'UTC', now);
    expect(windows).toHaveLength(0);
  });

  test('returns at most 20 windows', () => {
    const now = DateTime.fromISO('2024-01-15T10:00:00.000Z').toMillis();
    const windows = computeOverlap([], [], 'UTC', 'UTC', now);
    expect(windows.length).toBeLessThanOrEqual(20);
  });

  test('windows are sorted by score descending', () => {
    const now = DateTime.fromISO('2024-01-15T10:00:00.000Z').toMillis();
    const windows = computeOverlap([], [], 'UTC', 'UTC', now);
    for (let i = 1; i < windows.length; i++) {
      expect(windows[i].score).toBeLessThanOrEqual(windows[i - 1].score);
    }
  });

  test('windows have correct durationMinutes', () => {
    const now = DateTime.fromISO('2024-01-15T10:00:00.000Z').toMillis();
    const windows = computeOverlap([], [], 'UTC', 'UTC', now);
    for (const w of windows) {
      const expected = Math.round((w.endUtc - w.startUtc) / 60000);
      expect(w.durationMinutes).toBe(expected);
    }
  });

  test('clamps to waking hours in both timezones', () => {
    const now = DateTime.fromISO('2024-01-15T00:00:00.000Z').toMillis();
    const windows = computeOverlap([], [], 'America/New_York', 'America/Los_Angeles', now);
    for (const w of windows) {
      // All windows must start/end within 7am-11pm NY AND 7am-11pm LA
      const startNY = DateTime.fromMillis(w.startUtc, { zone: 'America/New_York' });
      const endNY = DateTime.fromMillis(w.endUtc, { zone: 'America/New_York' });
      const startLA = DateTime.fromMillis(w.startUtc, { zone: 'America/Los_Angeles' });
      const endLA = DateTime.fromMillis(w.endUtc, { zone: 'America/Los_Angeles' });

      expect(startNY.hour).toBeGreaterThanOrEqual(7);
      expect(endNY.hour).toBeLessThanOrEqual(23);
      expect(startLA.hour).toBeGreaterThanOrEqual(7);
      expect(endLA.hour).toBeLessThanOrEqual(23);
    }
  });
});
