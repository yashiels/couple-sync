import Fastify, { type FastifyBaseLogger, type FastifyInstance } from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { DateTime } from 'luxon';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Querier } from '../db.js';
import type { OverlapWindow } from '../overlap/types.js';
import type { BlockRow, BlockWithOccurrences, CoupleRow, UserRow, WsMessage } from '../wire.js';

// The REAL overlapService runs here, wrapped in a spy: the write handlers must be observed calling
// it exactly once, AND the unpair races below are only meaningful if the refresh really takes the
// same advisory lock and really re-checks the couple's status.
vi.mock('../firebase.js', () => ({ verifyIdToken: vi.fn() }));
vi.mock('../db.js', () => ({ query: vi.fn(), withTx: vi.fn() }));
vi.mock('../sockets.js', () => ({ sendTo: vi.fn(() => true) }));
vi.mock('../push.js', () => ({ pushOverlapChanged: vi.fn(async () => {}) }));
vi.mock('../overlapService.js', async (importOriginal) => {
  const real = await importOriginal<typeof import('../overlapService.js')>();
  return { refreshOverlap: vi.fn(real.refreshOverlap) };
});

const { verifyIdToken } = await import('../firebase.js');
const { query, withTx } = await import('../db.js');
const { sendTo } = await import('../sockets.js');
const { registerErrorHandler } = await import('../http.js');
const { refreshOverlap } = await import('../overlapService.js');
const blocksRoutes = (await import('../routes/blocks.js')).default;
const couplesRoutes = (await import('../routes/couples.js')).default;

const JHB = 'Africa/Johannesburg';
const NY = 'America/New_York';
const NOW = Date.parse('2026-06-03T10:00:00Z');
const HOUR = 3_600_000;
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
/** Parks the first statement matching `gateOn` until the returned promise resolves. */
let gateOn: string | null = null;
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
    category: 'exercise',
    start_utc: NOW + DAY,
    end_utc: NOW + DAY + HOUR,
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

