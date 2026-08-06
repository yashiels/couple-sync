import cors from '@fastify/cors';
import Fastify, { type FastifyInstance } from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { beforeAll, describe, expect, it, vi } from 'vitest';
import type { CoupleRow } from '../wire.js';

// Per-function tests on requireAuth and assertMember prove the functions work. They prove nothing
// about a handler that forgot to call one. This file is driven from a table of every route instead,
// plus a diff against the live route tree — so a new route that skips a guard fails CI rather than
// shipping.
vi.mock('../config.js', () => ({
  config: { port: 0, corsOrigins: ['https://app.example'], adminToken: null },
}));
vi.mock('../firebase.js', () => ({
  verifyIdToken: vi.fn(),
  assertCredentials: vi.fn(async () => {}),
}));
vi.mock('../db.js', () => ({ query: vi.fn(), withTx: vi.fn(), assertReachable: vi.fn(async () => {}) }));
vi.mock('../sockets.js', () => ({ sendTo: vi.fn(() => true) }));
vi.mock('../push.js', () => ({ pushOverlapChanged: vi.fn(async () => {}) }));
vi.mock('../overlapService.js', () => ({
  refreshOverlap: vi.fn(async () => ({ windows: [], computedAt: 0, changed: false })),
}));

const { verifyIdToken } = await import('../firebase.js');
const { query, withTx } = await import('../db.js');
const { registerErrorHandler } = await import('../http.js');
const { routePlugins } = await import('../index.js');

const COUPLE: CoupleRow = {
  id: 'c1',
  user_a_uid: 'uid-a',
  user_b_uid: 'uid-b',
  status: 'active',
  paired_at: 1,
  created_at: 1,
};

const GHOST = 'c-does-not-exist';

interface Route {
  /** Verb, and the registered url pattern — the pattern is what the enumeration test diffs. */
  m: string;
  u: string;
  /** Couple-scoped: the couple id is an input, so a non-member and a ghost id must both get 403. */
  couple?: true;
  at?: (coupleId: string) => string;
  payload?: (coupleId: string) => Record<string, unknown>;
}

/**
 * One table. Adding a route without adding it here breaks the last test in this file.
 * POST /auth/verify IS protected: it verifies a Bearer token in order to upsert the row.
 */
const ROUTES: Route[] = [
  { m: 'POST', u: '/auth/verify' },
  { m: 'POST', u: '/auth/fcm-token', payload: () => ({ token: 'fcm-1' }) },
  { m: 'DELETE', u: '/auth/fcm-token', payload: () => ({ token: 'fcm-1' }) },
  { m: 'GET', u: '/users/me' },
  { m: 'GET', u: '/users/:uid', at: () => '/users/uid-b' },
  { m: 'PATCH', u: '/users/:uid', at: () => '/users/uid-b', payload: () => ({ timezone: 'UTC' }) },
  { m: 'GET', u: '/blocks', couple: true, at: (c) => `/blocks?coupleId=${c}&from=0&to=1` },
  { m: 'POST', u: '/blocks', couple: true, payload: (c) => ({ couple_id: c }) },
  { m: 'GET', u: '/blocks/:id', couple: true, at: (c) => `/blocks/b1?coupleId=${c}` },
  {
    m: 'PATCH',
    u: '/blocks/:id',
    couple: true,
    at: () => '/blocks/b1',
    payload: (c) => ({ couple_id: c, title: 'x' }),
  },
  { m: 'DELETE', u: '/blocks/:id', couple: true, at: (c) => `/blocks/b1?coupleId=${c}` },
  {
    m: 'PUT',
    u: '/blocks/google',
    couple: true,
    payload: (c) => ({ couple_id: c, intervals: [] }),
  },
  { m: 'GET', u: '/overlaps/latest', couple: true, at: (c) => `/overlaps/latest?coupleId=${c}` },
  { m: 'GET', u: '/couples/:id', couple: true, at: (c) => `/couples/${c}` },
  { m: 'POST', u: '/couples/:id/unpair', couple: true, at: (c) => `/couples/${c}/unpair` },
  { m: 'POST', u: '/invites' },
  { m: 'POST', u: '/invites/:code/redeem', at: () => '/invites/ABC234/redeem' },
];

const COUPLE_SCOPED = ROUTES.filter((r) => r.couple);

