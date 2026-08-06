import { DateTime } from 'luxon';
import { describe, expect, it } from 'vitest';
import { clipToLocalDays } from './clip.js';

const HOUR = 3_600_000;
const NY = 'America/New_York';
const SYD = 'Australia/Sydney';
const JNB = 'Africa/Johannesburg'; // UTC+2, no DST — the control

const at = (iso: string, zone: string) => DateTime.fromISO(iso, { zone }).toMillis();
const hours = (s: { start: number; end: number }) => (s.end - s.start) / HOUR;
const localHour = (ms: number, zone: string) => DateTime.fromMillis(ms, { zone }).hour;

describe('clipToLocalDays — full day (showLateNightWindows: true)', () => {
  it('a normal local day is one 24-hour segment', () => {
    const iv = { start: at('2024-06-05T00:00', NY), end: at('2024-06-06T00:00', NY) };
    const out = clipToLocalDays([iv], NY, true);
    expect(out).toEqual([iv]);
    expect(hours(out[0]!)).toBe(24);
  });

  it('the fall-back day 2024-11-03 in New York is 25 hours', () => {
    const iv = { start: at('2024-11-03T00:00', NY), end: at('2024-11-04T00:00', NY) };
    expect(iv.start).toBe(Date.parse('2024-11-03T04:00:00Z')); // EDT, UTC-4
    expect(iv.end).toBe(Date.parse('2024-11-04T05:00:00Z')); // EST, UTC-5

    const out = clipToLocalDays([iv], NY, true);
    expect(out).toHaveLength(1);
    expect(hours(out[0]!)).toBe(25);
  });

  it('the spring-forward day 2024-03-10 in New York is 23 hours', () => {
    const iv = { start: at('2024-03-10T00:00', NY), end: at('2024-03-11T00:00', NY) };
    const out = clipToLocalDays([iv], NY, true);
    expect(out).toHaveLength(1);
    expect(hours(out[0]!)).toBe(23);
  });

  it('splits a multi-day span across spring-forward into 24/23/24/24-hour days', () => {
    const iv = { start: at('2024-03-09T00:00', NY), end: at('2024-03-13T00:00', NY) };
    const out = clipToLocalDays([iv], NY, true);
    expect(out.map(hours)).toEqual([24, 23, 24, 24]);
    // Every boundary is still local midnight — the thing `+ 86_400_000` would break.
    expect(out.map((s) => localHour(s.start, NY))).toEqual([0, 0, 0, 0]);
  });

  it('splits a multi-day span across fall-back into 24/25/24-hour days', () => {
    const iv = { start: at('2024-11-02T00:00', NY), end: at('2024-11-05T00:00', NY) };
    const out = clipToLocalDays([iv], NY, true);
    expect(out.map(hours)).toEqual([24, 25, 24]);
    expect(out.map((s) => localHour(s.start, NY))).toEqual([0, 0, 0]);
  });

  it('southern hemisphere: Sydney 2024-10-06 springs forward to a 23-hour day', () => {
    const iv = { start: at('2024-10-05T00:00', SYD), end: at('2024-10-08T00:00', SYD) };
    const out = clipToLocalDays([iv], SYD, true);
    expect(out.map(hours)).toEqual([24, 23, 24]);
  });

  it('southern hemisphere: Sydney 2024-04-07 falls back to a 25-hour day', () => {
    const iv = { start: at('2024-04-06T00:00', SYD), end: at('2024-04-09T00:00', SYD) };
    const out = clipToLocalDays([iv], SYD, true);
    expect(out.map(hours)).toEqual([24, 25, 24]);
  });

  it('no-DST control: Johannesburg days are all 24 hours', () => {
    const iv = { start: at('2024-03-09T00:00', JNB), end: at('2024-03-13T00:00', JNB) };
    const out = clipToLocalDays([iv], JNB, true);
    expect(out.map(hours)).toEqual([24, 24, 24, 24]);
  });

  it('keeps partial first and last days as-is', () => {
    const iv = { start: at('2024-06-05T18:30', NY), end: at('2024-06-07T04:15', NY) };
    const out = clipToLocalDays([iv], NY, true);
    expect(out).toHaveLength(3);
    expect(out[0]!.start).toBe(iv.start);
    expect(out.at(-1)!.end).toBe(iv.end);
    expect(out.map(hours)).toEqual([5.5, 24, 4.25]);
  });

  it('returns [] for []', () => {
    expect(clipToLocalDays([], NY, true)).toEqual([]);
  });
});