/** The row an INSERT INTO timeblocks builds, in the column order blocks.ts declares. */
function rowFromInsert(params: unknown[]): BlockRow {
  const [
    id,
    couple_id,
    user_id,
    title,
    type,
    category,
    start_utc,
    end_utc,
    timezone,
    recurrence_rule,
    source,
    visibility,
    created_at,
  ] = params;
  return {
    id,
    couple_id,
    user_id,
    title,
    type,
    category,
    start_utc,
    end_utc,
    timezone,
    recurrence_rule,
    source,
    visibility,
    created_at,
  } as BlockRow;
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
  if (gateOn && gate && sql.includes(gateOn)) {
    const held = gate;
    gate = null;
    await held;
  }

  if (sql.includes('pg_advisory_xact_lock')) {
    await acquire(String(params[0]), releasers);
    return [];
  }

  // overlapService's loader: one row, four columns.
  if (sql.includes('WITH cp AS')) {
    const couple = couples.get(String(params[0])) ?? null;
    return [
      {
        couple,
        users: couple
          ? [users.get(couple.user_a_uid), users.get(couple.user_b_uid)].filter(Boolean)
          : null,
        blocks: timeblocks.filter((b) => b.couple_id === params[0]),
        stored: overlaps.get(String(params[0])) ?? null,
      },
    ];
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

  // Batched calendar insert: parallel arrays through unnest (id[], start[], end[]) + scalar columns.
  if (sql.includes('INSERT INTO timeblocks') && sql.includes('unnest')) {
    const ids = params[0] as string[];
    const [, coupleId, uid, title, timezone, source, createdAt, starts, ends] = params as [
      unknown,
      string,
      string,
      string,
      string,
      string,
      number,
      number[],
      number[],
    ];
    const rows = ids.map(
      (id, i) =>
        ({
          id,
          couple_id: coupleId,
          user_id: uid,
          title,
          type: 'busy',
          category: null,
          start_utc: starts[i],
          end_utc: ends[i],
          timezone,
          recurrence_rule: null,
          source,
          visibility: 'bothPartners',
          created_at: createdAt,
        }) as BlockRow,
    );
    staged.push(() => {
      for (const r of rows) timeblocks.push(r);
    });
    return rows.map((r) => ({ ...r }));
  }

  if (sql.includes('INSERT INTO timeblocks')) {
    const row = rowFromInsert(params);
    staged.push(() => timeblocks.push(row));
    return [{ ...row }];
  }

  if (/SELECT \* FROM timeblocks WHERE id = \$1 AND couple_id = \$2/.test(sql)) {
    const row = timeblocks.find((b) => b.id === params[0] && b.couple_id === params[1]);
    return row ? [{ ...row }] : [];
  }

  if (sql.includes('UPDATE timeblocks SET')) {
    const row = timeblocks.find((b) => b.id === params[0] && b.couple_id === params[1]);
    if (!row) return [];
    const patched = { ...row } as Record<string, unknown>;
    for (const [, column, index] of sql.matchAll(/(\w+) = \$(\d+)/g)) {
      patched[column!] = params[Number(index) - 1];
    }
    staged.push(() => {
      timeblocks = timeblocks.map((b) => (b.id === row.id ? (patched as unknown as BlockRow) : b));
    });
    return [{ ...patched }];
  }

  // The calendar whole-set delete (scoped to one source via $3), before the broader matches below.
  if (sql.includes('DELETE FROM timeblocks') && sql.includes('source = $3')) {
    const [coupleId, uid, source] = params.map(String);
    staged.push(() => {
      timeblocks = timeblocks.filter(
        (b) => !(b.couple_id === coupleId && b.user_id === uid && b.source === source),
      );
    });
    return [];
  }

  if (/DELETE FROM timeblocks WHERE id = \$1/.test(sql)) {
    const id = String(params[0]);
    staged.push(() => {
      timeblocks = timeblocks.filter((b) => b.id !== id);
    });
    return [];
  }

  if (sql.includes('SELECT timezone FROM users WHERE uid = $1')) {
    const row = users.get(String(params[0]));
    return row ? [{ timezone: row.timezone }] : [];
  }

  if (/SELECT \* FROM couples WHERE id = \$1/.test(sql)) {
    const row = couples.get(String(params[0]));
    return row ? [{ ...row }] : [];
  }

  // ---- unpair, so the block writes can be raced against it ----
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

  if (/DELETE FROM timeblocks WHERE couple_id = \$1/.test(sql)) {
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

/** The pool path: assertMember plus the two reads. */
async function poolQuery(sql: string, params: unknown[] = []): Promise<Record<string, unknown>[]> {
  events.push(`pool:${sql.replace(/\s+/g, ' ').trim()}`);
  if (/SELECT \* FROM couples WHERE id = \$1/.test(sql)) {
    const row = couples.get(String(params[0]));
    return row ? [{ ...row }] : [];
  }
  if (/SELECT \* FROM timeblocks WHERE couple_id = \$1/.test(sql)) {
    return timeblocks
      .filter((b) => b.couple_id === params[0])
      .sort((x, y) => x.start_utc - y.start_utc)
      .map((b) => ({ ...b }));
  }
  if (/SELECT \* FROM timeblocks WHERE id = \$1 AND couple_id = \$2/.test(sql)) {
    const row = timeblocks.find((b) => b.id === params[0] && b.couple_id === params[1]);
    return row ? [{ ...row }] : [];
  }
  throw new Error(`unrouted pool statement: ${sql}`);
}

function app(): FastifyInstance {
  const a = Fastify();
  registerErrorHandler(a);
  void a.register(blocksRoutes);
  void a.register(couplesRoutes);
  return a;
}

const as = (uid: string) => ({ authorization: `Bearer ${uid}` });

const body = (over: Record<string, unknown> = {}) => ({
  couple_id: 'c1',
  title: 'gym',
  type: 'busy',
  start_utc: NOW + HOUR,
  end_utc: NOW + 2 * HOUR,
  timezone: JHB,
  ...over,
});

const post = (payload: Record<string, unknown>, uid = 'uid-a', a = app()) =>
  a.inject({ method: 'POST', url: '/blocks', headers: as(uid), payload });

const patch = (id: string, payload: Record<string, unknown>, uid = 'uid-a') =>
  app().inject({ method: 'PATCH', url: `/blocks/${id}`, headers: as(uid), payload });

const del = (id: string, uid = 'uid-a', coupleId = 'c1') =>
  app().inject({ method: 'DELETE', url: `/blocks/${id}?coupleId=${coupleId}`, headers: as(uid) });

const putGoogle = (payload: Record<string, unknown>, uid = 'uid-a', a = app()) =>
  a.inject({ method: 'PUT', url: '/blocks/google', headers: as(uid), payload });

const list = (uid = 'uid-a', from = NOW, to = NOW + 7 * DAY, coupleId = 'c1') =>
  app().inject({
    method: 'GET',
    url: `/blocks?coupleId=${coupleId}&from=${from}&to=${to}`,
    headers: as(uid),
  });

const one = (id: string, uid = 'uid-a', coupleId = 'c1') =>
  app().inject({ method: 'GET', url: `/blocks/${id}?coupleId=${coupleId}`, headers: as(uid) });

const unpair = (a: FastifyInstance, uid = 'uid-a', id = 'c1') =>
  a.inject({ method: 'POST', url: `/couples/${id}/unpair`, headers: as(uid) });

const blocksOf = (res: { json: <T>() => T }) => res.json<{ blocks: BlockWithOccurrences[] }>().blocks;
const byId = (res: { json: <T>() => T }, id: string) => blocksOf(res).find((b) => b.id === id)!;

/** WS messages of one type, across every recipient. */
const msgs = (t: WsMessage['t']) =>
  vi.mocked(sendTo).mock.calls.filter(([, m]) => m.t === t) as [string, WsMessage][];

/** Drains until an in-flight transaction has reached the given point. */
async function until(pred: () => boolean): Promise<void> {
  for (let i = 0; i < 200 && !pred(); i++) await new Promise((res) => setImmediate(res));
  expect(pred()).toBe(true);
}

async function drain(turns = 20): Promise<void> {
  for (let i = 0; i < turns; i++) await new Promise((res) => setImmediate(res));
}

function park(statement: string): () => void {
  gateOn = statement;
  let release!: () => void;
  gate = new Promise<void>((res) => {
    release = res;
  });
  return release;
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
  gateOn = null;
  gate = null;
  vi.spyOn(Date, 'now').mockReturnValue(NOW);
  vi.mocked(verifyIdToken).mockImplementation(
    async (token: string) => ({ uid: token, sub: token }) as DecodedIdToken,
  );
  vi.mocked(query).mockImplementation(poolQuery as typeof query);
  vi.mocked(withTx).mockImplementation(fakeTx as typeof withTx);
});

describe('GET /blocks', () => {
  it('returns both partners blocks for a member', async () => {
    seedPair();
    seedBlock('b1');
    seedBlock('b2', { user_id: 'uid-b' });
    seedBlock('b3', { couple_id: 'c2' });

    const res = await list('uid-a');

    expect(res.statusCode).toBe(200);
    expect(blocksOf(res).map((b) => b.id)).toEqual(['b1', 'b2']);
  });

  it('403s for a non-member', async () => {
    seedPair();
    seedBlock('b1');

    const res = await list('uid-x');

    expect(res.statusCode).toBe(403);
    expect(res.json()).toEqual({ error: 'forbidden' });
  });

  it('nulls title and category on the partners onlyMe blocks', async () => {
    seedPair();
    seedBlock('b1', { user_id: 'uid-b', visibility: 'onlyMe', title: 'therapy' });

    const res = await list('uid-a');

    expect(byId(res, 'b1')).toMatchObject({ title: null, category: null });
    expect(res.body).not.toContain('therapy');
    // The interval itself is never dropped: the partner still needs it on the calendar.
    expect(byId(res, 'b1').start_utc).toBe(NOW + DAY);
  });

  it('keeps title and category on the callers own onlyMe blocks', async () => {
    seedPair();
    seedBlock('b1', { user_id: 'uid-a', visibility: 'onlyMe', title: 'therapy' });

    const res = await list('uid-a');

    expect(byId(res, 'b1')).toMatchObject({ title: 'therapy', category: 'exercise' });
  });
});

describe('GET /blocks/:id', () => {
  it('nulls title and category on the partners onlyMe block', async () => {
    seedPair();
    seedBlock('b1', { user_id: 'uid-b', visibility: 'onlyMe', title: 'therapy' });

    const res = await one('b1', 'uid-a');

    expect(res.statusCode).toBe(200);
    expect(res.json<{ block: BlockRow }>().block).toMatchObject({ title: null, category: null });
    expect(res.body).not.toContain('therapy');
  });

  it('keeps title and category on the callers own onlyMe block', async () => {
    seedPair();
    seedBlock('b1', { user_id: 'uid-a', visibility: 'onlyMe', title: 'therapy' });

    const res = await one('b1', 'uid-a');

    expect(res.json<{ block: BlockRow }>().block).toMatchObject({
      title: 'therapy',
      category: 'exercise',
    });
  });

  it('403s for a block belonging to another couple', async () => {
    seedPair();
    seedCouple({ id: 'c2', user_a_uid: 'uid-c', user_b_uid: 'uid-d' });
    seedBlock('foreign', { couple_id: 'c2', user_id: 'uid-c', title: 'affair' });

    // Both spellings of the attack: naming the other couple, and naming your own.
    const viaTheirCouple = await one('foreign', 'uid-a', 'c2');
    const viaMine = await one('foreign', 'uid-a', 'c1');

    expect(viaTheirCouple.statusCode).toBe(403);
    expect(viaMine.statusCode).toBe(403);
    expect(viaMine.body).toBe(viaTheirCouple.body);
    expect(viaMine.body).not.toContain('affair');
  });
});

describe('POST /blocks', () => {
  it('400s on an empty title', async () => {
    seedPair();

    for (const title of ['', '   ', null, 42]) {
      const res = await post(body({ title }));
      expect(res.statusCode).toBe(400);
      expect(res.json()).toMatchObject({ error: 'invalid_title' });
    }
    expect(timeblocks).toHaveLength(0);
  });

  it('400s when end_utc <= start_utc', async () => {
    seedPair();

    const equal = await post(body({ start_utc: NOW, end_utc: NOW }));
    const inverted = await post(body({ start_utc: NOW + HOUR, end_utc: NOW }));

    expect(equal.statusCode).toBe(400);
    expect(inverted.statusCode).toBe(400);
    expect(inverted.json()).toMatchObject({ error: 'invalid_interval' });
    expect(timeblocks).toHaveLength(0);
  });

  it('400s on an invalid IANA timezone', async () => {
    seedPair();

    for (const timezone of ['SAST', '+02:00', 'Mars/Olympus', '']) {
      const res = await post(body({ timezone }));
      expect(res.statusCode).toBe(400);
      expect(res.json()).toMatchObject({ error: 'invalid_timezone' });
    }
    expect(timeblocks).toHaveLength(0);
  });

  it('400s on an unparseable recurrence rule', async () => {
    seedPair();

    for (const recurrence_rule of ['nonsense', 'FREQ=BOGUS', 'FREQ=DAILY;BYDAY=XX', '', 7]) {
      const res = await post(body({ recurrence_rule }));
      expect(res.statusCode).toBe(400);
      expect(res.json()).toMatchObject({ error: 'invalid_recurrence_rule' });
    }
    expect(timeblocks).toHaveLength(0);
  });

  it('400s on a rule with no explicit FREQ', async () => {
    seedPair();
    // rrulestr defaults a missing FREQ to YEARLY, so these would otherwise be stored as rules the
    // recurrence picker cannot round-trip.
    for (const recurrence_rule of ['BYDAY=MO', 'INTERVAL=2', 'COUNT=3', 'RRULE:BYDAY=TU,WE']) {
      const res = await post(body({ recurrence_rule }));
      expect(res.statusCode).toBe(400);
      expect(res.json()).toMatchObject({ error: 'invalid_recurrence_rule' });
    }
  });

  it('400s on an unsupported RRULE FREQ', async () => {
    seedPair();

    for (const recurrence_rule of ['FREQ=HOURLY', 'FREQ=MINUTELY', 'RRULE:FREQ=SECONDLY']) {
      const res = await post(body({ recurrence_rule }));
      expect(res.statusCode).toBe(400);
      expect(res.json()).toMatchObject({ error: 'unsupported_recurrence_freq' });
    }
    // …and the four the engine does support are accepted.
    for (const recurrence_rule of [
      'FREQ=DAILY',
      'FREQ=WEEKLY;BYDAY=TU,WE',
      'RRULE:FREQ=MONTHLY;INTERVAL=2',
      'FREQ=YEARLY;COUNT=3',
    ]) {
      const res = await post(body({ recurrence_rule }));
      expect(res.statusCode).toBe(201);
    }
  });

  it('forces user_id to the caller, ignoring any user_id in the body', async () => {
    seedPair();

    const res = await post(body({ user_id: 'uid-b' }), 'uid-a');

    expect(res.statusCode).toBe(201);
    expect(res.json<{ block: BlockRow }>().block.user_id).toBe('uid-a');
    expect(timeblocks[0]?.user_id).toBe('uid-a');
  });

  it('forces source to manual, ignoring any source in the body', async () => {
    seedPair();

    const res = await post(body({ source: 'google' }));

    expect(res.statusCode).toBe(201);
    expect(res.json<{ block: BlockRow }>().block.source).toBe('manual');
    expect(timeblocks[0]?.source).toBe('manual');
  });

  it('triggers refreshOverlap and broadcasts block:set', async () => {
    seedPair();

    const res = await post(body({ title: 'dinner' }));

    expect(res.statusCode).toBe(201);
    const created = res.json<{ block: BlockRow }>().block;
    expect(refreshOverlap).toHaveBeenCalledExactlyOnceWith('c1', 'uid-a', expect.anything());
    expect(msgs('block:set').map(([uid]) => uid)).toEqual(['uid-a', 'uid-b']);
    expect(msgs('block:set')[0]?.[1]).toEqual({ t: 'block:set', block: created });
    // The write really landed, and the recompute saw it.
    expect(overlaps.get('c1')?.input_hash).toBeTruthy();
  });
});

describe('PATCH /blocks/:id', () => {
  it('403s when the caller does not own the block', async () => {
    seedPair();
    seedBlock('b1', { user_id: 'uid-b' });

    const res = await patch('b1', { couple_id: 'c1', title: 'hacked' }, 'uid-a');

    expect(res.statusCode).toBe(403);
    expect(timeblocks[0]?.title).toBe('gym');
    expect(refreshOverlap).not.toHaveBeenCalled();
  });

  it('403s on a google-sourced block', async () => {
    seedPair();
    seedBlock('b1', { source: 'google' });

    const res = await patch('b1', { couple_id: 'c1', title: 'renamed' }, 'uid-a');

    expect(res.statusCode).toBe(403);
    expect(res.json()).toEqual({ error: 'read_only_block' });
    expect(timeblocks[0]?.title).toBe('gym');
  });

  it('triggers refreshOverlap and broadcasts block:set', async () => {
    seedPair();
    seedBlock('b1');

    const res = await patch('b1', { couple_id: 'c1', title: 'yoga', end_utc: NOW + DAY + 2 * HOUR });

    expect(res.statusCode).toBe(200);
    expect(res.json<{ block: BlockRow }>().block).toMatchObject({
      title: 'yoga',
      end_utc: NOW + DAY + 2 * HOUR,
    });
    expect(timeblocks[0]).toMatchObject({ title: 'yoga' });
    expect(refreshOverlap).toHaveBeenCalledExactlyOnceWith('c1', 'uid-a', expect.anything());
    expect(msgs('block:set').map(([uid]) => uid)).toEqual(['uid-a', 'uid-b']);
  });

  it('400s when the patched interval inverts against the stored other end', async () => {
    seedPair();
    seedBlock('b1');

    const res = await patch('b1', { couple_id: 'c1', start_utc: NOW + 5 * DAY });

    expect(res.statusCode).toBe(400);
    expect(res.json()).toMatchObject({ error: 'invalid_interval' });
    expect(timeblocks[0]?.start_utc).toBe(NOW + DAY);
  });
});

describe('DELETE /blocks/:id', () => {
  it('403s when the caller does not own the block', async () => {
    seedPair();
    seedBlock('b1', { user_id: 'uid-b' });

    const res = await del('b1', 'uid-a');

    expect(res.statusCode).toBe(403);
    expect(timeblocks).toHaveLength(1);
    expect(refreshOverlap).not.toHaveBeenCalled();
  });

  it('triggers refreshOverlap and broadcasts block:del', async () => {
    seedPair();
    seedBlock('b1', { visibility: 'onlyMe', title: 'therapy' });

    const res = await del('b1', 'uid-a');

    expect(res.statusCode).toBe(200);
    expect(timeblocks).toHaveLength(0);
    expect(refreshOverlap).toHaveBeenCalledExactlyOnceWith('c1', 'uid-a', expect.anything());
    expect(msgs('block:del').map(([uid]) => uid)).toEqual(['uid-a', 'uid-b']);
    expect(msgs('block:del')[0]?.[1]).toEqual({ t: 'block:del', id: 'b1' });
  });
});

describe('PUT /blocks/google', () => {
  const iv = (dayOffset: number) => ({
    start_utc: NOW + dayOffset * DAY,
    end_utc: NOW + dayOffset * DAY + HOUR,
  });

  it('replaces only the callers google blocks, leaving manual blocks alone', async () => {
    seedPair();
    seedBlock('old-google', { source: 'google' });
    seedBlock('manual', { source: 'manual' });

    const res = await putGoogle({ couple_id: 'c1', intervals: [iv(2), iv(3)] });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ count: 2 });
    expect(timeblocks.map((b) => b.id)).toContain('manual');
    expect(timeblocks.map((b) => b.id)).not.toContain('old-google');
    expect(timeblocks.filter((b) => b.source === 'google')).toHaveLength(2);
  });

  it('leaves the partners google blocks alone', async () => {
    seedPair();
    seedBlock('theirs', { user_id: 'uid-b', source: 'google' });

    await putGoogle({ couple_id: 'c1', intervals: [iv(2)] }, 'uid-a');

    expect(timeblocks.map((b) => b.id)).toContain('theirs');
  });

  it('replaces only the named source — device and google are independent', async () => {
    seedPair();
    seedBlock('old-google', { source: 'google' });
    seedBlock('old-device', { source: 'device' });

    // Posting device leaves google untouched...
    await putGoogle({ couple_id: 'c1', intervals: [iv(2)], source: 'device' });
    expect(timeblocks.map((b) => b.id)).toContain('old-google');
    expect(timeblocks.map((b) => b.id)).not.toContain('old-device');
    expect(timeblocks.filter((b) => b.source === 'device')).toHaveLength(1);

    // ...and posting google leaves the freshly-written device set untouched.
    await putGoogle({ couple_id: 'c1', intervals: [iv(4)], source: 'google' });
    expect(timeblocks.filter((b) => b.source === 'device')).toHaveLength(1);
    expect(timeblocks.filter((b) => b.source === 'google')).toHaveLength(1);
    expect(timeblocks.map((b) => b.id)).not.toContain('old-google');
  });

  it('defaults source to google when omitted', async () => {
    seedPair();
    await putGoogle({ couple_id: 'c1', intervals: [iv(1)] });
    expect(timeblocks.filter((b) => b.source === 'google')).toHaveLength(1);
  });

  it('400s an invalid source', async () => {
    seedPair();
    const res = await putGoogle({ couple_id: 'c1', intervals: [iv(1)], source: 'manual' });
    expect(res.statusCode).toBe(400);
  });

  it('400s an unexpected body field (no title/category/summary can ride along)', async () => {
    seedPair();
    const res = await putGoogle({ couple_id: 'c1', intervals: [iv(1)], summary: 'lunch' });
    expect(res.statusCode).toBe(400);
  });

  it('400s a payload over the interval cap instead of inserting it', async () => {
    seedPair();
    const intervals = Array.from({ length: 1001 }, (_, i) => iv(i));
    const res = await putGoogle({ couple_id: 'c1', intervals });
    expect(res.statusCode).toBe(400);
    expect(timeblocks).toHaveLength(0);
  });

  it('is atomic — a mid-insert failure leaves the old set intact', async () => {
    seedPair();
    seedBlock('old-google', { source: 'google' });
    failOn = 'INSERT INTO timeblocks';

    const res = await putGoogle({ couple_id: 'c1', intervals: [iv(2), iv(3)] });

    expect(res.statusCode).toBe(500);
    expect(events).toContain('ROLLBACK');
    expect(timeblocks.map((b) => b.id)).toEqual(['old-google']);
    expect(refreshOverlap).not.toHaveBeenCalled();
    expect(sendTo).not.toHaveBeenCalled();
  });

  it('forces type=busy, source=google and a placeholder title on every entry', async () => {
    seedPair();

    await putGoogle({ couple_id: 'c1', intervals: [iv(1), iv(2), iv(3)] });

    expect(timeblocks).toHaveLength(3);
    for (const b of timeblocks) {
      expect(b).toMatchObject({
        type: 'busy',
        source: 'google',
        category: null,
        recurrence_rule: null,
        user_id: 'uid-a',
        couple_id: 'c1',
        timezone: JHB, // the caller's own zone, not something the body asserted
      });
      expect(b.title).toBe('Busy');
    }
  });

  it('rejects a payload carrying a title', async () => {
    seedPair();
    seedBlock('old-google', { source: 'google' });

    for (const payload of [
      { couple_id: 'c1', intervals: [{ ...iv(1), title: 'Dentist' }] },
      { couple_id: 'c1', intervals: [{ ...iv(1), summary: 'Dentist' }] },
      { couple_id: 'c1', intervals: [{ ...iv(1), category: 'work' }] },
      { couple_id: 'c1', title: 'Dentist', intervals: [iv(1)] },
    ]) {
      const res = await putGoogle(payload);
      expect(res.statusCode).toBe(400);
      expect(res.json()).toMatchObject({ error: 'title_not_allowed' });
    }
    // Nothing was written, so a title cannot even reach the table transiently.
    expect(timeblocks.map((b) => b.id)).toEqual(['old-google']);
    expect(JSON.stringify(timeblocks)).not.toContain('Dentist');
  });

  it('triggers exactly one refreshOverlap for the whole batch', async () => {
    seedPair();

    await putGoogle({ couple_id: 'c1', intervals: [iv(1), iv(2), iv(3), iv(4)] });

    expect(refreshOverlap).toHaveBeenCalledExactlyOnceWith('c1', 'uid-a', expect.anything());
    expect(count('INSERT INTO overlaps_latest')).toBe(1);
  });

  it('broadcasts exactly ONE blocks:changed, not one block:set per interval', async () => {
    seedPair();

    await putGoogle({ couple_id: 'c1', intervals: [iv(1), iv(2), iv(3), iv(4)] });

    // One message, two recipients — N block:set messages would cost the client N ranged refetches.
    expect(msgs('block:set')).toHaveLength(0);
    expect(msgs('blocks:changed').map(([uid, m]) => [uid, m])).toEqual([
      ['uid-a', { t: 'blocks:changed', couple_id: 'c1' }],
      ['uid-b', { t: 'blocks:changed', couple_id: 'c1' }],
    ]);
  });

  it('with an empty interval list still broadcasts blocks:changed', async () => {
    seedPair();
    seedBlock('old-google', { source: 'google' });

    const res = await putGoogle({ couple_id: 'c1', intervals: [] });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ count: 0 });
    expect(timeblocks).toHaveLength(0);
    // An empty replacement cannot be expressed as a block:set at all — this is the case that needs it.
    expect(msgs('blocks:changed')).toHaveLength(2);
    expect(refreshOverlap).toHaveBeenCalledExactlyOnceWith('c1', 'uid-a', expect.anything());
  });
});

