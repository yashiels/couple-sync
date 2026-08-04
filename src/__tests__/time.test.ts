import { describe, expect, it } from 'vitest';

import type { OverlapWindow } from '../../backend/src/wire';
import {
  earliestWindow,
  formatClock,
  formatCountdown,
  formatDuration,
  formatWindowRange,
  gridPosition,
  visibleWindows,
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
