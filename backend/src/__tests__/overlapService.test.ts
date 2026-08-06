import type { FastifyBaseLogger } from 'fastify';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Querier } from '../db.js';
import type { OverlapInput, OverlapWindow } from '../overlap/types.js';
import type { BlockRow, CoupleRow, UserRow } from '../wire.js';

vi.mock('../db.js', () => ({ withTx: vi.fn(), query: vi.fn() }));
vi.mock('../sockets.js', () => ({ sendTo: vi.fn(() => false) }));
vi.mock('../push.js', () => ({ pushOverlapChanged: vi.fn(async () => {}) }));
// The REAL engine, wrapped in spies. Nothing is stubbed: the wrappers exist only so the tests can
// read the exact OverlapInput the service built and assert that both calls got the same object.
vi.mock('../overlap/index.js', async (importOriginal) => {
  const real = await importOriginal<typeof import('../overlap/index.js')>();
  return {
    ...real,
    computeInputHash: vi.fn(real.computeInputHash),
    computeOverlap: vi.fn(real.computeOverlap),
  };
});

const { withTx } = await import('../db.js');
const { sendTo } = await import('../sockets.js');
const { pushOverlapChanged } = await import('../push.js');
const engine = await import('../overlap/index.js');
const { refreshOverlap } = await import('../overlapService.js');
// Unwrapped, for building expectations independently of the call the service made.
const real = await vi.importActual<typeof import('../overlap/index.js')>('../overlap/index.js');

const JHB = 'Africa/Johannesburg';
const NY = 'America/New_York';
const NOW = Date.parse('2026-06-03T10:00:00Z');
const DAY = 86_400_000;

const log = { warn: vi.fn() } as unknown as FastifyBaseLogger;

interface Stored {
  windows: OverlapWindow[];
  computed_at: number;
  input_hash: string;
}
interface Snap {
  couple: CoupleRow | null;
  users: UserRow[];
  blocks: BlockRow[];
  stored: Stored | null;
}

/** The fake database, plus a log of what the service did to it. */
const world = new Map<string, Snap>();
const events: string[] = [];
const upserts: { coupleId: string; windows: OverlapWindow[]; computedAt: number; hash: string }[] =
  [];
const locks = new Map<string, Promise<void>>();
/** Held by the NEXT load only, so a second refresh can start while the first is mid-flight. */
let gate: Promise<void> | null = null;

