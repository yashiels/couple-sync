import Fastify, { type FastifyInstance } from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { UserRow } from '../wire.js';

vi.mock('../firebase.js', () => ({ verifyIdToken: vi.fn() }));
vi.mock('../db.js', () => ({ query: vi.fn() }));

const { verifyIdToken } = await import('../firebase.js');
const { query } = await import('../db.js');
const { registerErrorHandler } = await import('../http.js');
const authRoutes = (await import('../routes/auth.js')).default;

const JHB = 'Africa/Johannesburg';
const NOW = Date.parse('2026-06-03T10:00:00Z');

const users = new Map<string, UserRow>();

function seedUser(uid: string, over: Partial<UserRow> = {}): UserRow {
  const row: UserRow = {
    uid,
    email: `${uid}@example.com`,
    display_name: 'Ada',
    photo_url: 'https://example.com/old.png',
    timezone: JHB,
    couple_id: 'c1',
    show_late_night_windows: true,
    notifications_enabled: false,
    fcm_tokens: [],
    created_at: 111,
    ...over,
  };
  users.set(uid, row);
  return row;
}

/**
 * The upsert is emulated from the statement text, not hardcoded: the INSERT column list and the DO
 * UPDATE assignments are parsed and applied. So an implementation that added
 * `timezone = EXCLUDED.timezone` to the conflict clause really would clobber the stored timezone
 * here, instead of the fake quietly protecting it.
 */
function upsert(sql: string, params: unknown[]): UserRow {
  const columns = /INSERT INTO users \(([^)]*)\)/
    .exec(sql)![1]!
    .split(',')
    .map((c) => c.trim());
  const incoming: Record<string, unknown> = {};
  columns.forEach((column, i) => (incoming[column] = params[i]));
  const uid = String(incoming['uid']);

  const existing = users.get(uid);
  if (!existing) {
    // Column defaults per migrations/001_init.sql.
    const created: UserRow = {
      uid,
      email: String(incoming['email'] ?? ''),
      display_name: (incoming['display_name'] as string | null) ?? null,
      photo_url: (incoming['photo_url'] as string | null) ?? null,
      timezone: null,
      couple_id: null,
      show_late_night_windows: false,
      notifications_enabled: true,
      fcm_tokens: [],
      created_at: Number(incoming['created_at']),
    };
    users.set(uid, created);
    return created;
  }

  const setClause = sql.slice(sql.indexOf('DO UPDATE SET'), sql.indexOf('RETURNING'));
  const updated = { ...existing } as Record<string, unknown>;
  for (const [, column, coalesced, direct] of setClause.matchAll(
    /(\w+) = (?:COALESCE\(EXCLUDED\.(\w+), users\.\w+\)|EXCLUDED\.(\w+))/g,
  )) {
    updated[column!] = coalesced
      ? (incoming[coalesced] ?? (existing as Record<string, unknown>)[coalesced])
      : incoming[direct!];
  }
  const row = updated as unknown as UserRow;
  users.set(uid, row);
  return row;
}

async function fakeQuery(sql: string, params: unknown[] = []): Promise<Record<string, unknown>[]> {
  if (sql.includes('INSERT INTO users')) return [{ ...upsert(sql, params) }];

  if (/^UPDATE users/.test(sql.trim())) {
    const [uid, token] = params as [string, string];
    const row = users.get(uid);
    if (!row) return [];
    const tokens = row.fcm_tokens;
    const next = sql.includes('array_append')
      ? tokens.includes(token)
        ? tokens
        : [...tokens, token]
      : tokens.filter((t) => t !== token);
    const updated = { ...row, fcm_tokens: next };
    users.set(uid, updated);
    return [{ ...updated }];
  }
  throw new Error(`unrouted statement: ${sql}`);
}

function app(): FastifyInstance {
  const a = Fastify();
  registerErrorHandler(a);
  void a.register(authRoutes);
  return a;
}

const as = (uid: string) => ({ authorization: `Bearer ${uid}` });

const verify = (uid: string, claims: Partial<DecodedIdToken> = {}) => {
  vi.mocked(verifyIdToken).mockImplementation(
    async (token: string) => ({ uid: token, sub: token, ...claims }) as DecodedIdToken,
  );
  return app().inject({ method: 'POST', url: '/auth/verify', headers: as(uid) });
};

const fcm = (method: 'POST' | 'DELETE', uid: string, body: unknown) =>
  app().inject({ method, url: '/auth/fcm-token', headers: as(uid), payload: body });

beforeEach(() => {
  vi.clearAllMocks();
  users.clear();
  vi.spyOn(Date, 'now').mockReturnValue(NOW);
  vi.mocked(verifyIdToken).mockImplementation(
    async (token: string) => ({ uid: token, sub: token }) as DecodedIdToken,
  );
  vi.mocked(query).mockImplementation(fakeQuery as typeof query);
});

