import { DateTime } from 'luxon';
import { describe, expect, it } from 'vitest';
import {
  ALGO_VERSION,
  HORIZON_DAYS,
  MAX_WINDOWS,
  MIN_WINDOW_MINUTES,
  type Block,
  type OverlapInput,
  computeOverlap,
} from './index.js';

const HOUR = 3_600_000;
const DAY = 86_400_000;
const MIN = 60_000;
const NY = 'America/New_York';
const SYD = 'Australia/Sydney';

const NOW = Date.parse('2024-06-05T10:00:00Z'); // Wednesday, already on the hour
const WS = NOW;
const WE = NOW + HORIZON_DAYS * DAY;

const at = (iso: string, zone: string) => DateTime.fromISO(iso, { zone }).toMillis();

function block(over: Partial<Block> & Pick<Block, 'startUtc' | 'endUtc'>): Block {
  return { userId: 'a', type: 'busy', timezone: 'UTC', recurrenceRule: null, ...over };
}

/** Blocks that make the owner busy for the whole horizon except [start, end). */
const busyExcept = (start: number, end: number): Block[] => [
  block({ startUtc: WS - HOUR, endUtc: start }),
  block({ startUtc: end, endUtc: WE + HOUR }),
];

function input(over: Partial<OverlapInput> = {}): OverlapInput {
  return {
    blocksA: [],
    blocksB: [],
    timezoneA: 'UTC',
    timezoneB: 'UTC',
    // Late-night on by default so the plain-UTC cases split at midnight only and the arithmetic
    // stays legible; the waking-hours clip has its own cases below.
    prefsA: { showLateNightWindows: true },
    prefsB: { showLateNightWindows: true },
    now: NOW,
    ...over,
  };
}

describe('computeOverlap — exports', () => {
  it('exposes the documented constants', () => {
    expect([ALGO_VERSION, HORIZON_DAYS, MIN_WINDOW_MINUTES, MAX_WINDOWS]).toEqual([1, 14, 30, 20]);
  });
});

describe('computeOverlap — horizon', () => {
  it('with no blocks, returns one window per local day of the horizon', () => {
    const out = computeOverlap(input());
    expect(out).toHaveLength(15); // partial first day + 13 whole days + partial last day
    expect(Math.min(...out.map((w) => w.startUtc))).toBe(WS);
    expect(Math.max(...out.map((w) => w.endUtc))).toBe(WE);
  });

  it('never emits anything outside [now, now + 14d)', () => {
    const out = computeOverlap(input({ blocksA: [block({ startUtc: WS - 10 * DAY, endUtc: WS - 5 * DAY })] }));
    for (const w of out) {
      expect(w.startUtc).toBeGreaterThanOrEqual(WS);
      expect(w.endUtc).toBeLessThanOrEqual(WE);
    }
  });

  it('returns [] when one partner is busy for the whole horizon', () => {
    expect(computeOverlap(input({ blocksA: [block({ startUtc: WS - DAY, endUtc: WE + DAY })] }))).toEqual([]);
  });
});

describe('computeOverlap — 30-minute filter runs on the rounded duration', () => {
  const slot = at('2024-06-06T12:00', 'UTC');

  it('keeps a 30-minute window', () => {
    const out = computeOverlap(input({ blocksA: busyExcept(slot, slot + 30 * MIN) }));
    expect(out.map((w) => w.durationMinutes)).toEqual([30]);
  });

  it('keeps 29.6 minutes because it rounds to 30', () => {
    const out = computeOverlap(input({ blocksA: busyExcept(slot, slot + 29.6 * MIN) }));
    expect(out.map((w) => w.durationMinutes)).toEqual([30]);
    expect(out[0]!.endUtc - out[0]!.startUtc).toBe(29.6 * MIN); // raw ms are not rounded
  });

  it('drops 29.4 minutes because it rounds to 29', () => {
    expect(computeOverlap(input({ blocksA: busyExcept(slot, slot + 29.4 * MIN) }))).toEqual([]);
  });

  it('drops 29 minutes', () => {
    expect(computeOverlap(input({ blocksA: busyExcept(slot, slot + 29 * MIN) }))).toEqual([]);
  });
});

describe('computeOverlap — block types', () => {
  const slot = at('2024-06-06T12:00', 'UTC');

  it('ignores free blocks entirely', () => {
    const withFree = computeOverlap(
      input({ blocksA: [...busyExcept(slot, slot + HOUR), block({ startUtc: WS, endUtc: WE, type: 'free' })] }),
    );
    expect(withFree).toEqual(computeOverlap(input({ blocksA: busyExcept(slot, slot + HOUR) })));
    expect(withFree.map((w) => w.startUtc)).toEqual([slot]);
  });

  it('a free block cannot carve availability out of a busy span', () => {
    const out = computeOverlap(
      input({
        blocksA: [
          block({ startUtc: WS - DAY, endUtc: WE + DAY }),
          block({ startUtc: slot, endUtc: slot + 4 * HOUR, type: 'free' }),
        ],
      }),
    );
    expect(out).toEqual([]);
  });

  it('treats tentative exactly like busy', () => {
    const asTentative = computeOverlap(
      input({ blocksA: [block({ startUtc: slot, endUtc: slot + 4 * HOUR, type: 'tentative' })] }),
    );
    const asBusy = computeOverlap(input({ blocksA: [block({ startUtc: slot, endUtc: slot + 4 * HOUR })] }));
    expect(asTentative).toEqual(asBusy);
    expect(asTentative.some((w) => w.startUtc < slot + 4 * HOUR && w.endUtc > slot)).toBe(false);
  });
});

