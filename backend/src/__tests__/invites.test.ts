import Fastify, { type FastifyInstance } from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Querier } from '../db.js';

// Redeem is the highest-risk logic in the backend, so the fake database below is a real one in
// miniature: statements are routed by their text, `FOR UPDATE` actually blocks, and writes are
// staged until COMMIT so a rollback genuinely leaves nothing behind. Asserting "the mock was
// called" would pass for an implementation with the lock protocol removed.
vi.mock('../firebase.js', () => ({ verifyIdToken: vi.fn() }));
vi.mock('../db.js', () => ({ query: vi.fn(), withTx: vi.fn() }));
vi.mock('../sockets.js', () => ({ sendTo: vi.fn() }));
vi.mock('../overlapService.js', () => ({ refreshOverlap: vi.fn() }));

const { verifyIdToken } = await import('../firebase.js');
const { query, withTx } = await import('../db.js');
const { sendTo } = await import('../sockets.js');
const { refreshOverlap } = await import('../overlapService.js');
const { registerErrorHandler } = await import('../http.js');
const invitesRoutes = (await import('../routes/invites.js')).default;

const JHB = 'Africa/Johannesburg';
const NY = 'America/New_York';
const NOW = Date.parse('2026-06-03T10:00:00Z');
const H48 = 48 * 3_600_000;

interface Invite {
  code: string;
  created_by_uid: string;
  couple_id: string | null;
  expires_at: number;
  status: string;
  created_at: number;
}
interface User {
  uid: string;
  couple_id: string | null;
  timezone: string | null;
}
interface Couple {
  id: string;
  user_a_uid: string;
  user_b_uid: string;
  status: string;
  paired_at: number;
}

/** The committed state. Transactions read through to it and only write to it at COMMIT. */
const users = new Map<string, User>();
const invites = new Map<string, Invite>();
const couples = new Map<string, Couple>();
/** Every statement, plus COMMIT/ROLLBACK/lock/refresh/ws markers, in the order they happened. */
let events: string[] = [];
const locks = new Map<string, Promise<void>>();
/** Substring of a statement that should blow up, to exercise rollback. */
let failOn: string | null = null;

function seedUser(uid: string, over: Partial<User> = {}): User {
  const row: User = { uid, couple_id: null, timezone: JHB, ...over };
  users.set(uid, row);
  return row;
}

function seedInvite(code: string, created_by_uid: string, over: Partial<Invite> = {}): Invite {
  const row: Invite = {
    code,
    created_by_uid,
    couple_id: null,
    expires_at: NOW + H48,
    status: 'pending',
    created_at: NOW,
    ...over,
  };
  invites.set(code, row);
  return row;
}

/**
 * Blocking lock. A key is held from acquisition until the owning transaction ends, so a second
 * transaction that asks for the same key waits for the first to COMMIT and then reads what it
 * wrote — exactly what `SELECT ... FOR UPDATE` buys under READ COMMITTED.
 */
async function acquire(key: string, releasers: (() => void)[]): Promise<void> {
  events.push(`lock:${key}`);
  const prev = locks.get(key);
  let release!: () => void;
  const mine = new Promise<void>((res) => {
    release = res;
  });
  locks.set(key, prev ? prev.then(() => mine) : mine);
  releasers.push(release);
  await prev;
  // Yield a macrotask on every lock so concurrent requests really interleave instead of one
  // request running to completion inside a single microtask drain.
  await new Promise((res) => setImmediate(res));
}

