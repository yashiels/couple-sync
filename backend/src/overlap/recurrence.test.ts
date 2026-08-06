import { DateTime } from 'luxon';
import { describe, expect, it } from 'vitest';
import { expandBlock } from './recurrence.js';
import type { Block } from './types.js';

const DAY = 86_400_000;
const HOUR = 3_600_000;

/** Wall clock in `zone` -> real instant. Test-side mirror of what a block's start_utc means. */
const at = (iso: string, zone: string) => DateTime.fromISO(iso, { zone }).toMillis();

function block(over: Partial<Block> & Pick<Block, 'startUtc' | 'endUtc'>): Block {
  return {
    userId: 'u',
    type: 'busy',
    timezone: 'UTC',
    recurrenceRule: null,
    ...over,
  };
}

const hourIn = (ms: number, zone: string) => DateTime.fromMillis(ms, { zone }).hour;

describe('expandBlock — no recurrence', () => {
  const ws = Date.parse('2024-06-05T00:00:00Z');
  const we = ws + 14 * DAY;

  it('clamps a block that straddles the horizon start', () => {
    const b = block({ startUtc: ws - 2 * HOUR, endUtc: ws + HOUR });
    expect(expandBlock(b, ws, we)).toEqual([{ start: ws, end: ws + HOUR }]);
  });

  it('clamps a block that straddles the horizon end', () => {
    const b = block({ startUtc: we - HOUR, endUtc: we + 5 * HOUR });
    expect(expandBlock(b, ws, we)).toEqual([{ start: we - HOUR, end: we }]);
  });

  it('drops a block entirely before the horizon', () => {
    expect(expandBlock(block({ startUtc: ws - 5 * HOUR, endUtc: ws }), ws, we)).toEqual([]);
  });

  it('drops a block entirely after the horizon', () => {
    expect(expandBlock(block({ startUtc: we, endUtc: we + HOUR }), ws, we)).toEqual([]);
  });

  it('drops a zero-length or inverted block', () => {
    expect(expandBlock(block({ startUtc: ws + HOUR, endUtc: ws + HOUR }), ws, we)).toEqual([]);
    expect(expandBlock(block({ startUtc: ws + 2 * HOUR, endUtc: ws + HOUR }), ws, we)).toEqual([]);
  });
});

