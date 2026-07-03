import { describe, it, expect, beforeEach, vi } from 'vitest';

/**
 * V5 — overlap WS handler tests.
 *
 * Covers the three pure helpers (validateWindows, formatOverlapBody,
 * filterInvalidFcmTokens) plus handleOverlapMessage with mocked deps:
 *   - malformed windows → ignored (no persist, no push)
 *   - matching inputHash → deduped (no-op)
 *   - partner live → broadcast over WS (no FCM)
 *   - partner offline + has tokens → FCM push
 *   - invalid tokens pruned, transient kept
 *   - partner offline + no tokens → no-push
 *
 * No DB / Firebase / socket registry is touched — everything is injected.
 */

import {
  validateWindows,
  formatOverlapBody,
  filterInvalidFcmTokens,
  parseOverlapMessage,
  handleOverlapMessage,
  type OverlapWindow,
  type OverlapDeps,
} from '../overlap.js';

// ─── fixtures ──────────────────────────────────────────────────────────────

const T0 = Date.UTC(2026, 6, 2, 18, 0, 0); // 2026-07-02T18:00Z

/** A well-formed 1h window starting at T0. */
function win(overrides: Partial<OverlapWindow> = {}): OverlapWindow {
  const durationMinutes = 60;
  const startUtc = T0;
  const endUtc = startUtc + durationMinutes * 60_000;
  return {
    startUtc,
    endUtc,
    durationMinutes,
    score: 0.8,
    reasonableBoth: true,
    ...overrides,
  };
}

function makeDeps(overrides: Partial<OverlapDeps> = {}): OverlapDeps {
  return {
    getStoredInputHash: vi.fn(async () => null),
    upsertOverlap: vi.fn(async () => {}),
    getCouple: vi.fn(async () => ({
      userAUid: 'uid-alex',
      userBUid: 'uid-sam',
    })),
    getFcmTokens: vi.fn(async () => ['tok-a', 'tok-b']),
    sendFcm: vi.fn(async () => []),
    updateFcmTokens: vi.fn(async () => {}),
    isLive: vi.fn(() => false),
    sendToUid: vi.fn(() => true),
    log: { warn: vi.fn() },
    ...overrides,
  };
}

const MSG = {
  t: 'overlap' as const,
  coupleId: 'cpl-1',
  windows: [win()],
  inputHash: 'hash-1',
  computedBy: 'uid-alex',
};

// ─── validateWindows ───────────────────────────────────────────────────────

describe('validateWindows', () => {
  it('accepts a well-formed window', () => {
    const out = validateWindows([win()]);
    expect(out).toHaveLength(1);
    expect(out[0].startUtc).toBe(T0);
  });

  it('accepts multiple windows', () => {
    const out = validateWindows([
      win(),
      win({ startUtc: T0 + 3_600_000, endUtc: T0 + 4_200_000, durationMinutes: 10 }),
    ]);
    expect(out).toHaveLength(2);
  });

  it('rejects duration > 1560', () => {
    expect(() =>
      validateWindows([win({ durationMinutes: 1561, endUtc: T0 + 1561 * 60_000 })])
    ).toThrow(/durationMinutes out of bounds/);
  });

  it('rejects duration <= 0', () => {
    expect(() => validateWindows([win({ durationMinutes: 0, endUtc: T0 })])).toThrow(
      /durationMinutes out of bounds/
    );
  });

  it('rejects start >= end', () => {
    expect(() =>
      validateWindows([win({ startUtc: T0 + 1, endUtc: T0, durationMinutes: 60 })])
    ).toThrow(/startUtc must be/);
  });

  it('rejects non-integer startUtc', () => {
    expect(() => validateWindows([win({ startUtc: 1.5 } as any)])).toThrow(
      /invalid window shape/
    );
  });

  it('rejects non-integer durationMinutes', () => {
    expect(() => validateWindows([win({ durationMinutes: 1.5 } as any)])).toThrow(
      /invalid window shape/
    );
  });

  it('rejects non-finite score', () => {
    expect(() => validateWindows([win({ score: NaN } as any)])).toThrow(
      /invalid window shape/
    );
  });

  it('rejects wrong type for reasonableBoth', () => {
    expect(() => validateWindows([win({ reasonableBoth: 'yes' } as any)])).toThrow(
      /invalid window shape/
    );
  });

  it('rejects durationMinutes that does not match start/end', () => {
    // start=0, end=60000 (1min) but durationMinutes=2 → mismatch > 1000ms
    expect(() =>
      validateWindows([
        win({ startUtc: 0, endUtc: 60_000, durationMinutes: 120 }),
      ])
    ).toThrow(/durationMinutes does not match/);
  });

  it('rejects non-array input entries (wrong types)', () => {
    expect(() => validateWindows([{ startUtc: 'x' } as any])).toThrow(
      /invalid window shape/
    );
  });

  it('accepts boundary: durationMinutes=1560', () => {
    const out = validateWindows([
      win({ durationMinutes: 1560, endUtc: T0 + 1560 * 60_000 }),
    ]);
    expect(out).toHaveLength(1);
  });
});

