import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Querier } from '../db.js';
import type { BlockRow, CoupleRow, UserRow } from '../wire.js';

// Same shape as couples.route.test.ts: an in-memory DB standing in for db.js, so the transaction
// boundary, the advisory lock, and the ON DELETE cascades are all asserted without a live Postgres.
// firebase.deleteAuthUser and sockets.sendTo are mocked so the two out-of-transaction steps are
// controllable — the Firebase failure is the whole point of the resumability tests.
vi.mock('../db.js', () => ({ query: vi.fn(), withTx: vi.fn() }));
vi.mock('../firebase.js', () => ({ deleteAuthUser: vi.fn(async () => {}) }));
vi.mock('../sockets.js', () => ({ sendTo: vi.fn(() => true) }));

const { query, withTx } = await import('../db.js');
const { deleteAuthUser } = await import('../firebase.js');
const { sendTo } = await import('../sockets.js');
const { deleteAccount, isDeleted, reconcilePendingDeletions } = await import('../account.js');

const NOW = Date.parse('2026-06-03T10:00:00Z');

interface Tombstone {
  uid: string;
  deleted_at: number;
  completed_at: number | null;
}

const users = new Map<string, UserRow>();
const couples = new Map<string, CoupleRow>();
let timeblocks: BlockRow[] = [];
const overlaps = new Set<string>();
const tombstones = new Map<string, Tombstone>();
let events: string[] = [];
let failOn: string | null = null;

function seedUser(uid: string, over: Partial<UserRow> = {}): void {
  users.set(uid, {
    uid,
    email: `${uid}@example.com`,
    display_name: null,
    photo_url: null,
    timezone: 'Africa/Johannesburg',
    couple_id: 'c1',
    show_late_night_windows: false,
    notifications_enabled: true,
    fcm_tokens: [`tok-${uid}`],
    created_at: 1,
    ...over,
  });
}

function seedPair(): void {
  couples.set('c1', {
    id: 'c1',
    user_a_uid: 'uid-a',
    user_b_uid: 'uid-b',
    status: 'active',
    paired_at: 1,
    created_at: 1,
  });
  seedUser('uid-a');
  seedUser('uid-b');
}

/** Applies a statement to the in-memory store. Used by both the pool path and the transaction path. */
function run(sql: string, params: unknown[]): Record<string, unknown>[] {
  const s = sql.replace(/\s+/g, ' ').trim();
  events.push(s);
  if (failOn && s.includes(failOn)) throw new Error('constraint violation');

  if (s.startsWith('INSERT INTO deleted_accounts')) {
    const [uid, deleted_at] = params as [string, number];
    if (!tombstones.has(uid)) tombstones.set(uid, { uid, deleted_at, completed_at: null });
    return [];
  }
  if (s.startsWith('UPDATE deleted_accounts SET completed_at')) {
    const [uid, completed_at] = params as [string, number];
    const t = tombstones.get(uid);
    if (t) t.completed_at = completed_at;
    return [];
  }
  if (s.startsWith('SELECT 1 FROM deleted_accounts')) {
    return tombstones.has(String(params[0])) ? [{ '?column?': 1 }] : [];
  }
  if (s.startsWith('SELECT uid FROM deleted_accounts WHERE completed_at IS NULL')) {
    return [...tombstones.values()].filter((t) => t.completed_at === null).map((t) => ({ uid: t.uid }));
  }
  if (s.startsWith('SELECT couple_id FROM users WHERE uid = $1 FOR UPDATE')) {
    const row = users.get(String(params[0]));
    return row ? [{ couple_id: row.couple_id }] : [];
  }
  if (s.includes('pg_advisory_xact_lock')) return [];
  if (s.startsWith('SELECT * FROM couples WHERE (user_a_uid')) {
    const uid = String(params[0]);
    const row = [...couples.values()].find(
      (c) => (c.user_a_uid === uid || c.user_b_uid === uid) && c.status === 'active',
    );
    return row ? [{ ...row }] : [];
  }
  if (s.startsWith("UPDATE couples SET status = 'inactive'")) {
    const row = couples.get(String(params[0]));
    if (row) row.status = 'inactive';
    return [];
  }
  if (s.startsWith('UPDATE users SET couple_id = NULL')) {
    for (const uid of params.map(String)) {
      const row = users.get(uid);
      if (row) row.couple_id = null;
    }
    return [];
  }
  if (s.startsWith('DELETE FROM timeblocks')) {
    timeblocks = timeblocks.filter((b) => b.couple_id !== String(params[0]));
    return [];
  }
  if (s.startsWith('DELETE FROM overlaps_latest')) {
    overlaps.delete(String(params[0]));
    return [];
  }
  if (s.startsWith('DELETE FROM users')) {
    const uid = String(params[0]);
    users.delete(uid);
    // ON DELETE CASCADE on invites.created_by_uid and timeblocks.user_id.
    timeblocks = timeblocks.filter((b) => b.user_id !== uid);
    return [];
  }
  throw new Error(`unrouted statement: ${s}`);
}

