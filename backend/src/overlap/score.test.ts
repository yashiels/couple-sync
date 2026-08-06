import { DateTime } from 'luxon';
import { describe, expect, it } from 'vitest';
import { compareWindows, scoreWindow } from './score.js';
import type { OverlapWindow } from './types.js';

const HOUR = 3_600_000;
const DAY = 86_400_000;
const NY = 'America/New_York';

const at = (iso: string, zone: string) => DateTime.fromISO(iso, { zone }).toMillis();
const decay = (start: number, now: number) => Math.max(0, 10 - ((start - now) / DAY) * 0.5);

/** A midweek mid-afternoon start in NY: no evening bonus, no weekend bonus. */
const PLAIN = at('2024-06-05T14:00', NY); // Wednesday

describe('scoreWindow — base term', () => {
  it('is log2(hours + 1) * 10', () => {
    for (const [hrs, base] of [
      [1, 10],
      [3, 20],
      [7, 30],
      [0.5, Math.log2(1.5) * 10],
    ] as const) {
      const w = scoreWindow({ start: PLAIN, end: PLAIN + hrs * HOUR }, NY, PLAIN, true);
      expect(w.score).toBeCloseTo(base + 10, 9); // + timeDecay 10, both bonuses zero
    }
  });

  it('grows sub-linearly with duration — a 2x longer window is not worth 2x', () => {
    const short = scoreWindow({ start: PLAIN, end: PLAIN + 2 * HOUR }, NY, PLAIN, true).score;
    const long = scoreWindow({ start: PLAIN, end: PLAIN + 4 * HOUR }, NY, PLAIN, true).score;
    expect(long).toBeGreaterThan(short);
    expect(long).toBeLessThan(2 * short);
  });
});

describe('scoreWindow — evening bonus boundaries in A s zone', () => {
  const now = at('2024-06-05T00:00', NY);
  const scoreAt = (localIso: string) => {
    const start = at(localIso, NY);
    const w = scoreWindow({ start, end: start + HOUR }, NY, now, true);
    // Strip the terms under test's control so what remains is the bonus alone.
    return w.score - 10 - decay(start, now);
  };

  it('17:59 local gets no bonus', () => expect(scoreAt('2024-06-05T17:59')).toBeCloseTo(0, 9));
  it('18:00 local gets the bonus', () => expect(scoreAt('2024-06-05T18:00')).toBeCloseTo(5, 9));
  it('20:59 local still gets the bonus', () => expect(scoreAt('2024-06-05T20:59')).toBeCloseTo(5, 9));
  it('21:00 local loses the bonus', () => expect(scoreAt('2024-06-05T21:00')).toBeCloseTo(0, 9));

  it('is judged in A s zone, not UTC', () => {
    // 2024-06-06T01:00Z is 21:00 in New York (no bonus) but 01:00 UTC (no bonus either) — use a
    // start that is evening in NY and morning-after in UTC.
    const start = at('2024-06-05T19:00', NY); // = 2024-06-05T23:00Z
    expect(DateTime.fromMillis(start, { zone: 'UTC' }).hour).toBe(23);
    const inNy = scoreWindow({ start, end: start + HOUR }, NY, now, true).score;
    const inUtc = scoreWindow({ start, end: start + HOUR }, 'UTC', now, true).score;
    expect(inNy - inUtc).toBeCloseTo(5, 9);
  });
});

