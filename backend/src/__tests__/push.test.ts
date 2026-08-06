import type { BaseMessage } from 'firebase-admin/messaging';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { OverlapWindow } from '../wire.js';

vi.mock('../firebase.js', () => ({ sendEach: vi.fn() }));
vi.mock('../db.js', () => ({ query: vi.fn(async () => []) }));

const { sendEach } = await import('../firebase.js');
const { query } = await import('../db.js');
const { pushOverlapChanged } = await import('../push.js');

const JHB = 'Africa/Johannesburg'; // UTC+2, no DST
const NY = 'America/New_York'; // UTC-4 in June

/** 2026-06-03 18:00 UTC — 20:00 in Johannesburg, 14:00 in New York, same calendar day in both. */
const START = Date.parse('2026-06-03T18:00:00Z');
const HOUR = 3_600_000;

function win(startUtc: number, over: Partial<OverlapWindow> = {}): OverlapWindow {
  return { startUtc, endUtc: startUtc + HOUR, durationMinutes: 60, score: 50, reasonableBoth: true, ...over };
}

/** All tokens delivered. */
function allOk(tokens: string[]) {
  return tokens.map((token) => ({ token, errorCode: null }));
}

/** `codes` maps a token to the error code FCM returned for it. */
function withErrors(codes: Record<string, string>) {
  return (tokens: string[]) => tokens.map((token) => ({ token, errorCode: codes[token] ?? null }));
}

const payload = () => vi.mocked(sendEach).mock.calls[0]?.[1] as BaseMessage;
const body = () => (payload().notification?.body ?? '') as string;
/** The pruning UPDATE, or undefined when no write happened. */
const pruned = () => vi.mocked(query).mock.calls[0];

beforeEach(() => {
  vi.mocked(sendEach).mockReset();
  vi.mocked(query).mockReset();
  vi.mocked(sendEach).mockImplementation(async (tokens: string[]) => allOk(tokens));
  vi.mocked(query).mockResolvedValue([]);
});

describe('sending', () => {
  it('sends nothing when the user has no tokens', async () => {
    await pushOverlapChanged('u1', [], [win(START)], JHB);

    expect(sendEach).not.toHaveBeenCalled();
    expect(query).not.toHaveBeenCalled();
  });

  it('sends to every token the user has', async () => {
    await pushOverlapChanged('u1', ['t1', 't2', 't3'], [win(START)], JHB);

    expect(sendEach).toHaveBeenCalledTimes(1);
    expect(vi.mocked(sendEach).mock.calls[0]?.[0]).toEqual(['t1', 't2', 't3']);
  });
});

describe('token pruning', () => {
  it('prunes a token on messaging/invalid-registration-token', async () => {
    vi.mocked(sendEach).mockImplementation(async (t: string[]) =>
      withErrors({ t2: 'messaging/invalid-registration-token' })(t),
    );

    await pushOverlapChanged('u1', ['t1', 't2'], [win(START)], JHB);

    expect(pruned()?.[0]).toMatch(/UPDATE users/);
    expect(pruned()?.[1]).toEqual(['u1', ['t2']]);
  });

  it('prunes a token on messaging/registration-token-not-registered', async () => {
    vi.mocked(sendEach).mockImplementation(async (t: string[]) =>
      withErrors({ t1: 'messaging/registration-token-not-registered' })(t),
    );

    await pushOverlapChanged('u1', ['t1', 't2'], [win(START)], JHB);

    expect(pruned()?.[1]).toEqual(['u1', ['t1']]);
  });

  it('KEEPS a token on messaging/internal-error and other transient codes', async () => {
    // Losing a registration to a quota blip or a transport hiccup is a silent, permanent
    // regression for that user: they simply stop getting notified and nothing reports it.
    for (const code of [
      'messaging/internal-error',
      'messaging/server-unavailable',
      'messaging/quota-exceeded',
      'messaging/unknown-error',
      'messaging/authentication-error',
      'messaging/third-party-auth-error',
    ]) {
      vi.mocked(query).mockClear();
      vi.mocked(sendEach).mockImplementation(async (t: string[]) =>
        withErrors({ t1: code, t2: code })(t),
      );

      await pushOverlapChanged('u1', ['t1', 't2'], [win(START)], JHB);

      expect(query, `${code} must not prune`).not.toHaveBeenCalled();
    }
  });

  it('keeps every other token when one is pruned', async () => {
    vi.mocked(sendEach).mockImplementation(async (t: string[]) =>
      withErrors({
        t2: 'messaging/registration-token-not-registered',
        t3: 'messaging/internal-error',
      })(t),
    );

    await pushOverlapChanged('u1', ['t1', 't2', 't3', 't4'], [win(START)], JHB);

    // Only the hard-invalid one. The transient failure and the two successes survive.
    expect(pruned()?.[1]).toEqual(['u1', ['t2']]);
    // Subtracted in SQL rather than written back as a computed array, so a token registered
    // between the read and this write is not clobbered.
    expect(String(pruned()?.[0])).toMatch(/unnest\(fcm_tokens\)/);
  });

  it('writes nothing when every token succeeded', async () => {
    await pushOverlapChanged('u1', ['t1', 't2'], [win(START)], JHB);

    expect(query).not.toHaveBeenCalled();
  });
});

describe('the body', () => {
  it('formats the body with a local time in the recipient timezone', async () => {
    await pushOverlapChanged('u1', ['t1'], [win(START)], JHB);
    expect(body()).toBe('1 window — next Wed 3 Jun, 20:00');

    vi.mocked(sendEach).mockClear();
    await pushOverlapChanged('u2', ['t2'], [win(START)], NY);
    expect(body()).toBe('1 window — next Wed 3 Jun, 14:00');
  });

  it('names the soonest window, not the highest-scoring one', async () => {
    // The engine sorts by score descending (overlap/score.ts), so windows[0] is the best window,
    // not the next one. Reading windows[0] would announce a time three days out.
    const windows = [win(START + 3 * 24 * HOUR, { score: 99 }), win(START, { score: 10 })];

    await pushOverlapChanged('u1', ['t1'], windows, JHB);

    expect(body()).toBe('2 windows — next Wed 3 Jun, 20:00');
  });

  it('falls back to a generic body when there are no windows left', async () => {
    await pushOverlapChanged('u1', ['t1'], [], JHB);

    expect(body()).toBe('Your shared free time changed');
  });
});

describe('the payload', () => {
  it('never includes a block title in the payload', async () => {
    await pushOverlapChanged('u1', ['t1'], [win(START), win(START + HOUR)], JHB);

    // Exhaustive, not a substring check: the payload has exactly one data key, so there is no
    // channel a title, category or window could ride on even by accident. FCM renders this on a
    // locked screen.
    expect(payload()).toEqual({
      notification: { title: 'New free time together', body: '2 windows — next Wed 3 Jun, 20:00' },
      data: { type: 'overlap' },
    });
  });
});
