import { DateTime } from 'luxon';

import type { OverlapWindow } from '../backend/src/wire';

/**
 * Display helpers only. There is deliberately no interval algebra here — no merging, no
 * intersecting, no recurrence expansion (§0.1): the backend computes overlap and expands recurrence,
 * and the only arithmetic below turns an already-expanded interval into a rectangle.
 *
 * Note the two vocabularies: an OverlapWindow is the engine's computed type and stays camelCase,
 * while an occurrence is a row-shaped `{ start_utc, end_utc }`.
 */

const TIME = 'HH:mm';
const DAY = 'EEE d MMM';

/** "19:04" in the given zone. Callers tick this once a minute, never once a second. */
export function formatClock(zone: string, now: number = Date.now()): string {
  return DateTime.fromMillis(now, { zone }).toFormat(TIME);
}

/** "2h 30m", "45m". Minutes, because that is what the engine reports. */
export function formatDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes % 60);
  if (h === 0) return `${m}m`;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

/**
 * "Tue 5 Aug, 19:00 – 21:30", or "Tue 5 Aug, 23:30 – Wed 6 Aug, 00:30" when the window crosses
 * midnight in this zone — which it can, since a late-night window is a legitimate result.
 */
export function formatWindowRange(
  window: Pick<OverlapWindow, 'startUtc' | 'endUtc'>,
  zone: string,
): string {
  const start = DateTime.fromMillis(window.startUtc, { zone });
  const end = DateTime.fromMillis(window.endUtc, { zone });
  const sameDay = start.hasSame(end, 'day');
  return `${start.toFormat(`${DAY}, ${TIME}`)} – ${end.toFormat(sameDay ? TIME : `${DAY}, ${TIME}`)}`;
}

/** "in 3h 20m", "in 2 days", "now". Never a bare millisecond count. */
export function formatCountdown(targetUtc: number, now: number = Date.now()): string {
  const minutes = Math.floor((targetUtc - now) / 60_000);
  if (minutes <= 0) return 'now';
  if (minutes < 60 * 24) return `in ${formatDuration(minutes)}`;
  const days = Math.round(minutes / (60 * 24));
  return `in ${days} ${days === 1 ? 'day' : 'days'}`;
}

/**
 * The earliest-starting window, which is NOT `windows[0]`: the engine sorts by score descending, so
 * the first element is the *best* window and can be days away. Anything showing "next" comes through
 * here.
 */
export function earliestWindow<T extends Pick<OverlapWindow, 'startUtc'>>(
  windows: readonly T[],
): T | null {
  return windows.reduce<T | null>(
    (earliest, w) => (earliest === null || w.startUtc < earliest.startUtc ? w : earliest),
    null,
  );
}

/**
 * Where one server-expanded occurrence sits on a 7-column week grid, in the viewer's zone.
 * `dayIndex` is 0-6 from the week start's local day; `topMinutes` is minutes past local midnight.
 *
 * Ceiling: an occurrence spanning midnight returns a height that runs past the bottom of its column,
 * so the grid clips it. Splitting it into per-day rectangles is the upgrade path if that ever reads
 * badly; it is not interval algebra either way.
 */
export function gridPosition(
  occurrence: { start_utc: number; end_utc: number },
  zone: string,
  weekStartUtc: number,
): { dayIndex: number; topMinutes: number; heightMinutes: number } {
  const start = DateTime.fromMillis(occurrence.start_utc, { zone });
  const weekStart = DateTime.fromMillis(weekStartUtc, { zone }).startOf('day');
  return {
    // Calendar days, not 24h chunks: a DST week has a 23- and a 25-hour day and both are one column.
    dayIndex: Math.round(start.startOf('day').diff(weekStart, 'days').days),
    topMinutes: start.hour * 60 + start.minute,
    heightMinutes: Math.round((occurrence.end_utc - occurrence.start_utc) / 60_000),
  };
}