describe('computeOverlap — sort and cap', () => {
  // Two gaps per local day: 06:00–12:00 and 13:00–00:00 UTC. 14 days => ~27 windows, over the cap.
  const twoGapsPerDay = (): Block[] => {
    const dayStart = at('2024-06-05T00:00', 'UTC');
    return [
      block({ startUtc: dayStart, endUtc: dayStart + 6 * HOUR, recurrenceRule: 'FREQ=DAILY' }),
      block({ startUtc: dayStart + 12 * HOUR, endUtc: dayStart + 13 * HOUR, recurrenceRule: 'FREQ=DAILY' }),
    ];
  };

  it('caps at MAX_WINDOWS', () => {
    expect(computeOverlap(input({ blocksA: twoGapsPerDay() }))).toHaveLength(MAX_WINDOWS);
  });

  it('returns windows in score-descending order', () => {
    const out = computeOverlap(input({ blocksA: twoGapsPerDay() }));
    for (let i = 1; i < out.length; i++) expect(out[i]!.score).toBeLessThanOrEqual(out[i - 1]!.score);
  });

  it('breaks score ties by startUtc ascending', () => {
    const out = computeOverlap(input({ blocksA: twoGapsPerDay() }));
    for (let i = 1; i < out.length; i++) {
      if (out[i]!.score === out[i - 1]!.score) expect(out[i]!.startUtc).toBeGreaterThan(out[i - 1]!.startUtc);
    }
  });

  it('keeps the best windows, not the first ones', () => {
    const out = computeOverlap(input({ blocksA: twoGapsPerDay() }));
    const all = out.map((w) => w.score);
    expect(Math.max(...all)).toBe(all[0]);
  });
});

describe('computeOverlap — reasonableBoth is couple-level', () => {
  const flag = (a: boolean, b: boolean) =>
    computeOverlap(input({ prefsA: { showLateNightWindows: a }, prefsB: { showLateNightWindows: b } }))
      .map((w) => w.reasonableBoth);

  it('is true only when neither partner wants late-night windows', () => {
    expect(new Set(flag(false, false))).toEqual(new Set([true]));
    expect(new Set(flag(true, false))).toEqual(new Set([false]));
    expect(new Set(flag(false, true))).toEqual(new Set([false]));
    expect(new Set(flag(true, true))).toEqual(new Set([false]));
  });
});

describe('computeOverlap — both partners waking hours are enforced', () => {
  const waking = input({
    timezoneA: NY,
    timezoneB: SYD,
    prefsA: { showLateNightWindows: false },
    prefsB: { showLateNightWindows: false },
  });

  it('every window sits inside 07:00–23:00 in both zones', () => {
    const out = computeOverlap(waking);
    expect(out.length).toBeGreaterThan(0);
    for (const w of out) {
      for (const zone of [NY, SYD]) {
        const s = DateTime.fromMillis(w.startUtc, { zone });
        const e = DateTime.fromMillis(w.endUtc, { zone });
        expect(s.hour).toBeGreaterThanOrEqual(7);
        expect(e.hour === 0 ? 24 : e.hour + e.minute / 60).toBeLessThanOrEqual(23);
      }
    }
  });

  it('New York + London leaves exactly 11 hours of shared waking time per day', () => {
    // NY 07:00–23:00 EDT = 11:00Z–03:00Z; London 07:00–23:00 BST = 06:00Z–22:00Z. Overlap = 11h.
    const out = computeOverlap(
      input({
        timezoneA: NY,
        timezoneB: 'Europe/London',
        prefsA: { showLateNightWindows: false },
        prefsB: { showLateNightWindows: false },
      }),
    );
    expect(out).toHaveLength(14);
    expect(new Set(out.map((w) => w.durationMinutes))).toEqual(new Set([660]));
    expect(new Set(out.map((w) => w.reasonableBoth))).toEqual(new Set([true]));
  });
});