describe('a write racing an unpair', () => {
  it('a block create that starts before an unpair commits does not survive it', async () => {
    seedPair();
    const a = app();

    // The create holds the couple's advisory lock and has already read the couple as active.
    const release = park('INSERT INTO timeblocks');
    const creating = post(body(), 'uid-a', a);
    await until(() => events.some((e) => e.startsWith('tx:INSERT INTO timeblocks')));

    const unpairing = unpair(a);
    await drain();
    // The unpair is queued behind the lock and got nowhere.
    expect(count('DELETE FROM timeblocks')).toBe(0);

    release();
    await creating;
    await unpairing;

    // Whichever order the two refreshes and the unpair settled in, nothing survives for a dead couple.
    expect(couples.get('c1')?.status).toBe('inactive');
    expect(timeblocks).toHaveLength(0);
    expect(overlaps.has('c1')).toBe(false);
  });

  it('an unpair that starts before a block create still leaves no blocks behind', async () => {
    seedPair();
    const a = app();

    const release = park('DELETE FROM timeblocks');
    const unpairing = unpair(a);
    await until(() => events.some((e) => e.startsWith('tx:DELETE FROM timeblocks')));

    // assertMember runs here, before the lock is taken, and still sees an ACTIVE couple — which is
    // exactly why the re-check under the lock has to exist.
    const creating = post(body(), 'uid-a', a);
    await drain();
    release();
    const created = await creating;
    await unpairing;

    expect(created.statusCode).toBe(403);
    expect(timeblocks).toHaveLength(0);
    expect(overlaps.has('c1')).toBe(false);
  });

  it('PUT /blocks/google racing an unpair does not repopulate blocks', async () => {
    seedPair();
    const a = app();

    const release = park('INSERT INTO timeblocks');
    const putting = putGoogle(
      { couple_id: 'c1', intervals: [{ start_utc: NOW + DAY, end_utc: NOW + DAY + HOUR }] },
      'uid-a',
      a,
    );
    await until(() => events.some((e) => e.startsWith('tx:INSERT INTO timeblocks')));

    const unpairing = unpair(a);
    await drain();
    release();
    await putting;
    await unpairing;

    expect(couples.get('c1')?.status).toBe('inactive');
    expect(timeblocks).toHaveLength(0);
    expect(overlaps.has('c1')).toBe(false);
  });

  it('refreshOverlap refuses to upsert for an inactive couple', async () => {
    seedCouple({ status: 'inactive' });
    seedUser('uid-a');
    seedUser('uid-b', { timezone: NY });

    const res = await refreshOverlap('c1', null, log);

    expect(res).toMatchObject({ windows: [], changed: false });
    expect(count('INSERT INTO overlaps_latest')).toBe(0);
    expect(overlaps.has('c1')).toBe(false);
  });
});

