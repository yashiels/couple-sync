import { DateTime } from 'luxon';
import { describe, expect, it } from 'vitest';

import type { OverlapWindow } from '../../backend/src/wire';
import {
  earliestWindow,
  formatClock,
  formatCountdown,
  formatDuration,
  formatLocalInput,
  formatWindowRange,
  gridPosition,
  parseLocalInput,
  visibleWindows,
  weekIndex,
  weekRange,
  weekStart,
} from '../time';

function window(startUtc: number, score: number): OverlapWindow {
  return { startUtc, endUtc: startUtc + 3_600_000, durationMinutes: 60, score, reasonableBoth: true };
}

describe('earliestWindow', () => {
  it('picks the earliest start, NOT windows[0] — the list is score-sorted', () => {
    const later = window(Date.UTC(2026, 7, 9, 18), 90); // best score, three days out
    const sooner = window(Date.UTC(2026, 7, 6, 20), 40);
    // Score order, exactly as the engine returns it.
    expect(earliestWindow([later, sooner])).toBe(sooner);
  });

  it('returns null for an empty list', () => {
    expect(earliestWindow([])).toBeNull();
  });
});

describe('visibleWindows', () => {
  const now = Date.UTC(2026, 7, 4, 12);
  const sized = (startUtc: number, minutes: number, score: number): OverlapWindow => ({
    startUtc,
    endUtc: startUtc + minutes * 60_000,
    durationMinutes: minutes,
    score,
    reasonableBoth: true,
  });

  it('drops a window that has already ended — the stored row lags the clock', () => {
    const finished = sized(now - 3 * 3_600_000, 60, 50);
    const upcoming = sized(now + 3_600_000, 60, 20);
    expect(visibleWindows([finished, upcoming], now, 0)).toEqual([upcoming]);
  });

  it('keeps a window that is under way but not over', () => {
    const running = sized(now - 30 * 60_000, 120, 30);
    expect(visibleWindows([running], now, 0)).toEqual([running]);
  });

  it('filters on the duration the engine reported, inclusive of the bound', () => {
    const half = sized(now + 3_600_000, 30, 10);
    const hour = sized(now + 7_200_000, 60, 10);
    const two = sized(now + 10_800_000, 120, 10);
    expect(visibleWindows([half, hour, two], now, 60)).toEqual([hour, two]);
    expect(visibleWindows([half, hour, two], now, 120)).toEqual([two]);
    expect(visibleWindows([half, hour, two], now, 0)).toEqual([half, hour, two]);
  });

  it('keeps score order rather than re-sorting by time', () => {
    const best = sized(now + 5 * 86_400_000, 180, 90);
    const soonest = sized(now + 3_600_000, 60, 20);
    expect(visibleWindows([best, soonest], now, 0)).toEqual([best, soonest]);
  });

  it('the countdown target is the earliest visible start, never the first element', () => {
    // Exactly the shape the server sends: score descending, so the best window is days out. Reading
    // index 0 here is the bug that shipped in the FCM notification body.
    const ended = sized(now - 86_400_000, 240, 99);
    const best = sized(now + 5 * 86_400_000, 180, 90);
    const soonestButShort = sized(now + 3_600_000, 30, 25);
    const soonestLongEnough = sized(now + 2 * 3_600_000, 60, 22);
    const list = [ended, best, soonestButShort, soonestLongEnough];

    expect(earliestWindow(visibleWindows(list, now, 0))).toBe(soonestButShort);
    // With the display-only filter on, the countdown follows what is actually on screen.
    expect(earliestWindow(visibleWindows(list, now, 60))).toBe(soonestLongEnough);
  });
});

describe('formatting', () => {
  it('renders a window in the viewer zone, dropping the repeated day', () => {
    const start = Date.UTC(2026, 7, 4, 17, 0); // 19:00 in Berlin (CEST)
    expect(formatWindowRange({ startUtc: start, endUtc: start + 5_400_000 }, 'Europe/Berlin')).toBe(
      'Tue 4 Aug, 19:00 – 20:30',
    );
  });

  it('keeps the second day when the window crosses local midnight', () => {
    const start = Date.UTC(2026, 7, 4, 21, 30); // 23:30 in Berlin
    expect(formatWindowRange({ startUtc: start, endUtc: start + 3_600_000 }, 'Europe/Berlin')).toBe(
      'Tue 4 Aug, 23:30 – Wed 5 Aug, 00:30',
    );
  });

  it('renders the same instant differently in each partner zone', () => {
    const now = Date.UTC(2026, 7, 4, 17, 5);
    expect(formatClock('Europe/Berlin', now)).toBe('19:05');
    expect(formatClock('America/New_York', now)).toBe('13:05');
  });

  it('formats durations and countdowns without leaking milliseconds', () => {
    expect(formatDuration(150)).toBe('2h 30m');
    expect(formatDuration(45)).toBe('45m');
    expect(formatDuration(120)).toBe('2h');
    expect(formatCountdown(1_000_000, 1_000_000)).toBe('now');
    expect(formatCountdown(1_000_000, 999_000)).toBe('now'); // under a minute away
    expect(formatCountdown(10_000_000, 1_000_000)).toBe('in 2h 30m');
    expect(formatCountdown(1_000_000 + 3 * 86_400_000, 1_000_000)).toBe('in 3 days');
  });
});