describe('expandBlock — FREQ', () => {
  const ws = Date.parse('2024-06-03T00:00:00Z'); // Monday
  const we = ws + 14 * DAY;
  const nineToTen = { startUtc: ws + 9 * HOUR, endUtc: ws + 10 * HOUR };

  it('DAILY yields one instance per day', () => {
    const out = expandBlock(block({ ...nineToTen, recurrenceRule: 'FREQ=DAILY' }), ws, we);
    expect(out).toHaveLength(14);
    expect(out[0]).toEqual({ start: ws + 9 * HOUR, end: ws + 10 * HOUR });
    expect(out[13]).toEqual({ start: ws + 13 * DAY + 9 * HOUR, end: ws + 13 * DAY + 10 * HOUR });
  });

  it('DAILY;INTERVAL=2 skips every other day', () => {
    const out = expandBlock(block({ ...nineToTen, recurrenceRule: 'FREQ=DAILY;INTERVAL=2' }), ws, we);
    expect(out).toHaveLength(7);
    expect(out[1]!.start - out[0]!.start).toBe(2 * DAY);
  });

  it('WEEKLY yields two instances over a 14-day horizon', () => {
    const out = expandBlock(block({ ...nineToTen, recurrenceRule: 'FREQ=WEEKLY' }), ws, we);
    expect(out).toHaveLength(2);
    expect(out[1]!.start - out[0]!.start).toBe(7 * DAY);
  });

  it('WEEKLY;BYDAY=MO,WE,FR yields every listed weekday', () => {
    const out = expandBlock(block({ ...nineToTen, recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO,WE,FR' }), ws, we);
    // Mon 3, Wed 5, Fri 7, Mon 10, Wed 12, Fri 14 — Mon 17 is past the horizon.
    expect(out).toHaveLength(6);
    expect(out.map((o) => DateTime.fromMillis(o.start, { zone: 'UTC' }).day)).toEqual([3, 5, 7, 10, 12, 14]);
  });

  it('MONTHLY steps a whole month, not 30 days', () => {
    const start = Date.parse('2024-05-03T09:00:00Z');
    const b = block({ startUtc: start, endUtc: start + HOUR, recurrenceRule: 'FREQ=MONTHLY' });
    const junWs = Date.parse('2024-06-01T00:00:00Z');
    const out = expandBlock(b, junWs, junWs + 14 * DAY);
    expect(out).toEqual([{ start: Date.parse('2024-06-03T09:00:00Z'), end: Date.parse('2024-06-03T10:00:00Z') }]);
  });

  it('YEARLY steps a whole year', () => {
    const start = Date.parse('2021-06-05T09:00:00Z');
    const b = block({ startUtc: start, endUtc: start + HOUR, recurrenceRule: 'FREQ=YEARLY' });
    const junWs = Date.parse('2024-06-01T00:00:00Z');
    const out = expandBlock(b, junWs, junWs + 14 * DAY);
    expect(out).toEqual([{ start: Date.parse('2024-06-05T09:00:00Z'), end: Date.parse('2024-06-05T10:00:00Z') }]);
  });

  it('COUNT limits the number of instances', () => {
    const out = expandBlock(block({ ...nineToTen, recurrenceRule: 'FREQ=DAILY;COUNT=3' }), ws, we);
    expect(out).toHaveLength(3);
  });

  it('UNTIL limits the last instance', () => {
    const out = expandBlock(
      block({ ...nineToTen, recurrenceRule: 'FREQ=DAILY;UNTIL=20240606T090000Z' }),
      ws,
      we,
    );
    expect(out).toHaveLength(4); // Jun 3, 4, 5, 6
    expect(out.at(-1)!.start).toBe(Date.parse('2024-06-06T09:00:00Z'));
  });

  it('accepts the optional RRULE: prefix', () => {
    const bare = expandBlock(block({ ...nineToTen, recurrenceRule: 'FREQ=DAILY;COUNT=3' }), ws, we);
    const prefixed = expandBlock(block({ ...nineToTen, recurrenceRule: 'RRULE:FREQ=DAILY;COUNT=3' }), ws, we);
    expect(prefixed).toEqual(bare);
    expect(prefixed).toHaveLength(3);
  });

  it('clamps instances to the horizon edges', () => {
    // 22:00–02:00 daily: the last instance runs past windowEnd and must be cut at it.
    const start = ws + 22 * HOUR;
    const out = expandBlock(block({ startUtc: start, endUtc: start + 4 * HOUR, recurrenceRule: 'FREQ=DAILY' }), ws, we);
    expect(out.at(-1)!.end).toBe(we);
  });
});

describe('expandBlock — horizon lookback', () => {
  it('keeps an instance that starts before windowStart but bleeds into the horizon', () => {
    const dtstart = Date.parse('2024-06-03T23:00:00Z');
    const b = block({ startUtc: dtstart, endUtc: dtstart + 2 * HOUR, recurrenceRule: 'FREQ=DAILY' });
    const ws = Date.parse('2024-06-10T00:00:00Z'); // mid-instance: 2024-06-09T23:00Z .. 06-10T01:00Z
    const out = expandBlock(b, ws, ws + 14 * DAY);
    expect(out[0]).toEqual({ start: ws, end: Date.parse('2024-06-10T01:00:00Z') });
  });

  it('drops an instance that ends exactly at windowStart', () => {
    const dtstart = Date.parse('2024-06-03T22:00:00Z');
    const b = block({ startUtc: dtstart, endUtc: dtstart + 2 * HOUR, recurrenceRule: 'FREQ=DAILY' });
    const ws = Date.parse('2024-06-10T00:00:00Z'); // previous instance ends at exactly 00:00Z
    const out = expandBlock(b, ws, ws + 14 * DAY);
    expect(out[0]!.start).toBe(Date.parse('2024-06-10T22:00:00Z'));
  });
});

describe('expandBlock — DST, recurrence axis', () => {
  const NY = 'America/New_York';

  it('keeps 09:00 local across the spring-forward transition (2024-03-10)', () => {
    const dtstart = at('2024-03-06T09:00', NY); // Wed, EST (UTC-5) -> 14:00Z
    expect(dtstart).toBe(Date.parse('2024-03-06T14:00:00Z'));

    const b = block({ startUtc: dtstart, endUtc: dtstart + HOUR, timezone: NY, recurrenceRule: 'FREQ=WEEKLY' });
    const ws = Date.parse('2024-03-06T00:00:00Z');
    const out = expandBlock(b, ws, ws + 14 * DAY);

    expect(out).toHaveLength(2);
    expect(out.map((o) => hourIn(o.start, NY))).toEqual([9, 9]);
    // The UTC instant shifts by an hour — that is the point. The old Dart engine kept 14:00Z and
    // silently moved the block to 10:00 local.
    expect(out[0]!.start).toBe(Date.parse('2024-03-06T14:00:00Z'));
    expect(out[1]!.start).toBe(Date.parse('2024-03-13T13:00:00Z'));
    expect(out[1]!.start - out[0]!.start).not.toBe(7 * DAY);
  });

  it('keeps 09:00 local across the fall-back transition (2024-11-03)', () => {
    const dtstart = at('2024-10-30T09:00', NY); // Wed, EDT (UTC-4) -> 13:00Z
    const b = block({ startUtc: dtstart, endUtc: dtstart + HOUR, timezone: NY, recurrenceRule: 'FREQ=WEEKLY' });
    const ws = Date.parse('2024-10-30T00:00:00Z');
    const out = expandBlock(b, ws, ws + 14 * DAY);

    expect(out).toHaveLength(2);
    expect(out.map((o) => hourIn(o.start, NY))).toEqual([9, 9]);
    expect(out[0]!.start).toBe(Date.parse('2024-10-30T13:00:00Z'));
    expect(out[1]!.start).toBe(Date.parse('2024-11-06T14:00:00Z'));
    expect(out[1]!.start - out[0]!.start).toBe(7 * DAY + HOUR);
  });

  it('keeps 09:00 local across a southern-hemisphere spring-forward (Australia/Sydney 2024-10-06)', () => {
    const SYD = 'Australia/Sydney';
    const dtstart = at('2024-10-02T09:00', SYD); // AEST (UTC+10) -> 2024-10-01T23:00Z
    expect(dtstart).toBe(Date.parse('2024-10-01T23:00:00Z'));

    const b = block({ startUtc: dtstart, endUtc: dtstart + HOUR, timezone: SYD, recurrenceRule: 'FREQ=WEEKLY' });
    const ws = Date.parse('2024-10-01T00:00:00Z');
    const out = expandBlock(b, ws, ws + 14 * DAY);

    expect(out).toHaveLength(2);
    expect(out.map((o) => hourIn(o.start, SYD))).toEqual([9, 9]);
    // Sydney goes to AEDT (UTC+11), so the instant moves an hour *earlier* — opposite direction to NY.
    expect(out[1]!.start).toBe(Date.parse('2024-10-08T22:00:00Z'));
    expect(out[1]!.start - out[0]!.start).toBe(7 * DAY - HOUR);
  });

  it('no-DST control: Africa/Johannesburg instants are exactly 7 days apart', () => {
    const JNB = 'Africa/Johannesburg'; // UTC+2 year round
    const dtstart = at('2024-10-02T09:00', JNB);
    expect(dtstart).toBe(Date.parse('2024-10-02T07:00:00Z'));

    const b = block({ startUtc: dtstart, endUtc: dtstart + HOUR, timezone: JNB, recurrenceRule: 'FREQ=WEEKLY' });
    const ws = Date.parse('2024-10-01T00:00:00Z');
    const out = expandBlock(b, ws, ws + 14 * DAY);

    expect(out).toHaveLength(2);
    expect(out[1]!.start - out[0]!.start).toBe(7 * DAY);
    expect(out.map((o) => hourIn(o.start, JNB))).toEqual([9, 9]);
  });

  it('a daily block holds its local hour across a transition', () => {
    const dtstart = at('2024-03-06T09:00', NY);
    const b = block({ startUtc: dtstart, endUtc: dtstart + HOUR, timezone: NY, recurrenceRule: 'FREQ=DAILY' });
    const ws = Date.parse('2024-03-06T00:00:00Z');
    const out = expandBlock(b, ws, ws + 14 * DAY);
    expect(out).toHaveLength(14);
    expect(new Set(out.map((o) => hourIn(o.start, NY)))).toEqual(new Set([9]));
  });

  it('the same wall clock in different zones expands to different instants', () => {
    const rule = 'FREQ=DAILY;COUNT=1';
    const ws = Date.parse('2024-06-03T00:00:00Z');
    const nyStart = at('2024-06-03T09:00', NY);
    const utcStart = at('2024-06-03T09:00', 'UTC');
    const ny = expandBlock(block({ startUtc: nyStart, endUtc: nyStart + HOUR, timezone: NY, recurrenceRule: rule }), ws, ws + 14 * DAY);
    const utc = expandBlock(block({ startUtc: utcStart, endUtc: utcStart + HOUR, timezone: 'UTC', recurrenceRule: rule }), ws, ws + 14 * DAY);
    expect(ny[0]!.start - utc[0]!.start).toBe(4 * HOUR); // EDT is UTC-4
  });
});