async function runInTx(
  sql: string,
  params: unknown[],
  staged: (() => void)[],
  releasers: (() => void)[],
): Promise<Record<string, unknown>[]> {
  events.push(`tx:${sql.replace(/\s+/g, ' ').trim()}`);
  // Every statement yields a macrotask, so concurrent requests interleave between statements the
  // way they would across a real connection pool. Without this, a whole handler runs to COMMIT
  // inside one microtask drain and a missing row lock is invisible.
  await new Promise((res) => setImmediate(res));
  if (failOn && sql.includes(failOn)) throw new Error('constraint violation');

  if (/FROM invites WHERE code = \$1 FOR UPDATE/.test(sql)) {
    await acquire(`invite:${String(params[0])}`, releasers);
    const row = invites.get(String(params[0]));
    return row ? [{ ...row }] : [];
  }

  if (/FROM users WHERE uid IN/.test(sql)) {
    const uids = params.map(String);
    // The fake obeys exactly what the statement asks for: it locks only if the statement says FOR
    // UPDATE, and in the order the statement asks for. With `ORDER BY uid` two redemptions sharing
    // a user serialize; without the ordering, two crossing redemptions deadlock; without the lock,
    // both read a null couple_id and both pair. That is what makes these real tests rather than
    // assertions about statement text.
    const order = /ORDER BY uid/.test(sql) ? [...uids].sort() : uids;
    if (/FOR UPDATE/.test(sql)) for (const uid of order) await acquire(`user:${uid}`, releasers);
    return order.flatMap((uid) => {
      const row = users.get(uid);
      return row ? [{ ...row }] : [];
    });
  }

  if (sql.includes('INSERT INTO couples')) {
    const [id, a, b, pairedAt] = params as [string, string, string, number];
    staged.push(() =>
      couples.set(id, { id, user_a_uid: a, user_b_uid: b, status: 'active', paired_at: pairedAt }),
    );
    return [];
  }

  if (sql.includes('UPDATE invites')) {
    const [coupleId, code] = params as [string, string];
    staged.push(() => {
      const row = invites.get(code);
      if (row) invites.set(code, { ...row, status: 'accepted', couple_id: coupleId });
    });
    return [];
  }

  if (sql.includes('UPDATE users SET couple_id')) {
    const [coupleId, ...uids] = params as [string, ...string[]];
    staged.push(() => {
      for (const uid of uids) {
        const row = users.get(uid);
        if (row) users.set(uid, { ...row, couple_id: coupleId });
      }
    });
    return [];
  }

  throw new Error(`unrouted tx statement: ${sql}`);
}

async function fakeTx<T>(fn: (q: Querier) => Promise<T>): Promise<T> {
  const staged: (() => void)[] = [];
  const releasers: (() => void)[] = [];
  const q = {
    query: async <R>(sql: string, params: unknown[] = []) =>
      (await runInTx(sql, params, staged, releasers)) as R[],
  };
  try {
    const out = await fn(q);
    events.push('COMMIT');
    for (const apply of staged) apply();
    return out;
  } catch (err) {
    events.push('ROLLBACK');
    throw err;
  } finally {
    for (const release of releasers) release();
  }
}

/** The non-transactional path: POST /invites. */
async function poolQuery(sql: string, params: unknown[] = []): Promise<Record<string, unknown>[]> {
  events.push(`pool:${sql.replace(/\s+/g, ' ').trim()}`);
  if (/SELECT couple_id FROM users/.test(sql)) {
    const row = users.get(String(params[0]));
    return row ? [{ couple_id: row.couple_id }] : [];
  }
  if (sql.includes('INSERT INTO invites')) {
    const [code, uid, expiresAt, createdAt] = params as [string, string, number, number];
    if (invites.has(code)) return []; // ON CONFLICT (code) DO NOTHING
    seedInvite(code, uid, { expires_at: expiresAt, created_at: createdAt });
    return [{ code, expires_at: expiresAt }];
  }
  throw new Error(`unrouted pool statement: ${sql}`);
}

function app(): FastifyInstance {
  const a = Fastify();
  registerErrorHandler(a);
  void a.register(invitesRoutes);
  return a;
}

/** The bearer token IS the uid, so concurrent requests can act as different users. */
const as = (uid: string) => ({ authorization: `Bearer ${uid}` });

const redeem = (a: FastifyInstance, code: string, uid: string) =>
  a.inject({ method: 'POST', url: `/invites/${code}/redeem`, headers: as(uid) });

/** Fails loudly instead of hanging when the lock protocol deadlocks. */
async function bothSettle<T>(a: Promise<T>, b: Promise<T>): Promise<[T, T]> {
  const timeout = new Promise<never>((_, rej) =>
    setTimeout(() => rej(new Error('deadlock: two concurrent redemptions never settled')), 500),
  );
  return (await Promise.race([Promise.all([a, b]), timeout])) as [T, T];
}

const coupleIds = () => [...couples.keys()];

