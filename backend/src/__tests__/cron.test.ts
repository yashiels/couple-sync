import Fastify, { type FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * node:crypto is wrapped, not replaced: the real implementations run, but timingSafeEqual and
 * createHash are observable. That is what makes "compares in constant time" a real test instead of a
 * comment — swap the comparison for `===` and the spy is never called.
 *
 * This file also owns POST /admin/cleanup outright: guards.matrix.test.ts enumerates the route tree
 * from index.ts's `routePlugins`, and cron.ts registers on the instance directly (it is guarded by
 * ADMIN_TOKEN, not requireAuth), so that suite excludes /admin/cleanup by name.
 */
vi.mock('node:crypto', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:crypto')>();
  return {
    ...actual,
    default: actual,
    createHash: vi.fn(actual.createHash),
    timingSafeEqual: vi.fn(actual.timingSafeEqual),
  };
});

const TOKEN = 'correct-horse-battery-staple';
const NOW = Date.parse('2026-06-03T10:00:00Z');

interface Invite {
  code: string;
  status: string;
  expires_at: number;
}

let invites: Invite[] = [];

function seed(code: string, status: string, expires_at: number): Invite {
  const row = { code, status, expires_at };
  invites.push(row);
  return row;
}

/**
 * The sweep statement, executed for real against the seeded rows. The fake refuses to run a
 * statement whose predicate it does not recognise, so a sweep that dropped the `status = 'pending'`
 * filter — and would therefore expire an accepted invite — fails here instead of passing.
 */
async function fakeQuery(sql: string, params: unknown[] = []): Promise<Record<string, unknown>[]> {
  const one = sql.replace(/\s+/g, ' ').trim();
  if (!/^UPDATE invites SET status = 'expired'/.test(one)) {
    throw new Error(`unexpected statement: ${one}`);
  }
  if (!/WHERE status = 'pending' AND expires_at < \$1/.test(one)) {
    throw new Error(`sweep predicate is not pending-and-past: ${one}`);
  }
  if (!/RETURNING code/.test(one)) throw new Error(`sweep must report what it changed: ${one}`);
  const cutoff = Number(params[0]);
  const hit = invites.filter((i) => i.status === 'pending' && i.expires_at < cutoff);
  for (const i of hit) i.status = 'expired';
  return hit.map((i) => ({ code: i.code }));
}

type Cron = typeof import('../cron.js');
interface Loaded extends Cron {
  app: FastifyInstance;
  query: ReturnType<typeof vi.fn>;
  createHash: ReturnType<typeof vi.fn>;
  timingSafeEqual: ReturnType<typeof vi.fn>;
}

/**
 * cron.ts hashes the expected token at module load, so the token can only be varied by reloading the
 * module. The crypto spies are re-created by the mock factory on every reset, so they are re-read
 * here rather than captured once at the top of the file.
 */
async function loadCron(adminToken: string | null): Promise<Loaded> {
  vi.resetModules();
  vi.doMock('../config.js', () => ({ config: { adminToken } }));
  vi.doMock('../db.js', () => ({ query: vi.fn(fakeQuery) }));

  const cron = await import('../cron.js');
  const { query } = await import('../db.js');
  const { registerErrorHandler } = await import('../http.js');
  const crypto = await import('node:crypto');

  const app = Fastify();
  registerErrorHandler(app);
  cron.registerAdminRoutes(app);
  await app.ready();

  return {
    ...cron,
    app,
    query: vi.mocked(query) as unknown as ReturnType<typeof vi.fn>,
    createHash: crypto.createHash as unknown as ReturnType<typeof vi.fn>,
    timingSafeEqual: crypto.timingSafeEqual as unknown as ReturnType<typeof vi.fn>,
  };
}

const cleanup = (app: FastifyInstance, token?: string) =>
  app.inject({
    method: 'POST',
    url: '/admin/cleanup',
    headers: token === undefined ? {} : { 'x-admin-token': token },
  });

beforeEach(() => {
  invites = [];
  vi.setSystemTime(NOW);
});

afterEach(() => {
  for (const id of ['../config.js', '../db.js']) vi.doUnmock(id);
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe('expireStaleInvites', () => {
  it('flips only pending invites whose expires_at has passed', async () => {
    const stale = seed('AAA234', 'pending', NOW - 1);
    const fresh = seed('BBB234', 'pending', NOW + 1);
    const { expireStaleInvites } = await loadCron(TOKEN);

    await expect(expireStaleInvites()).resolves.toBe(1);

    expect(stale.status).toBe('expired');
    expect(fresh.status).toBe('pending');
  });

  it('leaves accepted invites untouched', async () => {
    // An accepted invite is the audit trail of a real pairing. Expiring it would rewrite history,
    // and routes/invites.ts distinguishes 409 invite_used from 409 invite_expired by this column.
    const accepted = seed('CCC234', 'accepted', NOW - 86_400_000);
    const alreadyExpired = seed('DDD234', 'expired', NOW - 86_400_000);
    const { expireStaleInvites } = await loadCron(TOKEN);

    await expect(expireStaleInvites()).resolves.toBe(0);

    expect(accepted.status).toBe('accepted');
    expect(alreadyExpired.status).toBe('expired');
  });

  it('is idempotent — a second sweep reports zero', async () => {
    seed('EEE234', 'pending', NOW - 1);
    const { expireStaleInvites } = await loadCron(TOKEN);

    await expect(expireStaleInvites()).resolves.toBe(1);
    await expect(expireStaleInvites()).resolves.toBe(0);
  });
});

describe('POST /admin/cleanup', () => {
  it('503s when the admin token is unset', async () => {
    const { app, query } = await loadCron(null);

    const res = await cleanup(app, TOKEN);

    expect(res.statusCode).toBe(503);
    expect(res.json()).toEqual({ error: 'admin_disabled' });
    // Disabled means disabled: not even a correct-looking token runs the sweep.
    expect(query).not.toHaveBeenCalled();
  });

  it('401s on a wrong token', async () => {
    const { app, query } = await loadCron(TOKEN);

    const res = await cleanup(app, 'wrong-horse-battery-staple');

    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: 'unauthorized' });
    expect(query).not.toHaveBeenCalled();
  });

  it('401s when the header is absent altogether', async () => {
    const { app } = await loadCron(TOKEN);

    expect((await cleanup(app)).statusCode).toBe(401);
  });

  it('rejects an empty supplied token', async () => {
    const { app, query } = await loadCron(TOKEN);

    const res = await cleanup(app, '');

    expect(res.statusCode).toBe(401);
    expect(query).not.toHaveBeenCalled();
  });

  it('200s and reports the count on the correct token', async () => {
    seed('FFF234', 'pending', NOW - 1);
    seed('GGG234', 'pending', NOW - 2);
    seed('HHH234', 'pending', NOW + 86_400_000);
    const { app } = await loadCron(TOKEN);

    const res = await cleanup(app, TOKEN);

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ expired: 2 });
  });
});

