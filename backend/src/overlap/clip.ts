import { DateTime } from 'luxon';
import type { Interval } from './intervals.js';
import { SLEEP_HOUR, WAKE_HOUR } from './types.js';

/**
 * Split every interval on local calendar-day boundaries in `zone`.
 *
 * `showLateNight` true  -> split at local midnight only, keeping the whole day, so a multi-day
 *                          window renders as one window per day.
 * `showLateNight` false -> each daily segment is additionally bounded by WAKE_HOUR..SLEEP_HOUR
 *                          wall clock.
 *
 * The day walk is `.plus({ days: 1 })` on a zoned DateTime: a *calendar* increment. That is why a
 * fall-back day is 25 hours long and a spring-forward day 23, and why every later day boundary still
 * lands on local midnight. Never replace this with `+ 86_400_000` — after a DST transition that
 * silently shifts every subsequent boundary by an hour, and the bug is invisible in any test that
 * only uses UTC.
 */
export function clipToLocalDays(intervals: Interval[], zone: string, showLateNight: boolean): Interval[] {
  const out: Interval[] = [];
  for (const iv of intervals) {
    let day = DateTime.fromMillis(iv.start, { zone }).startOf('day');
    while (day.toMillis() < iv.end) {
      const next = day.plus({ days: 1 }).startOf('day');
      const lo = showLateNight ? day : day.set({ hour: WAKE_HOUR, minute: 0, second: 0, millisecond: 0 });
      const hi = showLateNight ? next : day.set({ hour: SLEEP_HOUR, minute: 0, second: 0, millisecond: 0 });
      const start = Math.max(iv.start, lo.toMillis());
      const end = Math.min(iv.end, hi.toMillis());
      if (start < end) out.push({ start, end });
      day = next;
    }
  }
  return out;
}