async function fakeTx<T>(fn: (q: Querier) => Promise<T>): Promise<T> {
  // Snapshot for rollback: the transaction must be all-or-nothing.
  const snapshot = {
    users: new Map(users),
    couples: new Map([...couples].map(([k, v]) => [k, { ...v }])),
    timeblocks: [...timeblocks],
    overlaps: new Set(overlaps),
    tombstones: new Map([...tombstones].map(([k, v]) => [k, { ...v }])),
  };
  events.push('BEGIN');
  const q = { query: async <R>(sql: string, params: unknown[] = []) => run(sql, params) as R[] };
  try {
    const out = await fn(q);
    events.push('COMMIT');
    return out;
  } catch (err) {
    // Restore the snapshot so a failed transaction leaves nothing behind.
    users.clear();
    for (const [k, v] of snapshot.users) users.set(k, v);
    couples.clear();
    for (const [k, v] of snapshot.couples) couples.set(k, v);
    timeblocks = snapshot.timeblocks;
    overlaps.clear();
    for (const v of snapshot.overlaps) overlaps.add(v);
    tombstones.clear();
    for (const [k, v] of snapshot.tombstones) tombstones.set(k, v);
    events.push('ROLLBACK');
    throw err;
  }
}

beforeEach(() => {
  vi.clearAllMocks();
  users.clear();
  couples.clear();
  timeblocks = [];
  overlaps.clear();
  tombstones.clear();
  events = [];
  failOn = null;
  vi.spyOn(Date, 'now').mockReturnValue(NOW);
  vi.mocked(query).mockImplementation((async (sql: string, params: unknown[] = []) =>
    run(sql, params)) as typeof query);
  vi.mocked(withTx).mockImplementation(fakeTx as typeof withTx);
  vi.mocked(deleteAuthUser).mockResolvedValue(undefined);
});