beforeEach(() => {
  vi.clearAllMocks();
  users.clear();
  invites.clear();
  couples.clear();
  locks.clear();
  events = [];
  failOn = null;
  vi.spyOn(Date, 'now').mockReturnValue(NOW);
  vi.mocked(verifyIdToken).mockImplementation(
    async (token: string) => ({ uid: token, sub: token }) as DecodedIdToken,
  );
  vi.mocked(query).mockImplementation(poolQuery as typeof query);
  vi.mocked(withTx).mockImplementation(fakeTx as typeof withTx);
  vi.mocked(sendTo).mockImplementation(((uid: string, msg: { t: string }) => {
    events.push(`ws:${msg.t}:${uid}`);
    return true;
  }) as typeof sendTo);
  vi.mocked(refreshOverlap).mockImplementation(async (coupleId: string) => {
    events.push(`refresh:${coupleId}`);
    return { windows: [], computedAt: NOW, changed: true };
  });
});

describe('POST /invites', () => {
  it('returns 201 with a 6-character code and expires_at 48h out', async () => {
    seedUser('uid-a');

    const res = await app().inject({ method: 'POST', url: '/invites', headers: as('uid-a') });

    expect(res.statusCode).toBe(201);
    const body = res.json<{ code: string; expires_at: number }>();
    expect(body.code).toHaveLength(6);
    expect(body.expires_at).toBe(NOW + H48);
    expect(invites.get(body.code)).toMatchObject({ created_by_uid: 'uid-a', status: 'pending' });
  });

  it('generates codes from an unambiguous alphabet — no O, 0, I or 1', async () => {
    seedUser('uid-a');
    const a = app();

    const codes: string[] = [];
    for (let i = 0; i < 120; i++) {
      const res = await a.inject({ method: 'POST', url: '/invites', headers: as('uid-a') });
      codes.push(res.json<{ code: string }>().code);
    }

    for (const code of codes) expect(code).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    // 120 codes over a 32-symbol alphabet: a generator that never emits digits, or only letters,
    // would not survive this.
    expect(new Set(codes.join('')).size).toBeGreaterThan(20);
  });

  it('409s when the caller already has a couple_id', async () => {
    seedUser('uid-a', { couple_id: 'c-existing' });

    const res = await app().inject({ method: 'POST', url: '/invites', headers: as('uid-a') });

    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ error: 'already_paired' });
    expect(invites.size).toBe(0);
  });
});