describe('clipToLocalDays — waking hours (showLateNightWindows: false)', () => {
  it('bounds a whole local day to 07:00–23:00 wall clock', () => {
    const iv = { start: at('2024-06-05T00:00', NY), end: at('2024-06-06T00:00', NY) };
    const out = clipToLocalDays([iv], NY, false);
    expect(out).toHaveLength(1);
    expect(out[0]!.start).toBe(at('2024-06-05T07:00', NY));
    expect(out[0]!.end).toBe(at('2024-06-05T23:00', NY));
    expect(hours(out[0]!)).toBe(16);
  });

  it('drops an interval that sits entirely in the late-night gap', () => {
    const iv = { start: at('2024-06-05T02:00', NY), end: at('2024-06-05T04:00', NY) };
    expect(clipToLocalDays([iv], NY, false)).toEqual([]);
  });

  it('clips the leading edge up to 07:00 and the trailing edge back to 23:00', () => {
    const iv = { start: at('2024-06-05T05:00', NY), end: at('2024-06-05T23:45', NY) };
    const out = clipToLocalDays([iv], NY, false);
    expect(out).toEqual([{ start: at('2024-06-05T07:00', NY), end: at('2024-06-05T23:00', NY) }]);
  });

  it('never merges across the nightly gap — each local day is its own segment', () => {
    const iv = { start: at('2024-06-05T00:00', NY), end: at('2024-06-08T00:00', NY) };
    const out = clipToLocalDays([iv], NY, false);
    expect(out).toHaveLength(3);
    expect(out.map(hours)).toEqual([16, 16, 16]);
  });

  it('holds 07:00/23:00 wall clock across spring-forward (2024-03-10, New York)', () => {
    const iv = { start: at('2024-03-09T00:00', NY), end: at('2024-03-13T00:00', NY) };
    const out = clipToLocalDays([iv], NY, false);
    expect(out).toHaveLength(4);
    expect(out.map((s) => localHour(s.start, NY))).toEqual([7, 7, 7, 7]);
    expect(out.map((s) => localHour(s.end, NY))).toEqual([23, 23, 23, 23]);
    // 07:00–23:00 stays 16h: the missing hour on 2024-03-10 falls at 02:00, outside waking hours.
    expect(out.map(hours)).toEqual([16, 16, 16, 16]);
    // Proof the boundary did not drift: day 2 starts at 11:00Z (EDT), day 1 at 12:00Z (EST).
    expect(out[0]!.start).toBe(Date.parse('2024-03-09T12:00:00Z'));
    expect(out[1]!.start).toBe(Date.parse('2024-03-10T11:00:00Z'));
  });

  it('holds 07:00/23:00 wall clock across fall-back (2024-11-03, New York)', () => {
    const iv = { start: at('2024-11-02T00:00', NY), end: at('2024-11-05T00:00', NY) };
    const out = clipToLocalDays([iv], NY, false);
    expect(out).toHaveLength(3);
    expect(out.map((s) => localHour(s.start, NY))).toEqual([7, 7, 7]);
    expect(out.map((s) => localHour(s.end, NY))).toEqual([23, 23, 23]);
    expect(out.map(hours)).toEqual([16, 16, 16]);
    expect(out[0]!.start).toBe(Date.parse('2024-11-02T11:00:00Z')); // EDT
    expect(out[1]!.start).toBe(Date.parse('2024-11-03T12:00:00Z')); // EST
  });

  it('Sydney fall-back day still gives a 16h waking segment (the extra hour is at 02:00)', () => {
    // The repeated hour lands before WAKE_HOUR, so it never reaches the waking segment. Pinned so
    // nobody "fixes" the 25h expectation onto the wrong code path.
    const iv = { start: at('2024-04-07T00:00', SYD), end: at('2024-04-08T00:00', SYD) };
    const out = clipToLocalDays([iv], SYD, false);
    expect(out.map(hours)).toEqual([16]);
  });

  it('applies the clip per zone: the same interval yields different segments in A and B', () => {
    const iv = { start: Date.parse('2024-06-05T00:00:00Z'), end: Date.parse('2024-06-07T00:00:00Z') };
    const inNy = clipToLocalDays([iv], NY, false);
    const inJnb = clipToLocalDays([iv], JNB, false);
    expect(inNy).not.toEqual(inJnb);
  });

  it('sequential clipping is what strips a window outside either partner s day', () => {
    // 05:00–06:00 UTC = 01:00–02:00 in New York (asleep) but 07:00–08:00 in Johannesburg (awake).
    const iv = { start: Date.parse('2024-06-05T05:00:00Z'), end: Date.parse('2024-06-05T06:00:00Z') };
    expect(clipToLocalDays([iv], JNB, false)).toEqual([iv]);
    expect(clipToLocalDays(clipToLocalDays([iv], JNB, false), NY, false)).toEqual([]);
  });
});