describe('POST /auth/verify', () => {
  it('creates the row on a first-time sign-in, with a NULL timezone and no couple', async () => {
    const res = await verify('uid-new', {
      email: 'new@example.com',
      name: 'Grace',
      picture: 'https://example.com/g.png',
    });

    expect(res.statusCode).toBe(200);
    expect(res.json<{ user: UserRow }>().user).toEqual({
      uid: 'uid-new',
      email: 'new@example.com',
      display_name: 'Grace',
      photo_url: 'https://example.com/g.png',
      // NULL, so the router guard sends them to timezone setup.
      timezone: null,
      couple_id: null,
      show_late_night_windows: false,
      notifications_enabled: true,
      fcm_tokens: [],
      created_at: NOW,
    });
  });

  it('returns the caller own row including fcm_tokens', async () => {
    seedUser('uid-a', { fcm_tokens: ['tok-1'] });

    const res = await verify('uid-a');

    expect(res.json<{ user: UserRow }>().user.fcm_tokens).toEqual(['tok-1']);
  });

  it('does not reset the timezone, couple, preferences or created_at on a repeat sign-in', async () => {
    seedUser('uid-a');

    const res = await verify('uid-a', { email: 'ada@new.example', name: 'Ada L' });

    expect(res.json<{ user: UserRow }>().user).toMatchObject({
      // ours, untouched
      timezone: JHB,
      couple_id: 'c1',
      show_late_night_windows: true,
      notifications_enabled: false,
      created_at: 111,
      // Firebase's, refreshed
      email: 'ada@new.example',
      display_name: 'Ada L',
    });
  });

  it('keeps the stored display_name and photo when the token carries neither', async () => {
    seedUser('uid-a');

    await verify('uid-a', { email: 'ada@example.com' });

    expect(users.get('uid-a')).toMatchObject({
      display_name: 'Ada',
      photo_url: 'https://example.com/old.png',
    });
  });

  it('401s and touches no row without a bearer token', async () => {
    const res = await app().inject({ method: 'POST', url: '/auth/verify' });

    expect(res.statusCode).toBe(401);
    expect(query).not.toHaveBeenCalled();
  });
});

describe('POST /auth/fcm-token', () => {
  it('appends the token', async () => {
    seedUser('uid-a');

    const res = await fcm('POST', 'uid-a', { token: 'tok-1' });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ fcm_tokens: ['tok-1'] });
  });

  it('does not duplicate a token that is already registered', async () => {
    seedUser('uid-a', { fcm_tokens: ['tok-1'] });

    const res = await fcm('POST', 'uid-a', { token: 'tok-1' });

    expect(res.json()).toEqual({ fcm_tokens: ['tok-1'] });
    expect(users.get('uid-a')?.fcm_tokens).toEqual(['tok-1']);
  });

  it('keeps a second device token', async () => {
    seedUser('uid-a', { fcm_tokens: ['tok-phone'] });

    await fcm('POST', 'uid-a', { token: 'tok-tablet' });

    expect(users.get('uid-a')?.fcm_tokens).toEqual(['tok-phone', 'tok-tablet']);
  });

  it('400s on a missing or blank token', async () => {
    seedUser('uid-a');

    for (const body of [{}, { token: '' }, { token: '   ' }, { token: 42 }]) {
      const res = await fcm('POST', 'uid-a', body);
      expect(res.statusCode).toBe(400);
      expect(res.json()).toEqual({ error: 'bad_token' });
    }
  });
});

describe('DELETE /auth/fcm-token', () => {
  it('removes only the named token and leaves the other devices intact', async () => {
    seedUser('uid-a', { fcm_tokens: ['tok-phone', 'tok-tablet', 'tok-old-phone'] });

    const res = await fcm('DELETE', 'uid-a', { token: 'tok-tablet' });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ fcm_tokens: ['tok-phone', 'tok-old-phone'] });
    expect(users.get('uid-a')?.fcm_tokens).toEqual(['tok-phone', 'tok-old-phone']);
  });

  it('is a no-op, not an error, for a token the user does not own', async () => {
    seedUser('uid-a', { fcm_tokens: ['tok-phone'] });

    const res = await fcm('DELETE', 'uid-a', { token: 'tok-someone-else' });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ fcm_tokens: ['tok-phone'] });
  });

  it('only ever touches the caller own row', async () => {
    seedUser('uid-a', { fcm_tokens: ['tok-shared'] });
    seedUser('uid-b', { fcm_tokens: ['tok-shared'] });

    await fcm('DELETE', 'uid-a', { token: 'tok-shared' });

    // A shared handset: signing out of A must not strip B's registration of the same token.
    expect(users.get('uid-a')?.fcm_tokens).toEqual([]);
    expect(users.get('uid-b')?.fcm_tokens).toEqual(['tok-shared']);
  });
});