describe('deleteAccount', () => {
  it('deletes the user, tears down the couple, and cascades their data', async () => {
    seedPair();
    timeblocks.push({ couple_id: 'c1', user_id: 'uid-a', id: 'b1' } as BlockRow);
    timeblocks.push({ couple_id: 'c1', user_id: 'uid-b', id: 'b2' } as BlockRow);
    overlaps.add('c1');

    await deleteAccount('uid-a');

    expect(users.has('uid-a')).toBe(false);
    expect(couples.get('c1')?.status).toBe('inactive');
    expect(users.get('uid-b')?.couple_id).toBeNull();
    expect(timeblocks).toHaveLength(0);
    expect(overlaps.has('c1')).toBe(false);
  });

  it('writes a tombstone that outlives the user and stamps completed_at', async () => {
    seedPair();
    await deleteAccount('uid-a');

    const t = tombstones.get('uid-a');
    expect(t).toBeDefined();
    expect(t?.completed_at).toBe(NOW);
    // Non-resurrection: /auth/verify checks exactly this.
    await expect(isDeleted('uid-a')).resolves.toBe(true);
  });

  it('tombstone is written inside the transaction, completed_at after the Firebase delete', async () => {
    seedPair();
    await deleteAccount('uid-a');

    const begin = events.indexOf('BEGIN');
    const commit = events.indexOf('COMMIT');
    const insert = events.findIndex((e) => e.startsWith('INSERT INTO deleted_accounts'));
    const stamp = events.findIndex((e) => e.startsWith('UPDATE deleted_accounts SET completed_at'));
    expect(begin).toBeLessThan(insert);
    expect(insert).toBeLessThan(commit); // tombstone commits with the deletes
    expect(stamp).toBeGreaterThan(commit); // completed only after the out-of-tx Firebase delete
  });

  it('locks the user row FOR UPDATE first, to serialize against invite redemption', async () => {
    seedPair();
    await deleteAccount('uid-a');
    // The FOR UPDATE on the user row must precede reading the couple, so a concurrent redeem (which
    // also locks the user rows) cannot slip a new couple in between the read and the delete.
    const lockAt = events.findIndex((e) => e.startsWith('SELECT couple_id FROM users WHERE uid = $1 FOR UPDATE'));
    const coupleAt = events.findIndex((e) => e.startsWith('SELECT * FROM couples WHERE (user_a_uid'));
    expect(lockAt).toBeGreaterThanOrEqual(0);
    expect(lockAt).toBeLessThan(coupleAt);
  });

  it('takes the same advisory lock as unpair before touching the couple', async () => {
    seedPair();
    await deleteAccount('uid-a');
    const lockAt = events.findIndex((e) => e.includes('pg_advisory_xact_lock'));
    const updateAt = events.findIndex((e) => e.startsWith("UPDATE couples SET status = 'inactive'"));
    expect(lockAt).toBeGreaterThanOrEqual(0);
    expect(lockAt).toBeLessThan(updateAt);
  });

  it('notifies the partner so their app resets, exactly as unpair does', async () => {
    seedPair();
    await deleteAccount('uid-a');
    expect(sendTo).toHaveBeenCalledOnce();
    expect(sendTo).toHaveBeenCalledWith('uid-b', { t: 'unpair', couple_id: 'c1' });
  });

  it('handles an unpaired user: deletes them, no couple work, no notify', async () => {
    seedUser('solo', { couple_id: null });
    await deleteAccount('solo');
    expect(users.has('solo')).toBe(false);
    expect(tombstones.get('solo')?.completed_at).toBe(NOW);
    expect(sendTo).not.toHaveBeenCalled();
  });

  it('leaves the tombstone incomplete when the Firebase delete fails, then reconciles it', async () => {
    seedPair();
    vi.mocked(deleteAuthUser).mockRejectedValueOnce(new Error('firebase down'));

    await expect(deleteAccount('uid-a')).rejects.toThrow('firebase down');
    // Postgres committed: the user is gone and cannot be resurrected...
    expect(users.has('uid-a')).toBe(false);
    await expect(isDeleted('uid-a')).resolves.toBe(true);
    // ...but the tombstone is not complete until Firebase succeeds.
    expect(tombstones.get('uid-a')?.completed_at).toBeNull();

    const reconciled = await reconcilePendingDeletions();
    expect(reconciled).toBe(1);
    expect(tombstones.get('uid-a')?.completed_at).toBe(NOW);
  });

  it('is idempotent — re-running after a full deletion is a safe no-op', async () => {
    seedPair();
    await deleteAccount('uid-a');
    await expect(deleteAccount('uid-a')).resolves.toBeUndefined();
    expect(users.has('uid-a')).toBe(false);
    expect(tombstones.get('uid-a')?.completed_at).toBe(NOW);
  });

  it('rolls back the whole transaction if a delete fails — no partial teardown', async () => {
    seedPair();
    timeblocks.push({ couple_id: 'c1', user_id: 'uid-a', id: 'b1' } as BlockRow);
    failOn = 'DELETE FROM users';

    await expect(deleteAccount('uid-a')).rejects.toThrow('constraint violation');
    // Nothing committed: the couple is still active, the user still present, no tombstone.
    expect(users.has('uid-a')).toBe(true);
    expect(couples.get('c1')?.status).toBe('active');
    expect(tombstones.has('uid-a')).toBe(false);
    expect(deleteAuthUser).not.toHaveBeenCalled();
  });

  it('deleting both partners leaves the couple inactive and both users gone', async () => {
    seedPair();
    await deleteAccount('uid-a');
    await deleteAccount('uid-b');
    expect(users.size).toBe(0);
    expect(couples.get('c1')?.status).toBe('inactive');
    // The second deletion found no active couple, so it only notified once (for the first).
    expect(sendTo).toHaveBeenCalledOnce();
  });
});

describe('reconcilePendingDeletions', () => {
  it('returns 0 when nothing is pending', async () => {
    await expect(reconcilePendingDeletions()).resolves.toBe(0);
    expect(deleteAuthUser).not.toHaveBeenCalled();
  });
});