// ─── formatOverlapBody ─────────────────────────────────────────────────────

describe('formatOverlapBody', () => {
  it('formats a 1h window as "1h free together on <EEE, MMM d>"', () => {
    // 2026-07-02T18:00Z → Thu, Jul 2
    const body = formatOverlapBody(win());
    expect(body).toBe('1h free together on Thu, Jul 2');
  });

  it('strips trailing .0 from whole-hour durations', () => {
    const body = formatOverlapBody(win({ durationMinutes: 120, endUtc: T0 + 120 * 60_000 }));
    expect(body.startsWith('2h free together on')).toBe(true);
  });

  it('keeps one decimal for fractional hours', () => {
    const body = formatOverlapBody(win({ durationMinutes: 90, endUtc: T0 + 90 * 60_000 }));
    expect(body.startsWith('1.5h free together on')).toBe(true);
  });
});

// ─── filterInvalidFcmTokens ────────────────────────────────────────────────

describe('filterInvalidFcmTokens', () => {
  it('returns empty when all succeed', () => {
    const out = filterInvalidFcmTokens(['a', 'b'], [
      { success: true },
      { success: true },
    ]);
    expect(out).toEqual([]);
  });

  it('prunes only hard-invalid codes', () => {
    const out = filterInvalidFcmTokens(['a', 'b', 'c'], [
      { success: false, error: { code: 'messaging/invalid-registration-token' } },
      { success: true },
      { success: false, error: { code: 'messaging/registration-token-not-registered' } },
    ]);
    expect(out).toEqual(['a', 'c']);
  });

  it('keeps tokens with transient errors', () => {
    const log = { warn: vi.fn() };
    const out = filterInvalidFcmTokens(
      ['a', 'b'],
      [
        { success: false, error: { code: 'messaging/quota-exceeded' } },
        { success: false, error: { code: 'messaging/internal-error' } },
      ],
      log
    );
    expect(out).toEqual([]);
    expect(log.warn).toHaveBeenCalledTimes(2);
  });

  it('handles missing error code', () => {
    const log = { warn: vi.fn() };
    const out = filterInvalidFcmTokens(
      ['a'],
      [{ success: false, error: undefined as any }],
      log
    );
    expect(out).toEqual([]);
    expect(log.warn).toHaveBeenCalledTimes(1);
  });
});

// ─── parseOverlapMessage ───────────────────────────────────────────────────

describe('parseOverlapMessage', () => {
  it('parses a well-formed envelope', () => {
    const m = parseOverlapMessage(MSG);
    expect(m).not.toBeNull();
    expect(m?.coupleId).toBe('cpl-1');
    expect(m?.inputHash).toBe('hash-1');
  });

  it('rejects non-overlap t', () => {
    expect(parseOverlapMessage({ t: 'block:set' })).toBeNull();
  });

  it('rejects missing coupleId', () => {
    expect(parseOverlapMessage({ t: 'overlap', windows: [], inputHash: 'h', computedBy: 'u' })).toBeNull();
  });

  it('rejects non-array windows', () => {
    expect(parseOverlapMessage({ t: 'overlap', coupleId: 'c', windows: {}, inputHash: 'h', computedBy: 'u' })).toBeNull();
  });
});

// ─── handleOverlapMessage ──────────────────────────────────────────────────