describe('gridPosition', () => {
  const monday = Date.UTC(2026, 7, 3, 0, 0); // Mon 3 Aug 2026, 02:00 Berlin

  it('places an occurrence on its own day column at its local minute', () => {
    const start = Date.UTC(2026, 7, 5, 7, 15); // Wed 09:15 Berlin
    expect(gridPosition({ start_utc: start, end_utc: start + 2_700_000 }, 'Europe/Berlin', monday))
      .toEqual({ dayIndex: 2, topMinutes: 555, heightMinutes: 45 });
  });

  it('counts calendar days across a DST change, not 24h chunks', () => {
    // Europe/Berlin loses an hour on Sun 29 Mar 2026; Tuesday must still be dayIndex 2.
    const weekStart = Date.UTC(2026, 2, 22, 23, 0); // Mon 23 Mar 00:00 Berlin
    const tuesday = Date.UTC(2026, 2, 31, 8, 0); // Tue 31 Mar 10:00 Berlin (CEST)
    expect(
      gridPosition({ start_utc: tuesday, end_utc: tuesday + 3_600_000 }, 'Europe/Berlin', weekStart),
    ).toEqual({ dayIndex: 8, topMinutes: 600, heightMinutes: 60 });
  });
});

describe('week paging', () => {
  it('anchors page 0 on Monday 1 January 2024, not on the current week', () => {
    expect(weekStart(0, 'Europe/Berlin')).toBe(Date.UTC(2023, 11, 31, 23)); // 2024-01-01 00:00 CET
    expect(weekIndex(Date.UTC(2024, 0, 1, 12), 'Europe/Berlin')).toBe(0);
    // Sunday of page 0 is still page 0; the following Monday is page 1.
    expect(weekIndex(Date.UTC(2024, 0, 7, 12), 'Europe/Berlin')).toBe(0);
    expect(weekIndex(Date.UTC(2024, 0, 8, 12), 'Europe/Berlin')).toBe(1);
  });

  it('numbers weeks before the anchor negatively rather than clamping at 0', () => {
    expect(weekIndex(Date.UTC(2023, 11, 25, 12), 'Europe/Berlin')).toBe(-1);
    expect(weekStart(-1, 'Europe/Berlin')).toBe(Date.UTC(2023, 11, 24, 23));
  });

  it('is the same page index for every instant in the week, in the viewer zone', () => {
    const monday = Date.UTC(2026, 7, 3, 0); // Mon 3 Aug 2026
    const index = weekIndex(monday + 12 * 3_600_000, 'Europe/Berlin');
    for (let day = 0; day < 7; day += 1) {
      expect(weekIndex(monday + day * 86_400_000 + 12 * 3_600_000, 'Europe/Berlin')).toBe(index);
    }
  });

  it('reads the page in the viewer zone, so a late Sunday is a different page each side of the world', () => {
    // Sun 9 Aug 2026 22:30 UTC is Monday 10 Aug in Auckland but still Sunday in New York.
    const instant = Date.UTC(2026, 7, 9, 22, 30);
    expect(weekIndex(instant, 'Pacific/Auckland')).toBe(weekIndex(instant, 'America/New_York') + 1);
  });

  it('spans a spring-forward week with a 167-hour range, not 168', () => {
    // Europe/Berlin springs forward on Sun 29 Mar 2026: that week is one hour SHORT.
    const index = weekIndex(Date.UTC(2026, 2, 24, 12), 'Europe/Berlin');
    const { from, to } = weekRange(index, 'Europe/Berlin');
    expect(from).toBe(Date.UTC(2026, 2, 22, 23)); // Mon 23 Mar 00:00 CET
    expect(to).toBe(Date.UTC(2026, 2, 29, 22)); // Mon 30 Mar 00:00 CEST
    expect(to - from).toBe(167 * 3_600_000);
  });

  it('spans a fall-back week with a 169-hour range', () => {
    // Europe/Berlin falls back on Sun 25 Oct 2026.
    const index = weekIndex(Date.UTC(2026, 9, 20, 12), 'Europe/Berlin');
    const { from, to } = weekRange(index, 'Europe/Berlin');
    expect(to - from).toBe(169 * 3_600_000);
  });

  it('produces a range the server accepts: to > from and well under the 60-day cap', () => {
    const { from, to } = weekRange(weekIndex(Date.now(), 'Africa/Johannesburg'), 'Africa/Johannesburg');
    expect(to).toBeGreaterThan(from);
    expect(to - from).toBeLessThan(60 * 86_400_000);
  });

  it('every day of a DST week lands on its own column of the fetched range', () => {
    const index = weekIndex(Date.UTC(2026, 2, 24, 12), 'Europe/Berlin');
    const { from } = weekRange(index, 'Europe/Berlin');
    const seen = new Set<number>();
    for (let day = 0; day < 7; day += 1) {
      // 12:00 local on each day of the week, walked as calendar days.
      const noon = DateTime.fromMillis(from, { zone: 'Europe/Berlin' })
        .plus({ days: day })
        .set({ hour: 12 })
        .toMillis();
      seen.add(gridPosition({ start_utc: noon, end_utc: noon + 3_600_000 }, 'Europe/Berlin', from).dayIndex);
    }
    expect([...seen].sort((a, b) => a - b)).toEqual([0, 1, 2, 3, 4, 5, 6]);
  });
});

