import { clipToLocalDays } from './clip.js';
import { type Interval, intersect, invert, merge } from './intervals.js';
import { expandBlock } from './recurrence.js';
import { compareWindows, scoreWindow } from './score.js';
import {
  HORIZON_DAYS,
  MAX_WINDOWS,
  MIN_WINDOW_MINUTES,
  type Block,
  type OverlapInput,
  type OverlapWindow,
} from './types.js';

export { ALGO_VERSION, HORIZON_DAYS, MAX_WINDOWS, MIN_WINDOW_MINUTES, SLEEP_HOUR, WAKE_HOUR } from './types.js';
export type { Block, OverlapInput, OverlapWindow, Prefs } from './types.js';
export { computeInputHash } from './hash.js';

/** Free time for one partner inside the horizon: expand → drop `free` → merge → invert. */
function freeTime(blocks: Block[], windowStart: number, windowEnd: number): Interval[] {
  const busy: Interval[] = [];
  for (const b of blocks) {
    // `free` blocks are dropped entirely (spec §3.3) — they are annotations, not availability.
    // `tentative` counts as busy.
    if (b.type === 'free') continue;
    busy.push(...expandBlock(b, windowStart, windowEnd));
  }
  return invert(merge(busy), windowStart, windowEnd);
}

/** Never mutates `input`. Deterministic for a given input. */
export function computeOverlap(input: OverlapInput): OverlapWindow[] {
  // Floor `now` to the hour so results are stable for an hour and computeInputHash is a usable cache
  // key. The scoring decay uses this same floored value.
  const now = Math.floor(input.now / 3_600_000) * 3_600_000;
  const windowStart = now;
  // The only place fixed-ms day math is correct: the horizon is defined as a 14×24h span (§3.1), not
  // as 14 calendar days. Everything downstream that walks *days* goes through luxon.
  const windowEnd = now + HORIZON_DAYS * 86_400_000;

  let windows = intersect(
    freeTime(input.blocksA, windowStart, windowEnd),
    freeTime(input.blocksB, windowStart, windowEnd),
  );

  // Sequential, A then B: a window survives only if it fits inside both partners' local days.
  windows = clipToLocalDays(windows, input.timezoneA, input.prefsA.showLateNightWindows);
  windows = clipToLocalDays(windows, input.timezoneB, input.prefsB.showLateNightWindows);

  // Couple-level, not per-window (spec §3.9).
  const reasonableBoth = !input.prefsA.showLateNightWindows && !input.prefsB.showLateNightWindows;

  return windows
    .map((iv) => scoreWindow(iv, input.timezoneA, now, reasonableBoth))
    // The min-duration filter runs after scoring, on the *rounded* durationMinutes (spec §3.10).
    .filter((w) => w.durationMinutes >= MIN_WINDOW_MINUTES)
    .sort(compareWindows)
    .slice(0, MAX_WINDOWS);
}
