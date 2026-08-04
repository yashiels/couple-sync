import Fastify, { type FastifyInstance } from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { CoupleRow, UserRow } from '../wire.js';

vi.mock('../firebase.js', () => ({ verifyIdToken: vi.fn() }));
vi.mock('../db.js', () => ({ query: vi.fn() }));
vi.mock('../sockets.js', () => ({ sendTo: vi.fn(() => true) }));
vi.mock('../overlapService.js', () => ({ refreshOverlap: vi.fn() }));

const { verifyIdToken } = await import('../firebase.js');
const { query } = await import('../db.js');
const { sendTo } = await import('../sockets.js');
const { refreshOverlap } = await import('../overlapService.js');
const { registerErrorHandler } = await import('../http.js');
const usersRoutes = (await import('../routes/users.js')).default;

const JHB = 'Africa/Johannesburg';
const NY = 'America/New_York';

const users = new Map<string, UserRow>();
const couples = new Map<string, CoupleRow>();

function seedUser(uid: string, over: Partial<UserRow> = {}): UserRow {
  const row: UserRow = {
    uid,
    email: `${uid}@example.com`,
    display_name: 'Ada',
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

/** A miniature users/couples table, so a PATCH is asserted on the stored row, not on a mock call. */
async function fakeQuery(sql: string, params: unknown[] = []): Promise<Record<string, unknown>[]> {
  if (/SELECT \* FROM users WHERE uid = \$1/.test(sql)) {
    const row = users.get(String(params[0]));
    return row ? [{ ...row }] : [];
  }
  if (/SELECT \* FROM couples WHERE id = \$1/.test(sql)) {
    const row = couples.get(String(params[0]));
    if (!row) return [];
    if (/status = 'active'/.test(sql) && row.status !== 'active') return [];
    return [{ ...row }];
  }
  if (/^UPDATE users SET /.test(sql)) {
    const row = users.get(String(params[0]));
    if (!row) return [];
    const patched = { ...row } as Record<string, unknown>;
    for (const [, column, index] of sql.matchAll(/(\w+) = \$(\d+)/g)) {
      patched[column!] = params[Number(index) - 1];
    }
    users.set(row.uid, patched as unknown as UserRow);
    return [{ ...patched }];
  }
  throw new Error(`unrouted statement: ${sql}`);
}

function app(): FastifyInstance {
  const a = Fastify();
  registerErrorHandler(a);
  void a.register(usersRoutes);
  return a;
}

const as = (uid: string) => ({ authorization: `Bearer ${uid}` });

const patch = (uid: string, body: Record<string, unknown>, caller = uid) =>
  app().inject({ method: 'PATCH', url: `/users/${uid}`, headers: as(caller), payload: body });

beforeEach(() => {
  vi.clearAllMocks();
  users.clear();
  couples.clear();
  vi.mocked(verifyIdToken).mockImplementation(
    async (token: string) => ({ uid: token, sub: token }) as DecodedIdToken,
  );
  vi.mocked(query).mockImplementation(fakeQuery as typeof query);
  vi.mocked(refreshOverlap).mockResolvedValue({ windows: [], computedAt: 1, changed: true });
});

describe('GET /users/me', () => {
  it('includes fcm_tokens', async () => {
    seedUser('uid-a', { fcm_tokens: ['tok-1', 'tok-2'] });

    const res = await app().inject({ method: 'GET', url: '/users/me', headers: as('uid-a') });

    expect(res.statusCode).toBe(200);
    expect(res.json<{ user: UserRow }>().user.fcm_tokens).toEqual(['tok-1', 'tok-2']);
  });
});

describe('GET /users/:uid', () => {
  it('returns the partner without fcm_tokens', async () => {
    seedUser('uid-a');
    seedUser('uid-b', { timezone: NY });
    seedCouple();

    const res = await app().inject({ method: 'GET', url: '/users/uid-b', headers: as('uid-a') });

    expect(res.statusCode).toBe(200);
    const { user } = res.json<{ user: Record<string, unknown> }>();
    expect(user['uid']).toBe('uid-b');
    expect(user['timezone']).toBe(NY);
    expect(user).not.toHaveProperty('fcm_tokens');
  });

  it('keeps fcm_tokens when the uid is the caller', async () => {
    seedUser('uid-a');
    seedCouple();

    const res = await app().inject({ method: 'GET', url: '/users/uid-a', headers: as('uid-a') });

    expect(res.json<{ user: UserRow }>().user.fcm_tokens).toEqual(['tok-uid-a']);
  });

  it('403s for a uid that is neither self nor partner', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedUser('uid-stranger', { couple_id: 'c2' });
    seedCouple();

    const res = await app().inject({
      method: 'GET',
      url: '/users/uid-stranger',
      headers: as('uid-a'),
    });

    expect(res.statusCode).toBe(403);
    expect(res.json()).toEqual({ error: 'forbidden' });
  });

  it('403s — not 404 — for an unpaired caller and for a uid that does not exist', async () => {
    seedUser('uid-lonely', { couple_id: null });

    const unpaired = await app().inject({
      method: 'GET',
      url: '/users/uid-b',
      headers: as('uid-lonely'),
    });
    expect(unpaired.statusCode).toBe(403);

    seedUser('uid-a');
    seedCouple();
    const ghost = await app().inject({
      method: 'GET',
      url: '/users/nobody',
      headers: as('uid-a'),
    });
    expect(ghost.statusCode).toBe(403);
  });
});

describe('PATCH /users/:uid', () => {
  it('403s when the target is not the caller', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedCouple();

    const res = await patch('uid-b', { display_name: 'Hacked' }, 'uid-a');

    expect(res.statusCode).toBe(403);
    expect(users.get('uid-b')?.display_name).toBe('Ada');
  });

  it('accepts timezone, show_late_night_windows, notifications_enabled and display_name', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedCouple();

    const res = await patch('uid-a', {
      timezone: NY,
      show_late_night_windows: true,
      notifications_enabled: false,
      display_name: 'Ada L',
    });

    expect(res.statusCode).toBe(200);
    expect(res.json<{ user: UserRow }>().user).toMatchObject({
      timezone: NY,
      show_late_night_windows: true,
      notifications_enabled: false,
      display_name: 'Ada L',
    });
    expect(users.get('uid-a')).toMatchObject({ timezone: NY, notifications_enabled: false });
  });

  it('rejects any other field, including couple_id, email and fcm_tokens', async () => {
    seedUser('uid-a', { couple_id: null });

    for (const body of [
      { couple_id: 'c-stolen' },
      { email: 'attacker@example.com' },
      { fcm_tokens: ['tok-evil'] },
      { uid: 'uid-b' },
      { created_at: 0 },
      { timezone: NY, couple_id: 'c-stolen' },
    ]) {
      const res = await patch('uid-a', body);
      expect(res.statusCode).toBe(400);
      expect(res.json<{ error: string }>().error).toBe('unknown_field');
    }
    // Not even the legal half of a mixed patch was applied.
    expect(users.get('uid-a')).toMatchObject({
      couple_id: null,
      email: 'uid-a@example.com',
      timezone: JHB,
      fcm_tokens: ['tok-uid-a'],
    });
  });

  it('rejects an invalid IANA timezone', async () => {
    seedUser('uid-a');

    for (const timezone of ['SAST', '+02:00', 'Mars/Olympus', '']) {
      const res = await patch('uid-a', { timezone });
      expect(res.statusCode).toBe(400);
      expect(res.json()).toMatchObject({ error: 'invalid_timezone' });
    }
    expect(users.get('uid-a')?.timezone).toBe(JHB);
  });

  it('rejects setting timezone back to null', async () => {
    seedUser('uid-a');

    const res = await patch('uid-a', { timezone: null });

    expect(res.statusCode).toBe(400);
    expect(res.json()).toMatchObject({ error: 'timezone_required' });
    expect(users.get('uid-a')?.timezone).toBe(JHB);
  });

  it('rejects an empty patch', async () => {
    seedUser('uid-a');

    const res = await patch('uid-a', {});

    expect(res.statusCode).toBe(400);
    expect(res.json()).toEqual({ error: 'empty_patch' });
  });

  it('triggers refreshOverlap when timezone changed', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedCouple();

    await patch('uid-a', { timezone: NY });

    expect(refreshOverlap).toHaveBeenCalledWith('c1', 'uid-a', expect.anything());
  });

  it('triggers refreshOverlap when show_late_night_windows changed', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedCouple();

    await patch('uid-a', { show_late_night_windows: true });

    expect(refreshOverlap).toHaveBeenCalledWith('c1', 'uid-a', expect.anything());
  });

  it('does NOT trigger refreshOverlap when only display_name changed', async () => {
    seedUser('uid-a');
    seedUser('uid-b');
    seedCouple();

    await patch('uid-a', { display_name: 'Ada L', notifications_enabled: false });

    expect(refreshOverlap).not.toHaveBeenCalled();
    // The partner still hears about it — it is their partner's name.
    expect(sendTo).toHaveBeenCalledTimes(1);
  });

  it('does not recompute or broadcast for an unpaired user', async () => {
    seedUser('uid-lonely', { couple_id: null });

    const res = await patch('uid-lonely', { timezone: NY });

    expect(res.statusCode).toBe(200);
    expect(refreshOverlap).not.toHaveBeenCalled();
    expect(sendTo).not.toHaveBeenCalled();
  });

  it('broadcasts user:update to the partner with fcm_tokens stripped', async () => {
    seedUser('uid-a', { fcm_tokens: ['tok-secret'] });
    seedUser('uid-b');
    seedCouple();

    await patch('uid-a', { display_name: 'Ada L' });

    expect(sendTo).toHaveBeenCalledExactlyOnceWith('uid-b', {
      t: 'user:update',
      user: expect.objectContaining({ uid: 'uid-a', display_name: 'Ada L' }),
    });
    const [, msg] = vi.mocked(sendTo).mock.calls[0]!;
    expect(msg).toMatchObject({ t: 'user:update' });
    expect((msg as { user: Record<string, unknown> }).user).not.toHaveProperty('fcm_tokens');
    expect(JSON.stringify(msg)).not.toContain('tok-secret');
  });
});
