import Fastify, { type FastifyInstance } from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Querier } from '../db.js';
import { computeInputHash } from '../overlap/index.js';
import type { OverlapWindow } from '../overlap/types.js';
import { toEngineBlock, type BlockRow, type CoupleRow, type UserRow } from '../wire.js';

// The REAL overlapService and the REAL engine: this route's whole job is the dedup/recompute
// decision, and a mocked refreshOverlap would assert nothing about it.
vi.mock('../firebase.js', () => ({ verifyIdToken: vi.fn() }));
vi.mock('../db.js', () => ({ query: vi.fn(), withTx: vi.fn() }));
vi.mock('../sockets.js', () => ({ sendTo: vi.fn(() => false) }));
vi.mock('../push.js', () => ({ pushOverlapChanged: vi.fn(async () => {}) }));

const { verifyIdToken } = await import('../firebase.js');
const { query, withTx } = await import('../db.js');
const { pushOverlapChanged } = await import('../push.js');
const { registerErrorHandler } = await import('../http.js');
const overlapsRoutes = (await import('../routes/overlaps.js')).default;

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
let events: string[] = [];

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

function seedPair(): CoupleRow {
  const couple: CoupleRow = {
    id: 'c1',
    user_a_uid: 'uid-a',
    user_b_uid: 'uid-b',
    status: 'active',
    paired_at: 1,
    created_at: 1,
  };
  couples.set(couple.id, couple);
  seedUser('uid-a');
  seedUser('uid-b', { timezone: NY });
  return couple;
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

/** The hash overlapService would compute for the seeded state at `now`. */
function hashFor(now = NOW): string {
  const couple = couples.get('c1')!;
  const a = users.get(couple.user_a_uid)!;
  const b = users.get(couple.user_b_uid)!;
  const blocks = timeblocks.filter((x) => x.couple_id === couple.id);
  return computeInputHash({
    blocksA: blocks.filter((x) => x.user_id === a.uid).map(toEngineBlock),
    blocksB: blocks.filter((x) => x.user_id === b.uid).map(toEngineBlock),
    timezoneA: a.timezone!,
    timezoneB: b.timezone!,
    prefsA: { showLateNightWindows: a.show_late_night_windows },
    prefsB: { showLateNightWindows: b.show_late_night_windows },
    now,
  });
}

const sentinel: OverlapWindow = {
  startUtc: NOW + 2 * DAY,
  endUtc: NOW + 2 * DAY + 3 * HOUR,
  durationMinutes: 180,
  score: 42,
  reasonableBoth: true,
};

function store(over: Partial<Stored> = {}): Stored {
  const row: Stored = {
    couple_id: 'c1',
    windows: [sentinel],
    computed_at: NOW - 5 * HOUR,
    input_hash: hashFor(),
    ...over,
  };
  overlaps.set(row.couple_id, row);
  return row;
}

async function runInTx(sql: string, params: unknown[]): Promise<Record<string, unknown>[]> {
  events.push(sql.replace(/\s+/g, ' ').trim());
  if (sql.includes('pg_advisory_xact_lock')) return [];
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
    overlaps.set(coupleId, {
      couple_id: coupleId,
      windows: JSON.parse(windows) as OverlapWindow[],
      computed_at: computedAt,
      input_hash: hash,
    });
    return [];
  }
  throw new Error(`unrouted tx statement: ${sql}`);
}

async function fakeTx<T>(fn: (q: Querier) => Promise<T>): Promise<T> {
  return fn({ query: async <R>(sql: string, params: unknown[] = []) => (await runInTx(sql, params)) as R[] });
}

async function poolQuery(sql: string, params: unknown[] = []): Promise<Record<string, unknown>[]> {
  if (/SELECT \* FROM couples WHERE id = \$1/.test(sql)) {
    const row = couples.get(String(params[0]));
    return row ? [{ ...row }] : [];
  }
  throw new Error(`unrouted pool statement: ${sql}`);
}

function app(): FastifyInstance {
  const a = Fastify();
  registerErrorHandler(a);
  void a.register(overlapsRoutes);
  return a;
}

const as = (uid: string) => ({ authorization: `Bearer ${uid}` });

const latest = (uid = 'uid-a', coupleId = 'c1') =>
  app().inject({
    method: 'GET',
    url: `/overlaps/latest?coupleId=${coupleId}`,
    headers: as(uid),
  });

interface Body {
  couple_id: string;
  windows: OverlapWindow[];
  computed_at: number;
}

