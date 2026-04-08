import { createHash } from 'crypto';
import { DateTime } from 'luxon';
import { RRule } from 'rrule';
import { OverlapResult, OverlapWindow, TimeBlock } from './types';

// ─── Interval utilities ───────────────────────────────────────────────────────

export function mergeIntervals(
  intervals: Array<[number, number]>
): Array<[number, number]> {
  if (intervals.length === 0) return [];
  const sorted = [...intervals].sort((a, b) => a[0] - b[0]);
  const result: Array<[number, number]> = [[...sorted[0]]];
  for (let i = 1; i < sorted.length; i++) {
    const last = result[result.length - 1];
    if (sorted[i][0] <= last[1]) {
      last[1] = Math.max(last[1], sorted[i][1]);
    } else {
      result.push([...sorted[i]]);
    }
  }
  return result;
}

export function intersectIntervals(
  a: Array<[number, number]>,
  b: Array<[number, number]>
): Array<[number, number]> {
  const result: Array<[number, number]> = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const start = Math.max(a[i][0], b[j][0]);
    const end = Math.min(a[i][1], b[j][1]);
    if (start < end) result.push([start, end]);
    if (a[i][1] < b[j][1]) i++;
    else j++;
  }
  return result;
}

// ─── Block expansion ──────────────────────────────────────────────────────────

export function expandBlock(
  block: TimeBlock,
  windowStart: number,
  windowEnd: number
): Array<[number, number]> {
  const duration = block.endUtc - block.startUtc;

  if (!block.recurrenceRule) {
    if (block.endUtc <= windowStart || block.startUtc >= windowEnd) return [];
    return [[Math.max(block.startUtc, windowStart), Math.min(block.endUtc, windowEnd)]];
  }

  const ruleStr = block.recurrenceRule.startsWith('RRULE:')
    ? block.recurrenceRule.slice(6)
    : block.recurrenceRule;

  const rule = new RRule({
    ...RRule.parseString(ruleStr),
    dtstart: new Date(block.startUtc),
  });

  // Look back by one duration so occurrences starting just before the window
  // that extend into it are included.
  const occurrences = rule.between(
    new Date(windowStart - duration),
    new Date(windowEnd),
    true
  );

  return occurrences
    .map((occ) => [occ.getTime(), occ.getTime() + duration] as [number, number])
    .filter(([s, e]) => e > windowStart && s < windowEnd)
    .map(([s, e]) => [Math.max(s, windowStart), Math.min(e, windowEnd)] as [number, number]);
}

// ─── Free interval computation ────────────────────────────────────────────────

export function computeFreeIntervals(
  blocks: TimeBlock[],
  windowStart: number,
  windowEnd: number
): Array<[number, number]> {
  const busy = mergeIntervals(
    blocks
      .filter((b) => b.type === 'busy' || b.type === 'tentative')
      .flatMap((b) => expandBlock(b, windowStart, windowEnd))
  );

  const free: Array<[number, number]> = [];
  let cursor = windowStart;
  for (const [busyStart, busyEnd] of busy) {
    if (cursor < busyStart) free.push([cursor, busyStart]);
    cursor = Math.max(cursor, busyEnd);
  }
  if (cursor < windowEnd) free.push([cursor, windowEnd]);
  return free;
}

// ─── Waking-hours clipping ────────────────────────────────────────────────────

const WAKE_HOUR = 7;
const SLEEP_HOUR = 23; // 11 pm

export function clipIntervalToWakingHours(
  start: number,
  end: number,
  timezone: string,
  wakeHour = WAKE_HOUR,
  sleepHour = SLEEP_HOUR
): Array<[number, number]> {
  const result: Array<[number, number]> = [];
  let dayStart = DateTime.fromMillis(start, { zone: timezone }).startOf('day');

  while (dayStart.toMillis() < end) {
    const wakeMs = dayStart.set({ hour: wakeHour }).toMillis();
    const sleepMs = dayStart.set({ hour: sleepHour }).toMillis();
    const clipStart = Math.max(start, wakeMs);
    const clipEnd = Math.min(end, sleepMs);
    if (clipStart < clipEnd) result.push([clipStart, clipEnd]);
    dayStart = dayStart.plus({ days: 1 });
  }
  return result;
}

export function clipToWakingHours(
  intervals: Array<[number, number]>,
  timezone: string
): Array<[number, number]> {
  return intervals.flatMap(([s, e]) => clipIntervalToWakingHours(s, e, timezone));
}

// ─── Scoring ──────────────────────────────────────────────────────────────────

export function scoreWindow(
  startUtc: number,
  endUtc: number,
  timezoneA: string,
  _timezoneB: string,
  now = Date.now()
): number {
  const durationHours = (endUtc - startUtc) / (60 * 60 * 1000);
  const base = Math.log2(durationHours + 1) * 10;

  const localA = DateTime.fromMillis(startUtc, { zone: timezoneA });
  const eveningBonus = localA.hour >= 18 && localA.hour < 21 ? 5 : 0;
  const weekendBonus = localA.weekday >= 6 ? 5 : 0; // 6=Sat, 7=Sun in Luxon

  const daysFromNow = (startUtc - now) / (24 * 60 * 60 * 1000);
  const timeDecay = Math.max(0, 10 - daysFromNow * 0.5);

  return base + eveningBonus + weekendBonus + timeDecay;
}

// ─── Block hash ───────────────────────────────────────────────────────────────

export function computeBlockHash(blocks: TimeBlock[]): string {
  const sorted = [...blocks].sort((a, b) => a.startUtc - b.startUtc);
  const str = sorted
    .map((b) => `${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type}`)
    .join('|');
  return createHash('sha256').update(str).digest('hex').slice(0, 16);
}

// ─── Main overlap computation ─────────────────────────────────────────────────

const HORIZON_DAYS = 14;
const MIN_WINDOW_MINUTES = 30;
const MAX_WINDOWS = 20;

export function computeOverlap(
  blocksA: TimeBlock[],
  blocksB: TimeBlock[],
  timezoneA: string,
  timezoneB: string,
  now = Date.now()
): OverlapWindow[] {
  const windowEnd = now + HORIZON_DAYS * 24 * 60 * 60 * 1000;

  const freeA = computeFreeIntervals(blocksA, now, windowEnd);
  const freeB = computeFreeIntervals(blocksB, now, windowEnd);

  // Intersect, then clip to waking hours in both timezones
  const overlap = intersectIntervals(freeA, freeB);
  const clipped = clipToWakingHours(clipToWakingHours(overlap, timezoneA), timezoneB);

  const windows: OverlapWindow[] = clipped
    .map(([s, e]) => ({
      startUtc: s,
      endUtc: e,
      durationMinutes: Math.round((e - s) / 60_000),
      score: scoreWindow(s, e, timezoneA, timezoneB, now),
      reasonableBoth: true,
    }))
    .filter((w) => w.durationMinutes >= MIN_WINDOW_MINUTES);

  return windows.sort((a, b) => b.score - a.score).slice(0, MAX_WINDOWS);
}

// Re-export for convenience
export type { OverlapResult, OverlapWindow };