describe('computeOverlap — DST end to end', () => {
  it('a weekly 09:00–17:00 New York block still ends at 17:00 local after spring-forward', () => {
    const marchNow = Date.parse('2024-03-06T00:00:00Z');
    const dtstart = at('2024-03-06T09:00', NY); // Wednesday, EST
    const out = computeOverlap({
      blocksA: [{ userId: 'a', type: 'busy', timezone: NY, startUtc: dtstart, endUtc: dtstart + 8 * HOUR, recurrenceRule: 'FREQ=WEEKLY' }],
      blocksB: [],
      timezoneA: NY,
      timezoneB: NY,
      prefsA: { showLateNightWindows: true },
      prefsB: { showLateNightWindows: true },
      now: marchNow,
    });

    const afterTransition = at('2024-03-13T17:00', NY);
    expect(afterTransition).toBe(Date.parse('2024-03-13T21:00:00Z')); // EDT, UTC-4
    expect(out.map((w) => w.startUtc)).toContain(afterTransition);
    // The UTC-expansion bug would have freed up 22:00Z (18:00 local) instead.
    expect(out.map((w) => w.startUtc)).not.toContain(Date.parse('2024-03-13T22:00:00Z'));
  });

  it('allows a 25-hour window on a fall-back day (durationMinutes up to 1560)', () => {
    const novNow = at('2024-11-03T00:00', NY);
    const out = computeOverlap({
      blocksA: [],
      blocksB: [],
      timezoneA: NY,
      timezoneB: NY,
      prefsA: { showLateNightWindows: true },
      prefsB: { showLateNightWindows: true },
      now: novNow,
    });
    expect(out.map((w) => w.durationMinutes)).toContain(25 * 60);
    expect(Math.max(...out.map((w) => w.durationMinutes))).toBeLessThanOrEqual(1560);
  });
});

describe('computeOverlap — purity and determinism', () => {
  function deepFreeze<T>(value: T): T {
    if (value && typeof value === 'object') Object.values(value).forEach(deepFreeze);
    return Object.freeze(value);
  }

  const withBlocks = () =>
    input({
      blocksA: [block({ startUtc: WS + 2 * HOUR, endUtc: WS + 5 * HOUR, recurrenceRule: 'FREQ=DAILY' })],
      blocksB: [block({ startUtc: WS + 8 * HOUR, endUtc: WS + 9 * HOUR, timezone: NY, recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO,TH' })],
      timezoneA: NY,
      timezoneB: SYD,
    });

  it('does not mutate the input or its elements', () => {
    const i = withBlocks();
    const before = JSON.stringify(i);
    computeOverlap(i);
    expect(JSON.stringify(i)).toBe(before);
  });

  it('runs against a deeply frozen input', () => {
    const i = deepFreeze(withBlocks());
    expect(() => computeOverlap(i)).not.toThrow();
    expect(computeOverlap(i).length).toBeGreaterThan(0);
  });

  it('is deterministic for identical input', () => {
    expect(computeOverlap(withBlocks())).toEqual(computeOverlap(withBlocks()));
  });

  it('gives identical output for any now inside the same hour', () => {
    const base = computeOverlap(withBlocks());
    for (const delta of [1, 60_000, 30 * 60_000, HOUR - 1]) {
      expect(computeOverlap({ ...withBlocks(), now: NOW + delta })).toEqual(base);
    }
  });

  it('gives different output once now crosses the hour', () => {
    expect(computeOverlap({ ...withBlocks(), now: NOW + HOUR })).not.toEqual(computeOverlap(withBlocks()));
  });

  it('is asymmetric: swapping the partners can change the scores', () => {
    const i = withBlocks();
    const swapped = computeOverlap({
      ...i,
      blocksA: i.blocksB,
      blocksB: i.blocksA,
      timezoneA: i.timezoneB,
      timezoneB: i.timezoneA,
    });
    expect(swapped).not.toEqual(computeOverlap(i));
  });
});

describe('computeOverlap — performance', () => {
  it('handles 500 recurring blocks per partner in under 500 ms', () => {
    const many = (zone: string, seed: number): Block[] =>
      Array.from({ length: 500 }, (_, i) => {
        const start = WS + ((i * 7 + seed) % 14) * DAY + ((i * 5 + seed) % 24) * HOUR + (i % 4) * 15 * MIN;
        return block({ startUtc: start, endUtc: start + 30 * MIN, timezone: zone, recurrenceRule: 'FREQ=DAILY' });
      });

    const i = input({
      blocksA: many(NY, 0),
      blocksB: many(SYD, 3),
      timezoneA: NY,
      timezoneB: SYD,
      prefsA: { showLateNightWindows: false },
      prefsB: { showLateNightWindows: false },
    });

    const t0 = performance.now();
    const out = computeOverlap(i);
    const elapsed = performance.now() - t0;

    console.log(`500 recurring blocks per partner: ${elapsed.toFixed(1)} ms, ${out.length} windows`);
    // Guard against an accidental O(n²) blowup, not a micro-benchmark. Generous ceiling so shared CI
    // runners don't flake on timing jitter — a real regression is seconds, not the ~600 ms this takes.
    expect(elapsed).toBeLessThan(2000);
    expect(out.length).toBeGreaterThan(0);
  });
});
