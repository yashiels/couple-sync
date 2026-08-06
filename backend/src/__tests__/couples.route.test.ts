import Fastify, { type FastifyInstance, type FastifyBaseLogger } from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Querier } from '../db.js';
import type { OverlapWindow } from '../overlap/types.js';
import type { BlockRow, CoupleRow, UserRow } from '../wire.js';

// The REAL overlapService runs here, against the same fake database and the same simulated advisory
// lock as the unpair route. That is the only way to assert the resurrection hazard for real: with
// refreshOverlap mocked, an unpair with the lock removed would still look correct.
vi.mock('../firebase.js', () => ({ verifyIdToken: vi.fn() }));
vi.mock('../db.js', () => ({ query: vi.fn(), withTx: vi.fn() }));
vi.mock('../sockets.js', () => ({ sendTo: vi.fn(() => true) }));
vi.mock('../push.js', () => ({ pushOverlapChanged: vi.fn(async () => {}) }));

const { verifyIdToken } = await import('../firebase.js');
const { query, withTx } = await import('../db.js');
const { sendTo } = await import('../sockets.js');
const { registerErrorHandler } = await import('../http.js');
const { refreshOverlap } = await import('../overlapService.js');
const couplesRoutes = (await import('../routes/couples.js')).default;

const JHB = 'Africa/Johannesburg';
const NY = 'America/New_York';
const NOW = Date.parse('2026-06-03T10:00:00Z');
const DAY = 86_400_000;

interface Stored {
  couple_id: string;
  windows: OverlapWindow[];
  computed_at: number;
  input_hash: string;
}

const users = new Map<string, UserRow>();
const couples = new Map<string, CoupleRow>();
let timeblocks: BlockRow[] = [];
const overlaps = new Map<string, Stored>();
/** Statements and markers, in the order they happened. */
let events: string[] = [];
const locks = new Map<string, Promise<void>>();
let failOn: string | null = null;
/** Held by the NEXT overlap load, so a refresh can be parked mid-transaction. */
let gate: Promise<void> | null = null;

const log = { warn: vi.fn(), error: vi.fn(), info: vi.fn() } as unknown as FastifyBaseLogger;

function seedUser(uid: string, over: Partial<UserRow> = {}): UserRow {
  const row: UserRow = {
    uid,
    email: `${uid}@example.com`,
    display_name: null,
    photo_url: null,
    timezone: JHB,
    couple_id: 'c1',
    show_late_night_windows: false,
    notifications_enabled: true,
    fcm_tokens: [`tok-${uid}`],
    created_at: 1,
    ...over,
  };
  users.set(uid, row);
  return row;
}

function seedCouple(over: Partial<CoupleRow> = {}): CoupleRow {
  const row: CoupleRow = {
    id: 'c1',
    user_a_uid: 'uid-a',
    user_b_uid: 'uid-b',
    status: 'active',
    paired_at: 1,
    created_at: 1,
    ...over,
  };
  couples.set(row.id, row);
  return row;
}

function seedBlock(id: string, over: Partial<BlockRow> = {}): BlockRow {
  const row: BlockRow = {
    id,
    couple_id: 'c1',
    user_id: 'uid-a',
    title: 'gym',
    type: 'busy',
    category: null,
    start_utc: NOW + DAY,
    end_utc: NOW + DAY + 3_600_000,
    timezone: JHB,
    recurrence_rule: null,
    source: 'manual',
    visibility: 'bothPartners',
    created_at: 1,
    ...over,
  };
  timeblocks.push(row);
  return row;
}

function seedPair(): void {
  seedCouple();
  seedUser('uid-a');
  seedUser('uid-b', { timezone: NY });
}

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
}