describe('POST /invites/:code/redeem', () => {
  it('pairs two unpaired users and returns couple_id', async () => {
    seedUser('uid-a');
    seedUser('uid-b', { timezone: NY });
    seedInvite('ABC234', 'uid-a');

    const res = await redeem(app(), 'ABC234', 'uid-b');

    expect(res.statusCode).toBe(200);
    const { couple_id } = res.json<{ couple_id: string }>();
    expect(coupleIds()).toEqual([couple_id]);
    // The inviter is A, because scoring uses A's timezone (§2).
    expect(couples.get(couple_id)).toMatchObject({
      user_a_uid: 'uid-a',
      user_b_uid: 'uid-b',
      status: 'active',
      paired_at: NOW,
    });
  });

  it('sets couple_id on BOTH user rows and stamps the invite accepted', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a');

    const { couple_id } = (await redeem(app(), 'ABC234', 'uid-b')).json<{ couple_id: string }>();

    expect(users.get('uid-a')?.couple_id).toBe(couple_id);
    expect(users.get('uid-b')?.couple_id).toBe(couple_id);
    expect(invites.get('ABC234')).toMatchObject({ status: 'accepted', couple_id });
  });

  it('accepts a code typed in lower case', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a');

    const res = await redeem(app(), 'abc234', 'uid-b');

    expect(res.statusCode).toBe(200);
    expect(invites.get('ABC234')?.status).toBe('accepted');
  });

  it('404s on an unknown code', async () => {
    seedUser('uid-b');

    const res = await redeem(app(), 'ZZZZZZ', 'uid-b');

    expect(res.statusCode).toBe(404);
    expect(couples.size).toBe(0);
  });

  it('rejects an expired code and does not pair', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a', { expires_at: NOW - 1 });

    const res = await redeem(app(), 'ABC234', 'uid-b');

    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ error: 'invite_expired' });
    expect(couples.size).toBe(0);
    expect(users.get('uid-b')?.couple_id).toBeNull();
  });

  it('rejects an already-accepted code', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a', { status: 'accepted', couple_id: 'c-old' });

    const res = await redeem(app(), 'ABC234', 'uid-b');

    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ error: 'invite_used' });
    expect(couples.size).toBe(0);
  });

  it('rejects self-pairing by the invite creator', async () => {
    seedUser('uid-a');
    seedInvite('ABC234', 'uid-a');

    const res = await redeem(app(), 'ABC234', 'uid-a');

    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ error: 'self_pair' });
    expect(couples.size).toBe(0);
    expect(invites.get('ABC234')?.status).toBe('pending');
  });

  it('409s when the redeemer already has a couple', async () => {
    seedUser('uid-a');
    seedUser('uid-b', { couple_id: 'c-existing' });
    seedInvite('ABC234', 'uid-a');

    const res = await redeem(app(), 'ABC234', 'uid-b');

    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ error: 'already_paired' });
    expect(coupleIds()).toEqual([]);
  });

  it('409s when the inviter has since paired with someone else', async () => {
    seedUser('uid-a', { couple_id: 'c-other' });
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a');

    const res = await redeem(app(), 'ABC234', 'uid-b');

    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ error: 'inviter_already_paired' });
    expect(users.get('uid-b')?.couple_id).toBeNull();
  });

  it('409s when either user has a NULL timezone', async () => {
    seedUser('uid-a', { timezone: null });
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a');
    const a = app();

    // The inviter's timezone is missing. The router guard makes this unreachable in the app, but a
    // direct API call would hand the overlap engine a null zone on the very next refresh.
    const inviterNull = await redeem(a, 'ABC234', 'uid-b');
    expect(inviterNull.statusCode).toBe(409);
    expect(inviterNull.json()).toEqual({ error: 'timezone_required' });

    // And the same the other way round.
    seedUser('uid-a', { timezone: JHB });
    seedUser('uid-b', { timezone: null });
    const redeemerNull = await redeem(a, 'ABC234', 'uid-b');
    expect(redeemerNull.statusCode).toBe(409);
    expect(redeemerNull.json()).toEqual({ error: 'timezone_required' });

    expect(couples.size).toBe(0);
  });

  it('409s when either timezone is not a valid IANA id', async () => {
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a');
    const a = app();

    // An abbreviation, and a fixed offset — luxon's isValidZone accepts the latter, and an offset
    // has no DST rules, so the engine would drift by an hour twice a year.
    for (const timezone of ['SAST', '+02:00']) {
      seedUser('uid-a', { timezone });
      const res = await redeem(a, 'ABC234', 'uid-b');
      expect(res.statusCode).toBe(409);
      expect(res.json()).toEqual({ error: 'invalid_timezone' });
    }
    expect(couples.size).toBe(0);
  });

  it('locks both user rows ordered by uid, not just the invite', async () => {
    seedUser('uid-a');
    seedUser('uid-z');
    // The redeemer is passed first but sorts last, so param order and lock order differ: an
    // implementation that locked in param order would produce z-then-a here.
    seedInvite('ABC234', 'uid-a');

    await redeem(app(), 'ABC234', 'uid-z');

    expect(events.filter((e) => e.startsWith('lock:'))).toEqual([
      'lock:invite:ABC234',
      'lock:user:uid-a',
      'lock:user:uid-z',
    ]);
  });

  it('two concurrent redemptions of DIFFERENT codes sharing one user create only ONE couple', async () => {
    seedUser('uid-x'); // the shared user: inviter on both codes
    seedUser('uid-a');
    seedUser('uid-b');
    seedInvite('AAA234', 'uid-x');
    seedInvite('BBB234', 'uid-x');
    const a = app();

    // Two codes, so locking the invite row alone serializes nothing: both transactions would read
    // uid-x with a null couple_id and both would pair it.
    const [first, second] = await bothSettle(
      redeem(a, 'AAA234', 'uid-a'),
      redeem(a, 'BBB234', 'uid-b'),
    );

    const codes = [first.statusCode, second.statusCode].sort();
    expect(codes).toEqual([200, 409]);
    expect(coupleIds()).toHaveLength(1);
    expect(users.get('uid-x')?.couple_id).toBe(coupleIds()[0]);
    // The loser is 409 inviter_already_paired: uid-x was taken by the winner.
    const loser = first.statusCode === 409 ? first : second;
    expect(loser.json()).toEqual({ error: 'inviter_already_paired' });
  });

  it('does not deadlock when two codes between the SAME pair redeem in opposite directions', async () => {
    // uid-a and uid-z each sent the other a code, and both tap Join at once. The two transactions
    // want the same two rows in opposite param orders — `ORDER BY uid` is the only thing that
    // stops them holding one row each and waiting forever for the other.
    seedUser('uid-a');
    seedUser('uid-z');
    seedInvite('AAA234', 'uid-z'); // uid-a redeems: params (uid-a, uid-z)
    seedInvite('ZZZ234', 'uid-a'); // uid-z redeems: params (uid-z, uid-a)
    const a = app();

    const [first, second] = await bothSettle(
      redeem(a, 'AAA234', 'uid-a'),
      redeem(a, 'ZZZ234', 'uid-z'),
    );

    expect([first.statusCode, second.statusCode].sort()).toEqual([200, 409]);
    expect(coupleIds()).toHaveLength(1);
  });

  it('uses SELECT ... FOR UPDATE and performs every write in one transaction', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a');

    await redeem(app(), 'ABC234', 'uid-b');

    const tx = events.filter((e) => e.startsWith('tx:')).map((e) => e.slice(3));
    expect(tx[0]).toMatch(/^SELECT .* FROM invites WHERE code = \$1 FOR UPDATE$/);
    expect(tx[1]).toBe(
      'SELECT uid, couple_id, timezone FROM users WHERE uid IN ($1, $2) ORDER BY uid FOR UPDATE',
    );
    // Every write went through the transaction, none through the pool, and all before one COMMIT.
    expect(tx.filter((s) => /^(INSERT|UPDATE|DELETE)/.test(s))).toHaveLength(3);
    expect(events.filter((e) => e === 'COMMIT')).toHaveLength(1);
    expect(events.filter((e) => e.startsWith('pool:'))).toEqual([]);
    // And no network call inside the transaction: both side effects follow the COMMIT.
    const commit = events.indexOf('COMMIT');
    expect(events.findIndex((e) => e.startsWith('refresh:'))).toBeGreaterThan(commit);
    expect(events.findIndex((e) => e.startsWith('ws:'))).toBeGreaterThan(commit);
  });

  it('rolls back completely on a mid-transaction failure — no orphan couple row', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a');
    failOn = 'UPDATE users SET couple_id'; // fails AFTER the couple insert

    const res = await redeem(app(), 'ABC234', 'uid-b');

    expect(res.statusCode).toBe(500);
    expect(events).toContain('ROLLBACK');
    expect(events).not.toContain('COMMIT');
    expect(couples.size).toBe(0);
    expect(invites.get('ABC234')?.status).toBe('pending');
    expect(users.get('uid-a')?.couple_id).toBeNull();
    expect(users.get('uid-b')?.couple_id).toBeNull();
    // A failed pairing must not announce itself.
    expect(refreshOverlap).not.toHaveBeenCalled();
    expect(sendTo).not.toHaveBeenCalled();
  });

  it('triggers refreshOverlap and a pairing WS message to the inviter', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a');

    const { couple_id } = (await redeem(app(), 'ABC234', 'uid-b')).json<{ couple_id: string }>();

    // triggeredBy is the redeemer, so the redeemer is not pushed for their own action.
    expect(refreshOverlap).toHaveBeenCalledWith(couple_id, 'uid-b', expect.anything());
    expect(sendTo).toHaveBeenCalledExactlyOnceWith('uid-a', {
      t: 'pairing',
      couple_id,
      partner_uid: 'uid-b',
    });
  });

  it('still answers 200 when the post-commit overlap refresh fails — the pairing is committed', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedInvite('ABC234', 'uid-a');
    vi.mocked(refreshOverlap).mockRejectedValueOnce(new Error('engine blew up'));

    const res = await redeem(app(), 'ABC234', 'uid-b');

    expect(res.statusCode).toBe(200);
    expect(users.get('uid-b')?.couple_id).toBe(coupleIds()[0]);
    expect(sendTo).toHaveBeenCalledTimes(1);
  });
});