let app: FastifyInstance;
/** Every route the app really registered, collected from a root onRoute hook. */
const seen: [string, string][] = [];

beforeAll(async () => {
  vi.mocked(verifyIdToken).mockImplementation(async (token: string) => {
    if (token === 'not-a-real-token') throw new Error('Decoding Firebase ID token failed');
    return { uid: token, sub: token } as DecodedIdToken;
  });
  // Answers the membership read and the advisory lock, and nothing else: reaching any other
  // statement means no guard rejected the request, so the test fails with that statement's text.
  const guardOnly = async (sql: string, params: unknown[] = []) => {
    if (sql.includes('pg_advisory_xact_lock')) return [];
    if (/SELECT \* FROM couples WHERE id = \$1/.test(sql)) {
      return params[0] === COUPLE.id ? [{ ...COUPLE }] : [];
    }
    throw new Error(`no guard rejected this request; it reached: ${sql}`);
  };
  vi.mocked(query).mockImplementation(guardOnly as typeof query);
  // POST /couples/:id/unpair checks membership inside its transaction, under the lock, so the fake
  // has to let a transaction open — it just may not reach a write.
  vi.mocked(withTx).mockImplementation((async (fn: (q: { query: typeof guardOnly }) => unknown) =>
    fn({ query: guardOnly })) as typeof withTx);

  app = Fastify();
  // Added at the root and BEFORE any register(), so it fires for every encapsulated child too.
  // printRoutes() would also work but returns a formatted tree meant for humans to read.
  app.addHook('onRoute', (r) => {
    // r.method is an array when a route declares several verbs.
    for (const method of [r.method].flat()) seen.push([method, r.url]);
  });
  registerErrorHandler(app);
  // Registered here too, because CORS is what adds the OPTIONS route the diff has to normalize away.
  await app.register(cors, { origin: ['https://app.example'] });
  app.get('/health', async () => ({ status: 'ok', time: 0 }));
  for (const plugin of routePlugins) await app.register(plugin);
  await app.ready();
});

const call = (route: Route, coupleId: string, token: string | null) =>
  app.inject({
    method: route.m as 'GET',
    url: route.at?.(coupleId) ?? route.u,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    payload: route.payload?.(coupleId) ?? {},
  });

describe('every protected route verifies the ID token', () => {
  it.each(ROUTES)('$m $u 401s with no token', async (route) => {
    const res = await call(route, COUPLE.id, null);

    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: 'missing_token' });
  });

  it.each(ROUTES)('$m $u 401s with an invalid token', async (route) => {
    const res = await call(route, COUPLE.id, 'not-a-real-token');

    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: 'invalid_token' });
  });
});

describe('every couple-scoped route calls assertMember', () => {
  it.each(COUPLE_SCOPED)('$m $u 403s for a non-member', async (route) => {
    const res = await call(route, COUPLE.id, 'uid-stranger');

    expect(res.statusCode).toBe(403);
    expect(res.json()).toEqual({ error: 'forbidden' });
  });

  it.each(COUPLE_SCOPED)(
    '$m $u 403s — not 404 — for a couple id that does not exist',
    async (route) => {
      const ghost = await call(route, GHOST, 'uid-a');
      const stranger = await call(route, COUPLE.id, 'uid-stranger');

      expect(ghost.statusCode).toBe(403);
      // Byte-identical, so a caller cannot tell a couple id that exists from one that does not.
      expect(ghost.body).toBe(stranger.body);
    },
  );
});

describe('the table itself', () => {
  it('matches every registered route except /health and /admin/cleanup', () => {
    const live = new Set(
      seen
        // Fastify auto-adds HEAD for every GET, and CORS adds OPTIONS. Neither is a separately
        // authored route, and both would look like permanent gaps in the table.
        .filter(([method]) => method !== 'HEAD' && method !== 'OPTIONS')
        // /health is public by design; /admin/cleanup (Task 8) is guarded by ADMIN_TOKEN instead.
        .filter(([, url]) => url !== '/health' && url !== '/admin/cleanup')
        .map(([method, url]) => `${method} ${url}`),
    );
    const declared = new Set(ROUTES.map((r) => `${r.m} ${r.u}`));

    // Both directions: an unguarded new route, and a table entry that no longer exists.
    expect([...live].sort()).toEqual([...declared].sort());
  });
});
