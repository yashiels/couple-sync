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
 * What the Free time screen actually renders: windows that have not finished yet, then the
 * display-only duration filter (§0.7 — it never changes what the server computes; the 30-minute
 * minimum is the engine's and is hard-coded there).
 *
 * A window whose `endUtc` is already past is expected, not exceptional: `overlaps_latest` is only
 * recomputed when its input hash changes, so the stored row lags the clock (§9).
 *
 * Score order is preserved deliberately — that is what surfaces the good windows first. Anything
 * showing "next" runs the result through `earliestWindow` instead of reading index 0.
 */
export function visibleWindows<T extends Pick<OverlapWindow, 'endUtc' | 'durationMinutes'>>(
  windows: readonly T[],
  now: number,
  minMinutes: number,
): T[] {
  return windows.filter((w) => w.endUtc > now && w.durationMinutes >= minMinutes);
}

/**
 * Page 0 of the Calendar tab's week pager: Monday 1 January 2024, held as a calendar date rather
 * than an instant. Fixed rather than relative to "now" so a page index means the same week on every
 * launch — anchoring on "the Monday of this week" would renumber every page at local midnight and
 * make a stored index meaningless.
 */
const EPOCH_MONDAY = { year: 2024, month: 1, day: 1 } as const;

function anchor(zone: string): DateTime {
  return DateTime.fromObject(EPOCH_MONDAY, { zone });
}

/** The page index of the week containing `at`, in the viewer's zone. Negative before 2024. */
export function weekIndex(at: number, zone: string): number {
  const days = DateTime.fromMillis(at, { zone }).startOf('day').diff(anchor(zone), 'days').days;
  return Math.floor(Math.round(days) / 7);
}

/** Local Monday 00:00 of a page, as epoch ms. */
export function weekStart(index: number, zone: string): number {
  // plus({ weeks }) walks calendar weeks and keeps the local wall clock at 00:00, so a DST week is
  // still exactly one page. Adding 7 * 86_400_000 would drift an hour twice a year.
  return anchor(zone).plus({ weeks: index }).toMillis();
}

/**
 * The `GET /blocks?from=&to=` range for a page: local Monday 00:00 up to the *next* local Monday
 * 00:00, which is 167 or 169 hours in a DST week. This is also what goes into `visibleRange`, which
 * `src/ws.ts` reads to know what to refetch when the partner changes something.
 */
export function weekRange(index: number, zone: string): { from: number; to: number } {
  return { from: weekStart(index, zone), to: weekStart(index + 1, zone) };
}

/** The block form's start/end rows: the stored instant as wall clock in the block's own zone. */
export function formatLocalDateTime(at: number, zone: string): string {
  return DateTime.fromMillis(at, { zone }).toFormat(`${DAY} yyyy, ${TIME}`);
}

/**
 * The two halves of the block form's date/time picker, and the only reason they are not one line each
 * in the screen: the Android pickers speak *device* wall clock. They read `value`'s local fields and
 * hand back a timestamp built from the fields the user chose, both in the device's zone
 * (`DatePickerModule.java:64`, `TimePickerModule.java:65`). A block, meanwhile, is authored in its own
 * zone — the one the server anchors recurrence to (§0.3) — which on an edit is the block's stored
 * `timezone` and not the phone's.
 *
 * So both directions swap the zone while holding the wall clock still: a 19:00 Berlin block opens the
 * picker showing 19:00 on a phone in Chicago, and saving it writes 19:00 Berlin rather than 19:00
 * Chicago. A same-zone device makes both functions a no-op, which is exactly why this needs a test
 * rather than a look at the screen.
 *
 * 'default' is luxon's `Settings.defaultZone` — the device zone on a phone, and what a test overrides
 * to stand in for a phone somewhere else.
 *
 * Ceiling: a wall clock that does not exist on the target side of the swap (the hour a DST spring
 * forward skips) is moved forward by the gap, because that is what luxon does with an impossible local
 * time. The alternative is refusing the pick, and a form that rejects 02:30 without being able to say
 * why is worse than one that saves 03:30.
 */
export function toPickerDate(at: number, zone: string): Date {
  return DateTime.fromMillis(at, { zone }).setZone('default', { keepLocalTime: true }).toJSDate();
}

export function fromPickerDate(picked: Date, zone: string): number {
  return DateTime.fromJSDate(picked).setZone(zone, { keepLocalTime: true }).toMillis();
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
