import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { computeInputHash } from './hash.js';
import { ALGO_VERSION, type Block, type OverlapInput } from './types.js';

const HOUR = 3_600_000;
const NOW = Date.parse('2024-06-05T10:00:00Z');

function block(over: Partial<Block> = {}): Block {
  return {
    userId: 'a',
    type: 'busy',
    startUtc: NOW + HOUR,
    endUtc: NOW + 2 * HOUR,
    timezone: 'UTC',
    recurrenceRule: null,
    ...over,
  };
}

function input(over: Partial<OverlapInput> = {}): OverlapInput {
  return {
    blocksA: [block()],
    blocksB: [block({ userId: 'b', startUtc: NOW + 5 * HOUR, endUtc: NOW + 6 * HOUR })],
    timezoneA: 'America/New_York',
    timezoneB: 'Africa/Johannesburg',
    prefsA: { showLateNightWindows: false },
    prefsB: { showLateNightWindows: false },
    now: NOW,
    ...over,
  };
}

describe('computeInputHash — shape', () => {
  it('is 16 lowercase hex chars', () => {
    expect(computeInputHash(input())).toMatch(/^[0-9a-f]{16}$/);
  });

  it('matches the documented canonical string, so ALGO_VERSION and the hour bucket are in it', () => {
    const i = input({ blocksA: [block()], blocksB: [] });
    const canonical = [
      ALGO_VERSION,
      Math.floor(NOW / HOUR),
      'America/New_York',
      'Africa/Johannesburg',
      false,
      false,
      `${NOW + HOUR}:${NOW + 2 * HOUR}::busy:UTC`,
      '',
    ].join('|');
    expect(computeInputHash(i)).toBe(createHash('sha256').update(canonical).digest('hex').slice(0, 16));
  });
});

describe('computeInputHash — order independence and purity', () => {
  const blocks = [
    block({ startUtc: NOW + 3 * HOUR, endUtc: NOW + 4 * HOUR }),
    block({ startUtc: NOW + HOUR, endUtc: NOW + 2 * HOUR }),
    block({ startUtc: NOW + 2 * HOUR, endUtc: NOW + 3 * HOUR, type: 'tentative' }),
  ];

  it('ignores the caller s array order', () => {
    const forward = computeInputHash(input({ blocksA: blocks }));
    const reversed = computeInputHash(input({ blocksA: [...blocks].reverse() }));
    const shuffled = computeInputHash(input({ blocksA: [blocks[1]!, blocks[2]!, blocks[0]!] }));
    expect(reversed).toBe(forward);
    expect(shuffled).toBe(forward);
  });

  it('disambiguates blocks that share a startUtc', () => {
    const same = [
      block({ startUtc: NOW, endUtc: NOW + HOUR }),
      block({ startUtc: NOW, endUtc: NOW + 2 * HOUR }),
    ];
    expect(computeInputHash(input({ blocksA: same }))).toBe(
      computeInputHash(input({ blocksA: [...same].reverse() })),
    );
  });

  it('does not sort startUtc as a string (900 before 1000)', () => {
    const a = block({ startUtc: 900, endUtc: 1000 });
    const b = block({ startUtc: 1000, endUtc: 2000 });
    expect(computeInputHash(input({ blocksA: [a, b] }))).toBe(computeInputHash(input({ blocksA: [b, a] })));
  });

  it('does not mutate the input arrays', () => {
    const arr = [...blocks];
    const before = JSON.stringify(arr);
    computeInputHash(input({ blocksA: arr }));
    expect(JSON.stringify(arr)).toBe(before);
  });

  it('keeps A s and B s blocks distinct — swapping partners changes the hash', () => {
    const a = [block({ startUtc: NOW + HOUR, endUtc: NOW + 2 * HOUR })];
    const b = [block({ startUtc: NOW + 8 * HOUR, endUtc: NOW + 9 * HOUR })];
    expect(computeInputHash(input({ blocksA: a, blocksB: b }))).not.toBe(
      computeInputHash(input({ blocksA: b, blocksB: a })),
    );
  });
});

describe('computeInputHash — sensitivity', () => {
  const base = computeInputHash(input());
  const differs = (over: Partial<OverlapInput>) => expect(computeInputHash(input(over))).not.toBe(base);

  it('changes with timezoneA', () => differs({ timezoneA: 'Europe/London' }));
  it('changes with timezoneB', () => differs({ timezoneB: 'Europe/London' }));
  it('changes with prefsA', () => differs({ prefsA: { showLateNightWindows: true } }));
  it('changes with prefsB', () => differs({ prefsB: { showLateNightWindows: true } }));
  it('changes with a block startUtc', () => differs({ blocksA: [block({ startUtc: NOW + 7 * HOUR })] }));
  it('changes with a block endUtc', () => differs({ blocksA: [block({ endUtc: NOW + 9 * HOUR })] }));
  it('changes with a block recurrenceRule', () => differs({ blocksA: [block({ recurrenceRule: 'FREQ=DAILY' })] }));
  it('changes with a block type', () => differs({ blocksA: [block({ type: 'tentative' })] }));
  it('changes with a block timezone', () => differs({ blocksA: [block({ timezone: 'Europe/London' })] }));
  it('changes when a block is added or removed', () => {
    differs({ blocksA: [] });
    differs({ blocksA: [block(), block({ startUtc: NOW + 20 * HOUR, endUtc: NOW + 21 * HOUR })] });
  });

  it('ignores userId — it cannot change the computed windows', () => {
    expect(computeInputHash(input({ blocksA: [block({ userId: 'someone-else' })] }))).toBe(base);
  });

  it('distinguishes a null rrule from an empty-string rrule only via the rule text', () => {
    // Both serialise the recurrence slot as '' — deliberate: an empty rule is not a recurrence.
    expect(computeInputHash(input({ blocksA: [block({ recurrenceRule: '' })] }))).toBe(base);
  });
});

describe('computeInputHash — hour bucketing', () => {
  it('is stable anywhere inside the same hour', () => {
    const h = computeInputHash(input({ now: NOW }));
    expect(computeInputHash(input({ now: NOW + 1 }))).toBe(h);
    expect(computeInputHash(input({ now: NOW + 30 * 60_000 }))).toBe(h);
    expect(computeInputHash(input({ now: NOW + HOUR - 1 }))).toBe(h);
  });

  it('changes across a bucket boundary', () => {
    expect(computeInputHash(input({ now: NOW + HOUR }))).not.toBe(computeInputHash(input({ now: NOW })));
    expect(computeInputHash(input({ now: NOW - 1 }))).not.toBe(computeInputHash(input({ now: NOW })));
  });
});
