import { DateTime } from 'luxon';
// Default-import then destructure. `rrule` is CJS with no `exports` map, so a named ESM import
// resolves under tsc and vitest (they read the `module` field) but throws
// "does not provide an export named 'RRule'" under plain `node dist/...`. That made the built
// container unbootable while every test stayed green. boot-esm.test.ts guards this.
import rrulePkg from 'rrule';
import type { Interval } from './intervals.js';
import type { Block } from './types.js';

const { RRule } = rrulePkg;

// ---------------------------------------------------------------------------
// Why the "wall clock space" dance below exists.
//
// rrule.js has no timezone model — it treats every Date's UTC fields as the recurrence's local
// fields. So we do the whole expansion in a synthetic space where a Date's *UTC* fields hold the
// block's *local* wall-clock fields, then map each occurrence back through the block's IANA zone to
// a real instant.
//
// That is what keeps a weekly 09:00-local block at 09:00 local after a DST transition (its UTC
// instant shifts by an hour, which is correct). Expanding `new Date(block.startUtc)` directly is the
// bug the old Dart implementation shipped: every occurrence after a transition drifted an hour.
// Do not "simplify" this away.
// ---------------------------------------------------------------------------

/** Real instant -> synthetic instant whose UTC fields are the wall clock in `zone`. */
function toWallClock(epochMs: number, zone: string): number {
  const l = DateTime.fromMillis(epochMs, { zone });
  return Date.UTC(l.year, l.month - 1, l.day, l.hour, l.minute, l.second, l.millisecond);
}

/** Synthetic instant -> the real instant that shows that wall clock in `zone`. */
function fromWallClock(wallMs: number, zone: string): number {
  const d = new Date(wallMs);
  return DateTime.fromObject(
    {
      year: d.getUTCFullYear(),
      month: d.getUTCMonth() + 1,
      day: d.getUTCDate(),
      hour: d.getUTCHours(),
      minute: d.getUTCMinutes(),
      second: d.getUTCSeconds(),
      millisecond: d.getUTCMilliseconds(),
    },
    { zone },
  ).toMillis();
  // A wall clock inside a spring-forward gap (02:30 on 2024-03-10 in New York) does not exist;
  // luxon resolves it forward to 03:30. Good enough — an occurrence never vanishes.
}

/**
 * All instances of `block` that intersect [windowStart, windowEnd), clamped to it.
 * Duration is fixed at `endUtc - startUtc` and reused for every instance (spec §2).
 */
export function expandBlock(block: Block, windowStart: number, windowEnd: number): Interval[] {
  const duration = block.endUtc - block.startUtc;
  if (duration <= 0) return [];

  if (!block.recurrenceRule) {
    const start = Math.max(block.startUtc, windowStart);
    const end = Math.min(block.endUtc, windowEnd);
    return start < end ? [{ start, end }] : [];
  }

  const zone = block.timezone;
  const rule = new RRule({
    // `UNTIL` is read as a wall clock in `zone` rather than as the RFC 5545 UTC instant, because it
    // rides the same synthetic space. Off by at most one zone offset; fine for a 14-day horizon.
    ...RRule.parseString(block.recurrenceRule.replace(/^RRULE:/i, '')),
    dtstart: new Date(toWallClock(block.startUtc, zone)),
  });

  // Look back one duration so an instance that starts before the horizon but bleeds into it is still
  // found (spec §3.2). The extra hour absorbs DST offset wobble; real bounds are re-checked below.
  const lo = toWallClock(windowStart, zone) - duration - 3_600_000;
  const hi = toWallClock(windowEnd, zone) + 3_600_000;

  // Ceiling: rrule iterates from DTSTART, so a daily rule whose DTSTART is years in the past costs
  // one internal step per skipped day. Fine for calendar-sourced and hand-entered blocks; if it ever
  // matters, roll DTSTART forward to the last occurrence before `lo` before building the rule.
  const out: Interval[] = [];
  for (const occ of rule.between(new Date(lo), new Date(hi), true)) {
    const start = fromWallClock(occ.getTime(), zone);
    if (start >= windowEnd) break; // ascending wall clock maps to ascending instants
    const end = start + duration;
    if (end <= windowStart) continue;
    out.push({ start: Math.max(start, windowStart), end: Math.min(end, windowEnd) });
  }
  return out;
}
