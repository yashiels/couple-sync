import { DateTime } from 'luxon';

/**
 * RRULE string building for a *write*, restricted to what `backend/src/routes/blocks.ts` accepts
 * (§3.2: `FREQ=DAILY|WEEKLY|MONTHLY|YEARLY` plus `INTERVAL`, `BYDAY`, `COUNT`, `UNTIL`). Anything
 * outside that is rejected at write time with `unsupported_recurrence_freq` or
 * `invalid_recurrence_rule` — an error the user cannot act on — so the picker must not be able to
 * express one.
 *
 * There is no `rrule` dependency here and there must never be one (§0.6b): the server expands
 * recurrence and ships the occurrences. This module builds and reads back a string; it never
 * enumerates instances.
 *
 * Only `FREQ` and `BYDAY` are emitted. `INTERVAL`, `COUNT` and `UNTIL` are legal server-side but the
 * picker has no control for them, and a value nothing can produce needs no builder. Adding "every 2
 * weeks" later is a second field here plus a chip in the picker.
 */

export const WEEKDAYS = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'] as const;
export type Weekday = (typeof WEEKDAYS)[number];

/** YEARLY is accepted by the server but not offered: nobody asked for it, so nothing emits it. */
export type Freq = 'DAILY' | 'WEEKLY' | 'MONTHLY';

export interface Recurrence {
  freq: Freq;
  /** Only meaningful for WEEKLY, and never empty there — the picker keeps at least one day on. */
  byday: Weekday[];
}

const LABEL: Record<Weekday, string> = {
  MO: 'Mon',
  TU: 'Tue',
  WE: 'Wed',
  TH: 'Thu',
  FR: 'Fri',
  SA: 'Sat',
  SU: 'Sun',
};

/** Written without the optional `RRULE:` prefix — the server strips it either way. */
export function buildRrule(recurrence: Recurrence): string {
  return recurrence.freq === 'WEEKLY' && recurrence.byday.length > 0
    ? `FREQ=WEEKLY;BYDAY=${recurrence.byday.join(',')}`
    : `FREQ=${recurrence.freq}`;
}

function isWeekday(value: string): value is Weekday {
  return (WEEKDAYS as readonly string[]).includes(value);
}

/**
 * Reads back only what `buildRrule` emits. Null for everything else — including rules the *server*
 * would happily accept, such as `FREQ=YEARLY` or an `INTERVAL` — so the picker shows "custom" rather
 * than silently rewriting a rule it cannot represent.
 */
export function parseRrule(rule: string | null): Recurrence | null {
  if (!rule?.trim()) return null;
  let freq: Freq | null = null;
  let byday: Weekday[] = [];

  for (const part of rule.trim().replace(/^RRULE:/i, '').split(';')) {
    if (!part) continue;
    const eq = part.indexOf('=');
    const key = part.slice(0, eq).toUpperCase();
    const value = part.slice(eq + 1).toUpperCase();
    if (key === 'FREQ') {
      if (value !== 'DAILY' && value !== 'WEEKLY' && value !== 'MONTHLY') return null;
      freq = value;
    } else if (key === 'BYDAY') {
      const days = value.split(',');
      if (!days.every(isWeekday)) return null;
      byday = days;
    } else {
      return null;
    }
  }
  return freq === null ? null : { freq, byday };
}

/** "Repeats weekly on Tue, Wed". Null when the block does not repeat. */
export function describeRrule(rule: string | null): string | null {
  if (!rule?.trim()) return null;
  const parsed = parseRrule(rule);
  if (!parsed) return 'Repeats on a custom schedule';
  if (parsed.freq === 'WEEKLY' && parsed.byday.length > 0) {
    return `Repeats weekly on ${parsed.byday.map((day) => LABEL[day]).join(', ')}`;
  }
  return `Repeats ${parsed.freq.toLowerCase()}`;
}

/** "Tue" for a weekday code, for a picker chip. */
export function weekdayLabel(day: Weekday): string {
  return LABEL[day];
}

/**
 * The RRULE weekday of an instant read in the block's own zone — 23:00 on a Monday in Berlin is a
 * Monday, even though it is already Tuesday in UTC, and the server anchors expansion to that same
 * zone (§0.3).
 */
export function weekdayCode(at: number, zone: string): Weekday {
  return WEEKDAYS[DateTime.fromMillis(at, { zone }).weekday - 1];
}