describe('GET /blocks occurrences', () => {
  it('400s when from or to is missing', async () => {
    seedPair();
    const a = app();

    for (const url of [
      '/blocks?coupleId=c1',
      `/blocks?coupleId=c1&from=${NOW}`,
      `/blocks?coupleId=c1&to=${NOW + DAY}`,
      `/blocks?coupleId=c1&from=&to=`,
      `/blocks?coupleId=c1&from=soon&to=later`,
    ]) {
      const res = await a.inject({ method: 'GET', url, headers: as('uid-a') });
      expect(res.statusCode).toBe(400);
      expect(res.json()).toMatchObject({ error: 'range_required' });
    }
  });

  it('400s when the range exceeds 60 days', async () => {
    seedPair();

    const ok = await list('uid-a', NOW, NOW + 60 * DAY);
    const tooBig = await list('uid-a', NOW, NOW + 60 * DAY + 1);

    expect(ok.statusCode).toBe(200);
    expect(tooBig.statusCode).toBe(400);
    expect(tooBig.json()).toMatchObject({ error: 'range_too_large' });
  });

  it('a non-recurring block in range yields exactly one occurrence equal to its own bounds', async () => {
    seedPair();
    const block = seedBlock('b1');

    const res = await list('uid-a', NOW, NOW + 7 * DAY);

    expect(byId(res, 'b1').occurrences).toEqual([
      { start_utc: block.start_utc, end_utc: block.end_utc },
    ]);
  });

  it('a non-recurring block outside the range yields an empty occurrences array', async () => {
    seedPair();
    seedBlock('b1', { start_utc: NOW + 40 * DAY, end_utc: NOW + 40 * DAY + HOUR });

    const res = await list('uid-a', NOW, NOW + 7 * DAY);

    expect(byId(res, 'b1').occurrences).toEqual([]);
  });

  it('a weekly BYDAY=TU,WE block yields two occurrences in a Mon-Sun range', async () => {
    seedPair();
    // 2026-06-08 is a Monday in Johannesburg; the week runs to Sunday 2026-06-14.
    const monday = DateTime.fromISO('2026-06-08T00:00', { zone: JHB }).toMillis();
    seedBlock('b1', {
      start_utc: DateTime.fromISO('2026-06-02T09:00', { zone: JHB }).toMillis(),
      end_utc: DateTime.fromISO('2026-06-02T10:00', { zone: JHB }).toMillis(),
      recurrence_rule: 'FREQ=WEEKLY;BYDAY=TU,WE',
    });

    const res = await list('uid-a', monday, monday + 7 * DAY);

    const occ = byId(res, 'b1').occurrences;
    expect(occ).toHaveLength(2);
    expect(occ.map((o) => DateTime.fromMillis(o.start_utc, { zone: JHB }).toISO())).toEqual([
      '2026-06-09T09:00:00.000+02:00',
      '2026-06-10T09:00:00.000+02:00',
    ]);
  });

  it('occurrences are clamped to the requested range, not to the 14-day overlap horizon', async () => {
    seedPair();
    seedBlock('b1', {
      start_utc: DateTime.fromISO('2026-06-04T09:00', { zone: JHB }).toMillis(),
      end_utc: DateTime.fromISO('2026-06-04T10:00', { zone: JHB }).toMillis(),
      recurrence_rule: 'FREQ=DAILY',
    });

    // Entirely beyond now + 14 days, where the engine's own horizon would have produced nothing.
    const from = NOW + 30 * DAY;
    const res = await list('uid-a', from, from + 3 * DAY);

    const occ = byId(res, 'b1').occurrences;
    expect(occ).toHaveLength(3);
    expect(occ.every((o) => o.start_utc >= from && o.end_utc <= from + 3 * DAY)).toBe(true);
  });

  it('a recurring 09:00-local block keeps 09:00 local across a DST transition in the range', async () => {
    seedPair();
    // US DST ends 2026-11-01: 09:00 in New York is 13:00Z before it and 14:00Z after.
    seedBlock('b1', {
      user_id: 'uid-b',
      timezone: NY,
      start_utc: DateTime.fromISO('2026-10-29T09:00', { zone: NY }).toMillis(),
      end_utc: DateTime.fromISO('2026-10-29T10:00', { zone: NY }).toMillis(),
      recurrence_rule: 'FREQ=DAILY',
    });

    const from = DateTime.fromISO('2026-10-29T00:00', { zone: NY }).toMillis();
    const res = await list('uid-a', from, from + 7 * DAY);

    const occ = byId(res, 'b1').occurrences;
    expect(occ.length).toBeGreaterThanOrEqual(6);
    // Every instance is still 09:00 wall clock, on both sides of the transition.
    expect(occ.map((o) => DateTime.fromMillis(o.start_utc, { zone: NY }).hour)).toEqual(
      occ.map(() => 9),
    );
    // …and the UTC instant really did shift by an hour, which is the point.
    const utcHours = new Set(occ.map((o) => DateTime.fromMillis(o.start_utc).toUTC().hour));
    expect([...utcHours].sort()).toEqual([13, 14]);
  });

  it('occurrences are computed for the partners blocks too, and respect the onlyMe scrub', async () => {
    seedPair();
    seedBlock('mine');
    seedBlock('theirs', {
      user_id: 'uid-b',
      visibility: 'onlyMe',
      title: 'therapy',
      timezone: NY,
      start_utc: NOW + 2 * DAY,
      end_utc: NOW + 2 * DAY + HOUR,
      recurrence_rule: 'FREQ=DAILY;COUNT=2',
    });

    const res = await list('uid-a', NOW, NOW + 7 * DAY);

    expect(byId(res, 'theirs')).toMatchObject({ title: null, category: null });
    expect(byId(res, 'theirs').occurrences).toEqual([
      { start_utc: NOW + 2 * DAY, end_utc: NOW + 2 * DAY + HOUR },
      { start_utc: NOW + 3 * DAY, end_utc: NOW + 3 * DAY + HOUR },
    ]);
    expect(res.body).not.toContain('therapy');
  });
});

