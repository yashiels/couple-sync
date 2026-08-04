import { describe, expect, it } from 'vitest';

import type { OverlapWindow } from '../../backend/src/wire';
import {
  earliestWindow,
  formatClock,
  formatCountdown,
  formatDuration,
  formatWindowRange,
  gridPosition,
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