describe('the admin token comparison', () => {
  it('compares the admin token in constant time', async () => {
    const { app, timingSafeEqual } = await loadCron(TOKEN);
    timingSafeEqual.mockClear();

    await cleanup(app, 'wrong-horse-battery-staple');

    // Replace the comparison with `===` and this fails: the spy is the only witness.
    expect(timingSafeEqual).toHaveBeenCalledTimes(1);
    const [supplied, expected] = timingSafeEqual.mock.calls[0] as [Buffer, Buffer];
    // Fixed width on both sides, which is what stops a wrong-length token from throwing RangeError
    // and leaking the expected length through a 500.
    expect(supplied.length).toBe(32);
    expect(expected.length).toBe(32);
  });

  it('hashes the secret once at module load, not per request', async () => {
    const { app, createHash } = await loadCron(TOKEN);
    createHash.mockClear();

    await cleanup(app, TOKEN);
    await cleanup(app, TOKEN);

    // Exactly one digest per request — the supplied token. Hashing the secret again on each
    // request would make the request's duration depend on the secret's length, which is the leak
    // timingSafeEqual exists to close.
    expect(createHash).toHaveBeenCalledTimes(2);
  });

  it('does not throw on a SHORTER supplied token', async () => {
    const { app } = await loadCron(TOKEN);

    const res = await cleanup(app, 'c');

    // 401, never 500: timingSafeEqual throws RangeError on a length mismatch, and a 500 here would
    // let a caller binary-search the secret's length.
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: 'unauthorized' });
  });

  it('does not throw on a LONGER supplied token', async () => {
    const { app } = await loadCron(TOKEN);

    const res = await cleanup(app, TOKEN + 'x'.repeat(4096));

    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: 'unauthorized' });
  });

  it('answers identically whatever the wrong length was', async () => {
    const { app } = await loadCron(TOKEN);

    const short = await cleanup(app, 'c');
    const long = await cleanup(app, TOKEN + 'xxxx');
    const same = await cleanup(app, 'x'.repeat(TOKEN.length));

    // Byte-identical, so the response never hints at how close the guess was.
    expect(short.statusCode).toBe(long.statusCode);
    expect(short.body).toBe(long.body);
    expect(short.body).toBe(same.body);
  });
});

describe('startInviteExpiryTimer', () => {
  beforeEach(() => {
    // The outer beforeEach already mocked Date via setSystemTime; switching to fake timers on top
    // of that needs an explicit reset first.
    vi.useRealTimers();
    vi.useFakeTimers();
    vi.setSystemTime(NOW);
  });

  it('sweeps once when the clock reaches 03:00 UTC, and not again that day', async () => {
    seed('III234', 'pending', NOW - 1);
    const { startInviteExpiryTimer, query } = await loadCron(TOKEN);
    // 02:00 UTC the next morning, so the first 03:00 is one hour of ticks away.
    vi.setSystemTime(Date.parse('2026-06-04T02:00:00Z'));

    const timer = startInviteExpiryTimer();
    try {
      await vi.advanceTimersByTimeAsync(45 * 60_000);
      expect(query).not.toHaveBeenCalled();

      await vi.advanceTimersByTimeAsync(20 * 60_000); // now past 03:00
      expect(query).toHaveBeenCalledTimes(1);

      // Three more ticks inside the same 03:00 hour must not re-run it.
      await vi.advanceTimersByTimeAsync(45 * 60_000);
      expect(query).toHaveBeenCalledTimes(1);

      // The next day's 03:00 does.
      await vi.advanceTimersByTimeAsync(24 * 3_600_000);
      expect(query).toHaveBeenCalledTimes(2);
    } finally {
      clearInterval(timer);
    }
  });

  it('does not let a failed sweep become an unhandled rejection', async () => {
    const { startInviteExpiryTimer, query } = await loadCron(TOKEN);
    query.mockRejectedValueOnce(new Error('ECONNREFUSED 127.0.0.1:5432'));
    const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.setSystemTime(Date.parse('2026-06-04T02:59:00Z'));

    const timer = startInviteExpiryTimer();
    try {
      await vi.advanceTimersByTimeAsync(20 * 60_000);
      expect(logged).toHaveBeenCalled();
    } finally {
      clearInterval(timer);
    }
  });
});