describe('onlyMe over the WebSocket', () => {
  it('block:set sends the owner their own title and the partner a nulled title, from one write', async () => {
    seedPair();

    const res = await post(body({ title: 'therapy', visibility: 'onlyMe', category: 'personal' }));

    expect(res.statusCode).toBe(201);
    const sent = new Map(msgs('block:set'));
    expect(sent.get('uid-a')).toMatchObject({ block: { title: 'therapy', category: 'personal' } });
    expect(sent.get('uid-b')).toMatchObject({ block: { title: null, category: null } });
    // Same write, same broadcast — the partner's copy carries the interval but not the subject.
    expect(sent.get('uid-b')).toMatchObject({ block: { start_utc: NOW + HOUR, visibility: 'onlyMe' } });
    expect(JSON.stringify(msgs('block:set').filter(([uid]) => uid === 'uid-b'))).not.toContain(
      'therapy',
    );
  });

  it('block:del broadcasts only the id, never the block body', async () => {
    seedPair();
    seedBlock('b1', { visibility: 'onlyMe', title: 'therapy' });

    await del('b1', 'uid-a');

    for (const [, msg] of msgs('block:del')) {
      expect(Object.keys(msg)).toEqual(['t', 'id']);
    }
    expect(JSON.stringify(msgs('block:del'))).not.toContain('therapy');
  });

  it('an onlyMe block still changes the computed overlap windows', async () => {
    seedPair();

    const before = await refreshOverlap('c1', null, log);
    expect(before.windows.length).toBeGreaterThan(0);

    // Busy for the entire 14-day horizon, and invisible to the partner.
    const res = await post(
      body({
        title: 'therapy',
        visibility: 'onlyMe',
        start_utc: NOW - HOUR,
        end_utc: NOW + 15 * DAY,
      }),
    );
    expect(res.statusCode).toBe(201);

    // The interval reached the engine unscrubbed: there is no mutual free time left at all.
    expect(overlaps.get('c1')?.windows).toEqual([]);
  });
});