async function runInTx(
  sql: string,
  params: unknown[],
  staged: (() => void)[],
  releasers: (() => void)[],
): Promise<Record<string, unknown>[]> {
  events.push(`tx:${sql.replace(/\s+/g, ' ').trim()}`);
  // Yield per statement so two transactions really interleave. Without it a handler runs to COMMIT
  // inside one microtask drain and a missing lock is invisible.
  await new Promise((res) => setImmediate(res));
  if (failOn && sql.includes(failOn)) throw new Error('constraint violation');

  if (sql.includes('pg_advisory_xact_lock')) {
    await acquire(String(params[0]), releasers);
    return [];
  }

  // overlapService's loader: one row, four columns.
  if (sql.includes('WITH cp AS')) {
    const couple = couples.get(String(params[0])) ?? null;
    const row = {
      couple,
      users: couple
        ? [users.get(couple.user_a_uid), users.get(couple.user_b_uid)].filter(Boolean)
        : null,
      blocks: timeblocks.filter((b) => b.couple_id === params[0]),
      stored: overlaps.get(String(params[0])) ?? null,
    };
    const held = gate;
    gate = null;
    if (held) await held;
    return [row];
  }

  if (sql.includes('INSERT INTO overlaps_latest')) {
    const [coupleId, windows, computedAt, hash] = params as [string, string, number, string];
    staged.push(() =>
      overlaps.set(coupleId, {
        couple_id: coupleId,
        windows: JSON.parse(windows) as OverlapWindow[],
        computed_at: computedAt,
        input_hash: hash,
      }),
    );
    return [];
  }

  if (/SELECT \* FROM couples WHERE id = \$1/.test(sql)) {
    const row = couples.get(String(params[0]));
    return row ? [{ ...row }] : [];
  }

  if (sql.includes('UPDATE couples SET')) {
    const id = String(params[0]);
    staged.push(() => {
      const row = couples.get(id);
      if (row) couples.set(id, { ...row, status: 'inactive' });
    });
    return [];
  }

  if (sql.includes('UPDATE users SET couple_id = NULL')) {
    const uids = params.map(String);
    staged.push(() => {
      for (const uid of uids) {
        const row = users.get(uid);
        if (row) users.set(uid, { ...row, couple_id: null });
      }
    });
    return [];
  }

  if (sql.includes('DELETE FROM timeblocks')) {
    const id = String(params[0]);
    staged.push(() => {
      timeblocks = timeblocks.filter((b) => b.couple_id !== id);
    });
    return [];
  }

  if (sql.includes('DELETE FROM overlaps_latest')) {
    const id = String(params[0]);
    staged.push(() => overlaps.delete(id));
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

/** The pool path: assertMember only. */
async function poolQuery(sql: string, params: unknown[] = []): Promise<Record<string, unknown>[]> {
  events.push(`pool:${sql.replace(/\s+/g, ' ').trim()}`);
  if (/SELECT \* FROM couples WHERE id = \$1/.test(sql)) {
    const row = couples.get(String(params[0]));
    return row ? [{ ...row }] : [];
  }
  throw new Error(`unrouted pool statement: ${sql}`);
}

function app(): FastifyInstance {
  const a = Fastify();
  registerErrorHandler(a);
  void a.register(couplesRoutes);
  return a;
}

const as = (uid: string) => ({ authorization: `Bearer ${uid}` });
const unpair = (a: FastifyInstance, id: string, uid: string) =>
  a.inject({ method: 'POST', url: `/couples/${id}/unpair`, headers: as(uid) });

/** Drains until an in-flight transaction has reached the given point. */
async function until(pred: () => boolean): Promise<void> {
  for (let i = 0; i < 200 && !pred(); i++) await new Promise((res) => setImmediate(res));
  expect(pred()).toBe(true);
}

const count = (needle: string) => events.filter((e) => e.includes(needle)).length;

beforeEach(() => {
  vi.clearAllMocks();
  users.clear();
  couples.clear();
  overlaps.clear();
  locks.clear();
  timeblocks = [];
  events = [];
  failOn = null;
  gate = null;
  vi.spyOn(Date, 'now').mockReturnValue(NOW);
  vi.mocked(verifyIdToken).mockImplementation(
    async (token: string) => ({ uid: token, sub: token }) as DecodedIdToken,
  );
  vi.mocked(query).mockImplementation(poolQuery as typeof query);
  vi.mocked(withTx).mockImplementation(fakeTx as typeof withTx);
});

describe('GET /couples/:id', () => {
  it('returns the couple for a member', async () => {
    const couple = seedCouple();

    const res = await app().inject({ method: 'GET', url: '/couples/c1', headers: as('uid-b') });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ couple });
  });

  it('403s for a non-member and for a non-existent id alike', async () => {
    seedCouple();
    const a = app();

    const stranger = await a.inject({ method: 'GET', url: '/couples/c1', headers: as('uid-x') });
    const ghost = await a.inject({ method: 'GET', url: '/couples/nope', headers: as('uid-a') });

    expect(stranger.statusCode).toBe(403);
    expect(ghost.statusCode).toBe(403);
    // Byte-identical, so a caller cannot tell an id that exists from one that does not.
    expect(ghost.body).toBe(stranger.body);
  });
});

