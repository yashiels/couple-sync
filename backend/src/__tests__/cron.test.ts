import { describe, it, expect, beforeEach, vi } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

/**
 * Cron + admin route tests — Task 7 defects 3a + 3b.
 *
 *  3a: startCleanupCron schedules at 03:00 UTC (timezone: 'UTC' option).
 *  3b: POST /admin/cleanup compares the bearer token with timingSafeEqual
 *      (constant-time) — wrong/missing/different-length tokens all 401, the
 *      correct token 200s, and an unset ADMIN_TOKEN 503s.
 *
 * Mocks:
 *  - db.ts      -> query (the cleanup UPDATE)
 *  - config.ts -> getConfig (adminToken)
 *  - node-cron -> default.schedule (spy, so no real timer is armed)
 */

const { mockQuery, getConfig, scheduleSpy } = vi.hoisted(() => ({
  mockQuery: vi.fn(),
  getConfig: vi.fn(),
  scheduleSpy: vi.fn(() => ({ start: vi.fn(), stop: vi.fn() })),
}));

vi.mock('../db.js', () => ({
  query: (...args: unknown[]) => mockQuery(...args),
  getPool: vi.fn(),
  endPool: vi.fn(),
}));

vi.mock('../config.js', () => ({
  getConfig: () => getConfig(),
  loadConfig: vi.fn(),
}));

vi.mock('node-cron', () => ({
  default: { schedule: scheduleSpy },
}));

import { adminRoutes, cleanupExpiredInvites, startCleanupCron } from '../cron.js';

const TOKEN = 'super-secret-admin-token';

beforeEach(() => {
  mockQuery.mockReset();
  getConfig.mockReset();
  scheduleSpy.mockReset();
  scheduleSpy.mockReturnValue({ start: vi.fn(), stop: vi.fn() });
  getConfig.mockReturnValue({ adminToken: TOKEN });
});

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  await app.register(adminRoutes);
  return app;
}

describe('POST /admin/cleanup', () => {
  it('returns 200 + expired count for the correct bearer token', async () => {
    mockQuery.mockResolvedValue({ rowCount: 5 });
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/admin/cleanup',
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ expired: 5 });
    await app.close();
  });

  it('returns 401 for a wrong token', async () => {
    mockQuery.mockResolvedValue({ rowCount: 3 });
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/admin/cleanup',
      headers: { authorization: 'Bearer wrong-token' },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json().error).toBe('unauthorized');
    // The cleanup UPDATE must not run on a failed auth.
    expect(mockQuery).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns 401 when the Authorization header is missing', async () => {
    const app = await buildApp();
    const res = await app.inject({ method: 'POST', url: '/admin/cleanup' });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('returns 401 for a different-length attacker token (no throw)', async () => {
    // timingSafeEqual throws on length mismatch if not guarded — the handler
    // must short-circuit on length so a short token 401s instead of 500ing.
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/admin/cleanup',
      headers: { authorization: 'Bearer short' },
    });
    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('returns 503 when ADMIN_TOKEN is not configured', async () => {
    getConfig.mockReturnValue({ adminToken: '' });
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/admin/cleanup',
      headers: { authorization: `Bearer ${TOKEN}` },
    });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe('unavailable');
    await app.close();
  });
});

describe('startCleanupCron', () => {
  it('schedules the daily 03:00 job with timezone UTC', () => {
    startCleanupCron();
    expect(scheduleSpy).toHaveBeenCalledTimes(1);
    const [expr, , options] = scheduleSpy.mock.calls[0];
    expect(expr).toBe('0 3 * * *');
    expect(options).toMatchObject({ timezone: 'UTC' });
  });
});

describe('cleanupExpiredInvites', () => {
  it('flips pending+expired invites to expired and returns the count', async () => {
    mockQuery.mockResolvedValue({ rowCount: 7 });
    const count = await cleanupExpiredInvites();
    expect(count).toBe(7);
    const [sql, params] = mockQuery.mock.calls[0];
    expect(sql).toMatch(/UPDATE invites SET status = \$1 WHERE status = \$2 AND expires_at < \$3/);
    expect(params).toEqual(['expired', 'pending', expect.any(Number)]);
  });
});
