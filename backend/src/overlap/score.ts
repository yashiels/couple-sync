import { DateTime } from 'luxon';
import type { Interval } from './intervals.js';
import type { OverlapWindow } from './types.js';

/**
 * Spec §3.9. Anchored on the window *start* and on partner A's timezone only — asymmetric by
 * design, so swapping A and B can legitimately change the scores.
 *
 * `nowFloor` is already floored to the hour by the pipeline; scoring must use the same value the
 * hash does or the "stable within an hour" guarantee breaks.
 */
export function scoreWindow(
  iv: Interval,
  timezoneA: string,
  nowFloor: number,
  reasonableBoth: boolean,
): OverlapWindow {
  const durationHours = (iv.end - iv.start) / 3_600_000;
  const base = Math.log2(durationHours + 1) * 10;

  const localA = DateTime.fromMillis(iv.start, { zone: timezoneA });
  const eveningBonus = localA.hour >= 18 && localA.hour < 21 ? 5 : 0;
  const weekendBonus = localA.weekday >= 6 ? 5 : 0; // luxon weekday: 1=Mon … 6=Sat, 7=Sun

  const daysFromNow = (iv.start - nowFloor) / 86_400_000; // fractional, not whole days
  const timeDecay = Math.max(0, 10 - daysFromNow * 0.5);

  return {
    startUtc: iv.start,
    endUtc: iv.end,
    durationMinutes: Math.round((iv.end - iv.start) / 60_000),
    score: base + eveningBonus + weekendBonus + timeDecay,
    reasonableBoth,
  };
}

/** Best score first; equal scores fall back to the earlier window (spec §3.11). */
export function compareWindows(a: OverlapWindow, b: OverlapWindow): number {
  return b.score - a.score || a.startUtc - b.startUtc;
}