describe('POST /couples/:id/unpair', () => {
  it('sets status inactive and nulls couple_id on both users', async () => {
    seedPair();

    const res = await unpair(app(), 'c1', 'uid-a');

    expect(res.statusCode).toBe(200);
    expect(couples.get('c1')?.status).toBe('inactive');
    expect(users.get('uid-a')?.couple_id).toBeNull();
    expect(users.get('uid-b')?.couple_id).toBeNull();
  });

  it('deletes every timeblock for the couple', async () => {
    seedPair();
    seedBlock('b1');
    seedBlock('b2', { user_id: 'uid-b' });
    seedBlock('b3', { couple_id: 'c2' }); // another couple's block

    await unpair(app(), 'c1', 'uid-a');

    expect(timeblocks.map((b) => b.id)).toEqual(['b3']);
  });

  it('deletes the overlaps_latest row', async () => {
    seedPair();
    overlaps.set('c1', { couple_id: 'c1', windows: [], computed_at: NOW, input_hash: 'h' });

    await unpair(app(), 'c1', 'uid-a');

    expect(overlaps.has('c1')).toBe(false);
  });

  it('broadcasts unpair to both partners', async () => {
    seedPair();

    await unpair(app(), 'c1', 'uid-a');

    expect(sendTo).toHaveBeenCalledTimes(2);
    expect(sendTo).toHaveBeenCalledWith('uid-a', { t: 'unpair', couple_id: 'c1' });
    expect(sendTo).toHaveBeenCalledWith('uid-b', { t: 'unpair', couple_id: 'c1' });
  });

  it('403s for a non-member, and for a non-existent couple', async () => {
    seedPair();
    seedBlock('b1');
    const a = app();

    const stranger = await unpair(a, 'c1', 'uid-x');
    const ghost = await unpair(a, 'nope', 'uid-a');

    expect(stranger.statusCode).toBe(403);
    expect(ghost.statusCode).toBe(403);
    expect(couples.get('c1')?.status).toBe('active');
    expect(timeblocks).toHaveLength(1);
    expect(sendTo).not.toHaveBeenCalled();
  });

  it('does all of it in one transaction', async () => {
    seedPair();
    seedBlock('b1');
    overlaps.set('c1', { couple_id: 'c1', windows: [], computed_at: NOW, input_hash: 'h' });

    await unpair(app(), 'c1', 'uid-a');

    const writes = events.filter((e) => /^tx:(UPDATE|DELETE)/.test(e));
    expect(writes).toHaveLength(4);
    expect(events.filter((e) => e === 'COMMIT')).toHaveLength(1);
    // Nothing was written outside the transaction, and the WS fan-out followed the COMMIT.
    expect(events.filter((e) => /^pool:(UPDATE|DELETE)/.test(e))).toEqual([]);
    const commit = events.indexOf('COMMIT');
    expect(writes.every((w) => events.indexOf(w) < commit)).toBe(true);
  });

  it('rolls back every write when one statement fails', async () => {
    seedPair();
    seedBlock('b1');
    overlaps.set('c1', { couple_id: 'c1', windows: [], computed_at: NOW, input_hash: 'h' });
    failOn = 'DELETE FROM overlaps_latest'; // the last write, so everything precedes it

    const res = await unpair(app(), 'c1', 'uid-a');

    expect(res.statusCode).toBe(500);
    expect(events).toContain('ROLLBACK');
    expect(couples.get('c1')?.status).toBe('active');
    expect(users.get('uid-a')?.couple_id).toBe('c1');
    expect(timeblocks).toHaveLength(1);
    expect(overlaps.has('c1')).toBe(true);
    expect(sendTo).not.toHaveBeenCalled();
  });

  it('takes the same pg_advisory_xact_lock(hashtext(coupleId)) as refreshOverlap', async () => {
    seedPair();

    await refreshOverlap('c1', null, log);
    const fromRefresh = events.filter((e) => e.includes('pg_advisory_xact_lock'));
    events = [];
    await unpair(app(), 'c1', 'uid-a');
    const fromUnpair = events.filter((e) => e.includes('pg_advisory_xact_lock'));

    // Identical statement text, identical key: two different lock expressions would not serialize.
    expect(fromUnpair).toEqual(fromRefresh);
    expect(fromUnpair[0]).toBe('tx:SELECT pg_advisory_xact_lock(hashtext($1))');
    // And it is the FIRST statement of the transaction, so nothing is read before the lock is held.
    expect(events[0]).toBe('tx:SELECT pg_advisory_xact_lock(hashtext($1))');
    expect(events[1]).toBe('lock:c1');
  });

  it('a refresh that started before an unpair does not recreate overlaps_latest afterwards', async () => {
    seedPair();
    const a = app();

    // Park a refresh mid-transaction: it holds the advisory lock and has already read the couple as
    // active, which is exactly the state that resurrects a row if unpair does not take the lock.
    let release!: () => void;
    gate = new Promise<void>((res) => {
      release = res;
    });
    const refreshing = refreshOverlap('c1', null, log);
    await until(() => events.some((e) => e.startsWith('tx:WITH cp AS')));

    const unpairing = unpair(a, 'c1', 'uid-a');
    // Every chance to run: the unpair transaction is queued behind the lock and gets no further.
    for (let i = 0; i < 20; i++) await new Promise((res) => setImmediate(res));
    expect(count('DELETE FROM overlaps_latest')).toBe(0);
    expect(couples.get('c1')?.status).toBe('active');

    release();
    await refreshing;
    await unpairing;

    // The refresh wrote its row, and the delete landed after it. Nothing survives the unpair.
    expect(count('INSERT INTO overlaps_latest')).toBe(1);
    expect(events.findIndex((e) => e.includes('DELETE FROM overlaps_latest'))).toBeGreaterThan(
      events.findIndex((e) => e.includes('INSERT INTO overlaps_latest')),
    );
    expect(overlaps.has('c1')).toBe(false);
    expect(couples.get('c1')?.status).toBe('inactive');
  });

  it('a refresh that starts after an unpair computes nothing for the dead couple', async () => {
    seedPair();

    await unpair(app(), 'c1', 'uid-a');
    const res = await refreshOverlap('c1', null, log);

    expect(res).toMatchObject({ windows: [], changed: false });
    expect(overlaps.has('c1')).toBe(false);
  });

  it('re-checks that the couple is still active under the lock', async () => {
    seedPair();
    seedBlock('b1');
    const a = app();

    // Both partners tap Unpair at the same moment. The second transaction blocks on the lock, then
    // reads status 'inactive' and must refuse — running the body twice would broadcast twice and
    // delete the other couple's-worth of nothing under a resurrected id.
    const [first, second] = await Promise.all([unpair(a, 'c1', 'uid-a'), unpair(a, 'c1', 'uid-b')]);

    expect([first.statusCode, second.statusCode].sort()).toEqual([200, 403]);
    expect(count('DELETE FROM timeblocks')).toBe(1);
    expect(count('COMMIT')).toBe(1);
    expect(sendTo).toHaveBeenCalledTimes(2); // one broadcast, two recipients
  });
});