describe('local datetime input', () => {
  it('round-trips an instant through the form field in the block zone', () => {
    const at = Date.UTC(2026, 7, 4, 17, 30);
    expect(formatLocalInput(at, 'Europe/Berlin')).toBe('2026-08-04 19:30');
    expect(parseLocalInput('2026-08-04 19:30', 'Europe/Berlin')).toBe(at);
  });

  it('reads the same text as a different instant in a different zone', () => {
    expect(parseLocalInput('2026-08-04 19:30', 'America/New_York')).toBe(
      Date.UTC(2026, 7, 4, 23, 30),
    );
  });

  it('rejects text that is not a local datetime', () => {
    expect(parseLocalInput('', 'Europe/Berlin')).toBeNull();
    expect(parseLocalInput('tomorrow at 7', 'Europe/Berlin')).toBeNull();
    expect(parseLocalInput('2026-08-04', 'Europe/Berlin')).toBeNull();
    expect(parseLocalInput('2026-02-30 10:00', 'Europe/Berlin')).toBeNull();
    expect(parseLocalInput('2026-08-04 25:00', 'Europe/Berlin')).toBeNull();
  });

  it('tolerates surrounding whitespace, because a keyboard adds it', () => {
    expect(parseLocalInput('  2026-08-04 19:30 ', 'Europe/Berlin')).toBe(Date.UTC(2026, 7, 4, 17, 30));
  });
});

/**
 * The grid renders from the server's `occurrences` array and never from `recurrence_rule` — the app
 * has no `rrule` dependency (§0.6b). The occurrence values below were produced by the *backend's*
 * built expansion (`backend/dist/overlap/index.js`, `expandBlock`) for the stated block and range, so
 * these are the numbers a real `GET /blocks` sends. If the client ever tried to expand recurrence
 * itself, this is the contract it would be violating.
 */
describe('rendering a recurring block from server-supplied occurrences', () => {
  it('puts a weekly BYDAY=TU,WE block on the Tuesday and the Wednesday column', () => {
    const index = weekIndex(Date.UTC(2026, 7, 4, 12), 'Europe/Berlin');
    const { from, to } = weekRange(index, 'Europe/Berlin');
    expect([from, to]).toEqual([Date.UTC(2026, 7, 2, 22), Date.UTC(2026, 7, 9, 22)]);

    // expandBlock({ startUtc: 2026-08-04T07:00Z, endUtc: +1h, timezone: 'Europe/Berlin',
    //               recurrenceRule: 'FREQ=WEEKLY;BYDAY=TU,WE' }, from, to)
    const occurrences = [
      { start_utc: Date.UTC(2026, 7, 4, 7), end_utc: Date.UTC(2026, 7, 4, 8) },
      { start_utc: Date.UTC(2026, 7, 5, 7), end_utc: Date.UTC(2026, 7, 5, 8) },
    ];
    expect(occurrences.map((o) => gridPosition(o, 'Europe/Berlin', from))).toEqual([
      { dayIndex: 1, topMinutes: 540, heightMinutes: 60 },
      { dayIndex: 2, topMinutes: 540, heightMinutes: 60 },
    ]);
  });

  it('keeps a daily 09:00 block at 09:00 on every column of a spring-forward week', () => {
    const { from } = weekRange(weekIndex(Date.UTC(2026, 2, 24, 12), 'Europe/Berlin'), 'Europe/Berlin');
    // expandBlock of a FREQ=DAILY block starting Tue 24 Mar 09:00 Berlin: 09:00 local throughout,
    // which is 08:00Z before the 29 March transition and 07:00Z after it.
    const starts = [
      Date.UTC(2026, 2, 24, 8),
      Date.UTC(2026, 2, 25, 8),
      Date.UTC(2026, 2, 26, 8),
      Date.UTC(2026, 2, 27, 8),
      Date.UTC(2026, 2, 28, 8),
      Date.UTC(2026, 2, 29, 7),
    ];
    const placed = starts.map((start) =>
      gridPosition({ start_utc: start, end_utc: start + 3_600_000 }, 'Europe/Berlin', from),
    );
    expect(placed.map((p) => p.dayIndex)).toEqual([1, 2, 3, 4, 5, 6]);
    // The whole point of the DST axis: the rectangle does not slide an hour after the transition.
    expect(new Set(placed.map((p) => p.topMinutes))).toEqual(new Set([540]));
  });
});