const wrote = () => events.filter((e) => e.includes('INSERT INTO overlaps_latest')).length;

beforeEach(() => {
  vi.clearAllMocks();
  users.clear();
  couples.clear();
  overlaps.clear();
  timeblocks = [];
  events = [];
  vi.spyOn(Date, 'now').mockReturnValue(NOW);
  vi.mocked(verifyIdToken).mockImplementation(
    async (token: string) => ({ uid: token, sub: token }) as DecodedIdToken,
  );
  vi.mocked(query).mockImplementation(poolQuery as typeof query);
  vi.mocked(withTx).mockImplementation(fakeTx as typeof withTx);
});

describe('GET /overlaps/latest', () => {
  it('403s for a non-member', async () => {
    seedPair();
    store();

    const stranger = await latest('uid-x');
    const ghost = await latest('uid-a', 'c-nope');

    expect(stranger.statusCode).toBe(403);
    expect(ghost.statusCode).toBe(403);
    expect(ghost.body).toBe(stranger.body);
    expect(wrote()).toBe(0);
  });

  it('returns the stored windows when the recomputed hash matches', async () => {
    seedPair();
    seedBlock('b1');
    const stored = store();

    const res = await latest('uid-a');

    expect(res.statusCode).toBe(200);
    expect(res.json<Body>()).toEqual({
      couple_id: 'c1',
      windows: [sentinel],
      computed_at: stored.computed_at,
    });
  });

  it('does not write to the database when the hash matches', async () => {
    seedPair();
    seedBlock('b1');
    store();

    await latest('uid-a');

    expect(wrote()).toBe(0);
    expect(overlaps.get('c1')?.windows).toEqual([sentinel]);
    expect(pushOverlapChanged).not.toHaveBeenCalled();
  });

  it('recomputes and returns fresh windows when the stored hash is stale', async () => {
    seedPair();
    seedBlock('b1');
    store({ input_hash: 'stale-hash' });

    const res = await latest('uid-a');

    const body = res.json<Body>();
    expect(wrote()).toBe(1);
    expect(body.computed_at).toBe(NOW);
    expect(body.windows).not.toEqual([sentinel]);
    expect(body.windows.length).toBeGreaterThan(0);
    expect(overlaps.get('c1')?.input_hash).toBe(hashFor());
  });

  it('recomputes when the hour bucket rolled over even though no block changed', async () => {
    seedPair();
    seedBlock('b1');
    // Same blocks, same prefs — only the hour bucket differs, which is exactly the staleness the
    // read path exists to fix (§3: no cron).
    const stored = store({ input_hash: hashFor(NOW - HOUR), computed_at: NOW - HOUR });
    expect(stored.input_hash).not.toBe(hashFor(NOW));

    const res = await latest('uid-a');

    expect(wrote()).toBe(1);
    expect(res.json<Body>().computed_at).toBe(NOW);
    expect(overlaps.get('c1')?.input_hash).toBe(hashFor(NOW));
  });

  it('computes and UPSERTS for a couple that has never computed', async () => {
    seedPair();

    const res = await latest('uid-a');

    // Two block-less partners legitimately have windows; an empty response would be a lie.
    const body = res.json<Body>();
    expect(body.windows.length).toBeGreaterThan(0);
    expect(wrote()).toBe(1);
    expect(overlaps.get('c1')).toMatchObject({ computed_at: NOW, input_hash: hashFor() });
  });

  it('passes the requesting uid as triggeredBy, so a read never pushes to the reader', async () => {
    seedPair();
    seedBlock('b1');
    store({ input_hash: 'stale-hash' });

    // Nobody has a live socket (sendTo is mocked false), so only triggeredBy suppresses a push.
    await latest('uid-a');

    expect(pushOverlapChanged).toHaveBeenCalledTimes(1);
    expect(vi.mocked(pushOverlapChanged).mock.calls[0]?.[0]).toBe('uid-b');
  });

  it('accepts a window whose durationMinutes is 1560', async () => {
    seedPair();
    seedBlock('b1');
    // 26 h — reachable on a fall-back day, and the engine's stated ceiling (§2).
    const long: OverlapWindow = {
      startUtc: NOW + DAY,
      endUtc: NOW + DAY + 1560 * 60_000,
      durationMinutes: 1560,
      score: 7,
      reasonableBoth: false,
    };
    store({ windows: [long] });

    const res = await latest('uid-a');

    expect(res.statusCode).toBe(200);
    expect(res.json<Body>().windows).toEqual([long]);
  });
});