function user(uid: string, over: Partial<UserRow> = {}): UserRow {
  return {
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
}

function block(over: Partial<BlockRow> & Pick<BlockRow, 'id' | 'user_id'>): BlockRow {
  return {
    couple_id: 'c1',
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
}

function seed(over: Partial<Snap> = {}, coupleId = 'c1'): Snap {
  const snap: Snap = {
    couple: {
      id: coupleId,
      user_a_uid: 'uid-a',
      user_b_uid: 'uid-b',
      status: 'active',
      paired_at: 1,
      created_at: 1,
    },
    users: [user('uid-a'), user('uid-b', { timezone: NY })],
    blocks: [],
    stored: null,
    ...over,
  };
  world.set(coupleId, snap);
  return snap;
}

/** What the service should have built for the default seed. */
function expectedInput(over: Partial<OverlapInput> = {}): OverlapInput {
  return {
    blocksA: [],
    blocksB: [],
    timezoneA: JHB,
    timezoneB: NY,
    prefsA: { showLateNightWindows: false },
    prefsB: { showLateNightWindows: false },
    now: NOW,
    ...over,
  };
}

const engineBlock = (row: BlockRow) => ({
  userId: row.user_id,
  type: row.type,
  startUtc: row.start_utc,
  endUtc: row.end_utc,
  timezone: row.timezone,
  recurrenceRule: row.recurrence_rule,
});

/** Drains microtasks until an in-flight refresh has reached the given point. */
async function until(pred: () => boolean): Promise<void> {
  for (let i = 0; i < 100 && !pred(); i++) await Promise.resolve();
  expect(pred()).toBe(true);
}

/** The OverlapInput the service handed the engine. */
const inputPassedToCompute = () => vi.mocked(engine.computeOverlap).mock.calls[0]![0];
const inputPassedToHash = () => vi.mocked(engine.computeInputHash).mock.calls[0]![0];

/**
 * Stands in for withTx. `pg_advisory_xact_lock` is simulated with a per-key promise chain released
 * at commit, so the serialization tests exercise the real ordering the service depends on.
 */
async function fakeTx(fn: (q: Querier) => Promise<unknown>): Promise<unknown> {
  let release: (() => void) | undefined;
  const query = async <R>(sql: string, params: unknown[] = []): Promise<R[]> => {
    if (sql.includes('pg_advisory_xact_lock')) {
      const key = String(params[0]);
      events.push(`lock:${key}`);
      const prev = locks.get(key);
      const mine = new Promise<void>((res) => {
        release = res;
      });
      locks.set(key, prev ? prev.then(() => mine) : mine);
      await prev;
      return [] as R[];
    }
    if (sql.includes('INSERT INTO overlaps_latest')) {
      const [coupleId, windows, computedAt, hash] = params as [string, string, number, string];
      const stored: Stored = {
        windows: JSON.parse(windows) as OverlapWindow[],
        computed_at: computedAt,
        input_hash: hash,
      };
      world.get(coupleId)!.stored = stored;
      upserts.push({ coupleId, windows: stored.windows, computedAt, hash });
      events.push(`upsert:${coupleId}`);
      return [] as R[];
    }
    const coupleId = String(params[0]);
    events.push(`load:${coupleId}`);
    const snap = world.get(coupleId);
    // Snapshot BEFORE the gate: a delayed transaction must see the world as it was when it read.
    const row = {
      couple: snap?.couple ?? null,
      users: snap?.users ?? null,
      blocks: snap ? [...snap.blocks] : null,
      stored: snap?.stored ?? null,
    };
    const held = gate;
    gate = null;
    if (held) await held;
    return [row] as R[];
  };
  try {
    return await fn({ query });
  } finally {
    release?.();
  }
}

beforeEach(() => {
  vi.clearAllMocks();
  world.clear();
  events.length = 0;
  upserts.length = 0;
  locks.clear();
  gate = null;
  vi.spyOn(Date, 'now').mockReturnValue(NOW);
  vi.mocked(withTx).mockImplementation(fakeTx as typeof withTx);
  vi.mocked(sendTo).mockReturnValue(false);
  vi.mocked(pushOverlapChanged).mockResolvedValue(undefined);
});

describe('refreshOverlap — engine input', () => {
  it('partitions blocks by couple.user_a_uid into blocksA and user_b_uid into blocksB', async () => {
    seed({
      blocks: [
        block({ id: 'b1', user_id: 'uid-a' }),
        block({ id: 'b2', user_id: 'uid-b' }),
        block({ id: 'b3', user_id: 'uid-a', start_utc: NOW + 2 * DAY, end_utc: NOW + 2 * DAY + 1 }),
      ],
    });

    await refreshOverlap('c1', null, log);

    const input = inputPassedToCompute();
    expect(input.blocksA.map((b) => b.userId)).toEqual(['uid-a', 'uid-a']);
    expect(input.blocksB.map((b) => b.userId)).toEqual(['uid-b']);
  });

  it('passes timezoneA from user_a and timezoneB from user_b, not swapped', async () => {
    seed({
      users: [
        user('uid-a', { timezone: JHB, show_late_night_windows: true }),
        user('uid-b', { timezone: NY, show_late_night_windows: false }),
      ],
    });

    await refreshOverlap('c1', null, log);

    const input = inputPassedToCompute();
    expect(input.timezoneA).toBe(JHB);
    expect(input.timezoneB).toBe(NY);
    expect(input.prefsA).toEqual({ showLateNightWindows: true });
    expect(input.prefsB).toEqual({ showLateNightWindows: false });
  });

  it('includes onlyMe blocks in the engine input', async () => {
    const hidden = block({
      id: 'b1',
      user_id: 'uid-b',
      visibility: 'onlyMe',
      start_utc: NOW,
      end_utc: NOW + 3 * DAY,
    });
    seed({ blocks: [hidden] });

    const res = await refreshOverlap('c1', null, log);

    expect(inputPassedToCompute().blocksB).toEqual([engineBlock(hidden)]);
    // And it actually shaped the result: fewer windows than the same couple with no blocks.
    expect(res.windows.length).toBeLessThan(real.computeOverlap(expectedInput()).length);
  });

  it('passes ONE OverlapInput object to both computeInputHash and computeOverlap', async () => {
    seed();

    await refreshOverlap('c1', null, log);

    // Same object identity, so `now` cannot differ between the hash and the computation.
    expect(inputPassedToHash()).toBe(inputPassedToCompute());
    expect(inputPassedToCompute().now).toBe(NOW);
  });
});

describe('refreshOverlap — dedup', () => {
  it('skips the upsert entirely when the computed input_hash equals the stored one', async () => {
    const windows = real.computeOverlap(expectedInput());
    seed({
      stored: {
        windows,
        computed_at: NOW - 60_000,
        input_hash: real.computeInputHash(expectedInput()),
      },
    });

    await refreshOverlap('c1', null, log);

    expect(upserts).toEqual([]);
    expect(events).not.toContain('upsert:c1');
  });

  it('reports changed:false and sends no WS message and no push on an unchanged hash', async () => {
    const windows = real.computeOverlap(expectedInput());
    seed({
      stored: {
        windows,
        computed_at: NOW - 60_000,
        input_hash: real.computeInputHash(expectedInput()),
      },
    });

    const res = await refreshOverlap('c1', 'uid-a', log);

    expect(res).toEqual({ windows, computedAt: NOW - 60_000, changed: false });
    expect(sendTo).not.toHaveBeenCalled();
    expect(pushOverlapChanged).not.toHaveBeenCalled();
  });

  it('upserts windows, computed_at and input_hash when the hash differs', async () => {
    seed({ stored: { windows: [], computed_at: 1, input_hash: 'stale' } });

    const res = await refreshOverlap('c1', null, log);

    expect(upserts).toEqual([
      {
        coupleId: 'c1',
        windows: real.computeOverlap(expectedInput()),
        computedAt: NOW,
        hash: real.computeInputHash(expectedInput()),
      },
    ]);
    expect(res.changed).toBe(true);
    expect(res.computedAt).toBe(NOW);
  });
});

describe('refreshOverlap — computation', () => {
  it('returns one window per local day for a couple with no blocks on either side', async () => {
    seed();

    const res = await refreshOverlap('c1', null, log);

    // Two people with nothing scheduled are free all the time, so this is NOT [].
    // 14 for this fixture (JHB/NY, waking hours only); the engine's own UTC + late-night
    // fixture gives 15. Cross-checked against the engine rather than assumed.
    expect(res.windows).toHaveLength(14);
    expect(res.windows).toEqual(real.computeOverlap(expectedInput()));
  });

  it('computes for a couple where only one partner has any blocks', async () => {
    const busy = block({ id: 'b1', user_id: 'uid-a', start_utc: NOW, end_utc: NOW + 3 * DAY });
    seed({ blocks: [busy] });

    const res = await refreshOverlap('c1', null, log);

    const expected = real.computeOverlap(expectedInput({ blocksA: [engineBlock(busy)] }));
    expect(expected.length).toBeGreaterThan(0);
    expect(res.windows).toEqual(expected);
  });
});

describe('refreshOverlap — fan-out', () => {
  it('sends a WS overlap message to both partners when the result changed', async () => {
    seed();

    const res = await refreshOverlap('c1', 'uid-a', log);

    const msg = { t: 'overlap', couple_id: 'c1', windows: res.windows, computed_at: NOW };
    expect(vi.mocked(sendTo).mock.calls).toEqual([
      ['uid-a', msg],
      ['uid-b', msg],
    ]);
  });

  it('sends both WS messages in one turn, with no await between them', async () => {
    seed();
    const order: string[] = [];
    vi.mocked(sendTo).mockImplementation((uid) => {
      order.push(`send:${uid}`);
      // Queued during the first send. It can only run before the second send if the service
      // awaited in between — which is what lets a newer refresh's message overtake an older one.
      if (uid === 'uid-a') void Promise.resolve().then(() => order.push('microtask'));
      return false;
    });

    await refreshOverlap('c1', null, log);

    expect(order).toEqual(['send:uid-a', 'send:uid-b', 'microtask']);
  });

  it('does not push to triggeredBy even when that user is offline', async () => {
    seed();

    await refreshOverlap('c1', 'uid-a', log);

    expect(vi.mocked(pushOverlapChanged).mock.calls.map((c) => c[0])).toEqual(['uid-b']);
  });

  it('pushes to the partner only when sendTo returned false for them', async () => {
    seed();
    vi.mocked(sendTo).mockImplementation((uid) => uid === 'uid-b');

    await refreshOverlap('c1', 'uid-a', log);
    expect(pushOverlapChanged).not.toHaveBeenCalled();

    vi.mocked(sendTo).mockReturnValue(false);
    world.get('c1')!.stored = null;
    await refreshOverlap('c1', 'uid-a', log);
    expect(pushOverlapChanged).toHaveBeenCalledWith(
      'uid-b',
      ['tok-uid-b'],
      expect.any(Array),
      NY,
    );
  });

  it('does not push when the partner has notifications_enabled false', async () => {
    seed({ users: [user('uid-a'), user('uid-b', { timezone: NY, notifications_enabled: false })] });

    await refreshOverlap('c1', 'uid-a', log);

    expect(sendTo).toHaveBeenCalledTimes(2);
    expect(pushOverlapChanged).not.toHaveBeenCalled();
  });

  it('logs a failed push instead of failing the already-committed write', async () => {
    seed();
    vi.mocked(pushOverlapChanged).mockRejectedValue(new Error('fcm down'));

    const res = await refreshOverlap('c1', 'uid-a', log);

    expect(res.changed).toBe(true);
    expect(log.warn).toHaveBeenCalledWith({ err: expect.any(Error) }, 'push failed');
  });
});

describe('refreshOverlap — inactive or incomplete couple', () => {
  it('refuses to upsert for an inactive couple', async () => {
    const snap = seed();
    snap.couple = { ...snap.couple!, status: 'inactive' };

    const res = await refreshOverlap('c1', 'uid-a', log);

    expect(res).toEqual({ windows: [], computedAt: NOW, changed: false });
    expect(upserts).toEqual([]);
    expect(sendTo).not.toHaveBeenCalled();
    expect(pushOverlapChanged).not.toHaveBeenCalled();
  });

  it('refuses to upsert when a partner has no timezone yet', async () => {
    seed({ users: [user('uid-a'), user('uid-b', { timezone: null })] });

    const res = await refreshOverlap('c1', null, log);

    expect(res.changed).toBe(false);
    expect(upserts).toEqual([]);
    expect(engine.computeOverlap).not.toHaveBeenCalled();
  });
});

describe('refreshOverlap — advisory lock', () => {
  it('serializes two concurrent refreshes for the same couple', async () => {
    seed();
    let open!: () => void;
    gate = new Promise<void>((res) => {
      open = res;
    });

    const first = refreshOverlap('c1', null, log);
    const second = refreshOverlap('c1', null, log);
    open();
    const [a, b] = await Promise.all([first, second]);

    // The second transaction loads only after the first committed, so it sees the fresh hash and
    // the pair of concurrent refreshes produces exactly one write.
    expect(events.filter((e) => !e.startsWith('lock'))).toEqual([
      'load:c1',
      'upsert:c1',
      'load:c1',
    ]);
    expect([a.changed, b.changed]).toEqual([true, false]);
    expect(a.windows).toEqual(b.windows);
  });

  it('never stores an older result when two writes race', async () => {
    const snap = seed();
    let open!: () => void;
    gate = new Promise<void>((res) => {
      open = res;
    });

    const first = refreshOverlap('c1', null, log); // reads an empty block set, then stalls
    await until(() => events.includes('load:c1'));
    const newer = block({ id: 'b1', user_id: 'uid-a', start_utc: NOW, end_utc: NOW + 3 * DAY });
    snap.blocks.push(newer); // a second write lands while the first refresh is in flight
    const second = refreshOverlap('c1', null, log);
    open();
    await Promise.all([first, second]);

    const newerHash = real.computeInputHash(expectedInput({ blocksA: [engineBlock(newer)] }));
    expect(upserts.map((u) => u.hash)).toEqual([
      real.computeInputHash(expectedInput()),
      newerHash,
    ]);
    expect(snap.stored).toMatchObject({
      input_hash: newerHash,
      windows: real.computeOverlap(expectedInput({ blocksA: [engineBlock(newer)] })),
    });
  });

  it('does not serialize refreshes for different couples', async () => {
    seed();
    seed({ users: [user('uid-c', { couple_id: 'c2' }), user('uid-d', { couple_id: 'c2' })] }, 'c2');
    world.get('c2')!.couple = {
      id: 'c2',
      user_a_uid: 'uid-c',
      user_b_uid: 'uid-d',
      status: 'active',
      paired_at: 1,
      created_at: 1,
    };
    let open!: () => void;
    gate = new Promise<void>((res) => {
      open = res;
    });

    const first = refreshOverlap('c1', null, log); // stalls holding c1's lock
    // Would time out if c2 waited on c1's lock.
    await refreshOverlap('c2', null, log);
    expect(upserts.map((u) => u.coupleId)).toEqual(['c2']);

    open();
    await first;
    expect(upserts.map((u) => u.coupleId)).toEqual(['c2', 'c1']);
  });
});