describe('handleOverlapMessage', () => {
  beforeEach(() => vi.clearAllMocks());

  it('returns "ignored" on malformed windows (no persist, no push)', async () => {
    const deps = makeDeps();
    const res = await handleOverlapMessage(
      { ...MSG, windows: [{ startUtc: 'x' }] as unknown[] },
      deps
    );
    expect(res).toBe('ignored');
    expect(deps.upsertOverlap).not.toHaveBeenCalled();
    expect(deps.sendFcm).not.toHaveBeenCalled();
    expect(deps.sendToUid).not.toHaveBeenCalled();
  });

  it('returns "deduped" when stored inputHash matches', async () => {
    const deps = makeDeps({
      getStoredInputHash: vi.fn(async () => 'hash-1'),
    });
    const res = await handleOverlapMessage(MSG, deps);
    expect(res).toBe('deduped');
    expect(deps.upsertOverlap).not.toHaveBeenCalled();
    expect(deps.sendFcm).not.toHaveBeenCalled();
    expect(deps.sendToUid).not.toHaveBeenCalled();
  });

  it('returns "broadcast" + forwards over WS when partner is live (no FCM)', async () => {
    const deps = makeDeps({ isLive: vi.fn(() => true) });
    const res = await handleOverlapMessage(MSG, deps);
    expect(res).toBe('broadcast');
    expect(deps.upsertOverlap).toHaveBeenCalledTimes(1);
    expect(deps.sendToUid).toHaveBeenCalledWith(
      'uid-sam',
      expect.objectContaining({ t: 'overlap', coupleId: 'cpl-1' })
    );
    expect(deps.sendFcm).not.toHaveBeenCalled();
  });

  it('returns "pushed" + sends FCM when partner is offline with tokens', async () => {
    const deps = makeDeps({ isLive: vi.fn(() => false) });
    const res = await handleOverlapMessage(MSG, deps);
    expect(res).toBe('pushed');
    expect(deps.getFcmTokens).toHaveBeenCalledWith('uid-sam');
    expect(deps.sendFcm).toHaveBeenCalledWith(
      ['tok-a', 'tok-b'],
      expect.objectContaining({
        title: 'You have free time together!',
        body: expect.stringContaining('free together on'),
      })
    );
    expect(deps.sendToUid).not.toHaveBeenCalled();
  });

  it('does not self-push the computedBy uid', async () => {
    // computedBy = uid-alex; partner should be uid-sam, never uid-alex.
    const deps = makeDeps({ isLive: vi.fn(() => false) });
    await handleOverlapMessage(MSG, deps);
    expect(deps.getFcmTokens).not.toHaveBeenCalledWith('uid-alex');
    expect(deps.getFcmTokens).toHaveBeenCalledWith('uid-sam');
  });

  it('prunes invalid tokens and persists the survivors', async () => {
    const deps = makeDeps({
      isLive: vi.fn(() => false),
      getFcmTokens: vi.fn(async () => ['good', 'bad']),
      sendFcm: vi.fn(async () => ['bad']),
    });
    const res = await handleOverlapMessage(MSG, deps);
    expect(res).toBe('pushed');
    expect(deps.updateFcmTokens).toHaveBeenCalledWith('uid-sam', ['good']);
  });

  it('keeps transient-error tokens (no prune)', async () => {
    const deps = makeDeps({
      isLive: vi.fn(() => false),
      getFcmTokens: vi.fn(async () => ['a', 'b']),
      sendFcm: vi.fn(async () => []), // none pruned
    });
    await handleOverlapMessage(MSG, deps);
    expect(deps.updateFcmTokens).not.toHaveBeenCalled();
  });

  it('returns "no-push" when partner is offline but has no FCM tokens', async () => {
    const deps = makeDeps({
      isLive: vi.fn(() => false),
      getFcmTokens: vi.fn(async () => []),
    });
    const res = await handleOverlapMessage(MSG, deps);
    expect(res).toBe('no-push');
    expect(deps.sendFcm).not.toHaveBeenCalled();
  });

  it('returns "no-push" when couple has vanished', async () => {
    const deps = makeDeps({
      getCouple: vi.fn(async () => null),
    });
    const res = await handleOverlapMessage(MSG, deps);
    expect(res).toBe('no-push');
    expect(deps.sendFcm).not.toHaveBeenCalled();
  });

  it('upserts overlap on the non-dedup path', async () => {
    const deps = makeDeps();
    await handleOverlapMessage(MSG, deps);
    expect(deps.upsertOverlap).toHaveBeenCalledWith(
      'cpl-1',
      expect.any(Array),
      expect.any(Number),
      'hash-1',
      'uid-alex'
    );
  });

  it('selects the earliest-starting window for the notification body', async () => {
    const later = win({
      startUtc: T0 + 7_200_000,
      endUtc: T0 + 7_800_000,
      durationMinutes: 10,
    });
    const deps = makeDeps({ isLive: vi.fn(() => false) });
    await handleOverlapMessage({ ...MSG, windows: [later, win()] }, deps);
    expect(deps.sendFcm).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ body: expect.stringContaining('Thu, Jul 2') })
    );
  });
});