describe('scoreWindow — weekend bonus', () => {
  const now = at('2024-06-03T00:00', NY);
  const bonusAt = (localIso: string, zone: string) => {
    const start = at(localIso, zone);
    const w = scoreWindow({ start, end: start + HOUR }, zone, now, true);
    const evening = DateTime.fromMillis(start, { zone }).hour >= 18 && DateTime.fromMillis(start, { zone }).hour < 21 ? 5 : 0;
    return w.score - 10 - decay(start, now) - evening;
  };

  it('Friday gets nothing', () => expect(bonusAt('2024-06-07T14:00', NY)).toBeCloseTo(0, 9));
  it('Saturday gets 5', () => expect(bonusAt('2024-06-08T14:00', NY)).toBeCloseTo(5, 9));
  it('Sunday gets 5', () => expect(bonusAt('2024-06-09T14:00', NY)).toBeCloseTo(5, 9));
  it('Monday gets nothing', () => expect(bonusAt('2024-06-10T14:00', NY)).toBeCloseTo(0, 9));

  it('is judged in A s zone: Sunday 23:00 NY is Monday in UTC', () => {
    const start = at('2024-06-09T23:00', NY); // = 2024-06-10T03:00Z, a Monday in UTC
    expect(DateTime.fromMillis(start, { zone: 'UTC' }).weekday).toBe(1);
    const inNy = scoreWindow({ start, end: start + HOUR }, NY, now, true).score;
    const inUtc = scoreWindow({ start, end: start + HOUR }, 'UTC', now, true).score;
    expect(inNy - inUtc).toBeCloseTo(5, 9);
  });
});

describe('scoreWindow — timeDecay', () => {
  const now = Date.parse('2024-06-05T00:00:00Z'); // Wednesday, midnight UTC
  // Offsets below deliberately avoid landing on a Sat/Sun, so `bare` is base + decay only.
  const bare = (start: number) => scoreWindow({ start, end: start + HOUR }, 'UTC', now, true).score - 10;

  it('is 10 when the window starts now', () => expect(bare(now)).toBeCloseTo(10, 9));
  it('drops 0.5 per whole day', () => expect(bare(now + 6 * DAY)).toBeCloseTo(7, 9));
  it('is fractional, not stepped', () => expect(bare(now + 12 * HOUR)).toBeCloseTo(9.75, 9));
  it('is exactly 0 at day 20', () => expect(bare(now + 20 * DAY)).toBeCloseTo(0, 9));
  it('clamps at 0 beyond day 20', () => {
    expect(bare(now + 21 * DAY)).toBeCloseTo(0, 9);
    expect(bare(now + 400 * DAY)).toBeCloseTo(0, 9);
  });
  it('never goes negative even for absurd distances', () => {
    const w = scoreWindow({ start: now + 5000 * DAY, end: now + 5000 * DAY + HOUR }, 'UTC', now, true);
    expect(w.score).toBeGreaterThanOrEqual(10); // base only, decay floored to 0
  });
});

describe('scoreWindow — passthrough fields', () => {
  it('rounds durationMinutes to the nearest minute', () => {
    expect(scoreWindow({ start: 0, end: 29.6 * 60_000 }, 'UTC', 0, true).durationMinutes).toBe(30);
    expect(scoreWindow({ start: 0, end: 29.4 * 60_000 }, 'UTC', 0, true).durationMinutes).toBe(29);
  });

  it('copies startUtc/endUtc and reasonableBoth verbatim', () => {
    const w = scoreWindow({ start: 111, end: 222 }, 'UTC', 0, false);
    expect(w.startUtc).toBe(111);
    expect(w.endUtc).toBe(222);
    expect(w.reasonableBoth).toBe(false);
  });

  it('has no way to see B s zone — the signature only takes A s', () => {
    expect(scoreWindow.length).toBe(4);
  });
});

describe('compareWindows', () => {
  const w = (score: number, startUtc: number): OverlapWindow => ({
    startUtc,
    endUtc: startUtc + HOUR,
    durationMinutes: 60,
    score,
    reasonableBoth: true,
  });

  it('sorts by score descending', () => {
    expect([w(1, 0), w(3, 0), w(2, 0)].sort(compareWindows).map((x) => x.score)).toEqual([3, 2, 1]);
  });

  it('breaks ties by startUtc ascending', () => {
    expect([w(5, 300), w(5, 100), w(5, 200)].sort(compareWindows).map((x) => x.startUtc)).toEqual([100, 200, 300]);
  });

  it('score wins over start', () => {
    expect([w(1, 0), w(9, 999)].sort(compareWindows).map((x) => x.score)).toEqual([9, 1]);
  });
});
