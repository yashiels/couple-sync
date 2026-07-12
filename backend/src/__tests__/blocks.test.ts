import { describe, it, expect, beforeEach, vi } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

/**
 * Block / user / couple REST routes — V3 tests.
 *
 * Mocks:
 *  - firebase.ts -> verifyIdToken (Bearer auth)
 *  - db.ts       -> query (pg pool) + getPool().connect() (tx client)
 *  - routes/sync.ts -> sendToCouple / sendToUid (broadcast spy)
 *
 * The route handlers import `authenticate` from auth.ts, which calls
 * firebase verifyIdToken. We mock firebase so authenticate returns our
 * canned uid. The handlers also import `sendToCouple` from sync.ts — we
 * mock that module so broadcasts become observable spies.
 */

const verifyIdToken = vi.fn();
const sendToCouple = vi.fn();
const sendToUid = vi.fn();

vi.mock('../firebase.js', () => ({
  getAuth: () => ({ verifyIdToken }),
  initFirebaseAdmin: vi.fn(),
  getMessaging: vi.fn(),
}));

// db.query is the pool query; getPool().connect() returns a tx client whose
// .query also hits mockQuery so we can drive BEGIN/INSERT/COMMIT sequences.
const mockQuery = vi.fn();
const mockClientQuery = vi.fn();
const mockClientRelease = vi.fn();

vi.mock('../db.js', () => ({
  query: (...args: unknown[]) => mockQuery(...args),
  getPool: () => ({
    query: mockQuery,
    connect: () => ({
      query: mockClientQuery,
      release: mockClientRelease,
    }),
  }),
  endPool: vi.fn(),
}));

vi.mock('../routes/sync.js', () => ({
  sendToCouple: (...args: unknown[]) => sendToCouple(...args),
  sendToUid: (...args: unknown[]) => sendToUid(...args),
  sockets: new Map(),
  coupleMembers: new Map(),
}));

import { blockRoutes } from '../routes/blocks.js';
import { userRoutes } from '../routes/users.js';
import { coupleRoutes } from '../routes/couples.js';

const UID = 'uid-alex';
const PARTNER = 'uid-sam';
const COUPLE_ID = 'cpl-1';
const OTHER_COUPLE = 'cpl-other';

const decodedToken = { uid: UID, email: 'alex@example.com', email_verified: true };

function makeCoupleRow(overrides: Partial<{
  id: string;
  user_a_uid: string;
  user_b_uid: string;
  status: string;
  paired_at: number;
  created_at: number;
  unpair_history: unknown[];
}> = {}) {
  return {
    id: COUPLE_ID,
    user_a_uid: UID,
    user_b_uid: PARTNER,
    status: 'active',
    paired_at: 1000,
    created_at: 900,
    unpair_history: [],
    ...overrides,
  };
}

function makeBlockRow(overrides: Partial<{
  id: string;
  couple_id: string;
  user_id: string;
  title: string;
  type: string;
  category: string | null;
  start_utc: number;
  end_utc: number;
  timezone: string;
  recurrence_rule: string | null;
  source: string;
  visibility: string;
  created_at: number;
}> = {}) {
  return {
    id: 'blk-1',
    couple_id: COUPLE_ID,
    user_id: UID,
    title: 'Work',
    type: 'busy',
    category: 'work',
    start_utc: 100000,
    end_utc: 200000,
    timezone: 'UTC',
    recurrence_rule: null,
    source: 'manual',
    visibility: 'bothPartners',
    created_at: 5000,
    ...overrides,
  };
}

function blockInput(overrides: Record<string, unknown> = {}) {
  return {
    coupleId: COUPLE_ID,
    userId: UID,
    title: 'Work',
    type: 'busy',
    category: 'work',
    startUtc: 100000,
    endUtc: 200000,
    timezone: 'UTC',
    recurrenceRule: null,
    source: 'manual',
    visibility: 'bothPartners',
    createdAt: 5000,
    ...overrides,
  };
}

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  await app.register(blockRoutes);
  await app.register(userRoutes);
  await app.register(coupleRoutes);
  return app;
}

function authHeader(): Record<string, string> {
  return { authorization: 'Bearer valid-id-token' };
}

/** Stub a couple membership lookup (assertMember -> getCoupleOr404). */
function stubMember(ok: boolean = true) {
  mockQuery.mockImplementation(async (sql: string) => {
    if (/FROM couples WHERE id = \$1/.test(sql)) {
      if (ok) return { rows: [makeCoupleRow()] };
      // Non-member: the couple exists but caller isn't in it — still return
      // the row so assertMember can check membership. For a *different*
      // couple the handler reads the query param id, so return a row whose
      // members don't include UID.
      return { rows: [makeCoupleRow({ user_a_uid: 'someone-else', user_b_uid: 'partner-else' })] };
    }
    return { rows: [] };
  });
}

beforeEach(() => {
  verifyIdToken.mockReset();
  mockQuery.mockReset();
  mockClientQuery.mockReset();
  mockClientRelease.mockReset();
  sendToCouple.mockReset();
  sendToUid.mockReset();
  verifyIdToken.mockResolvedValue(decodedToken);
});

describe('POST /blocks', () => {
  it('creates a block, returns 201 with id, and broadcasts block:set to the partner (excluding caller)', async () => {
    // assertMember lookup, then INSERT ... RETURNING.
    mockQuery
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] }) // couples lookup
      .mockResolvedValueOnce({ rows: [makeBlockRow()] }); // INSERT RETURNING

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/blocks',
      headers: authHeader(),
      payload: blockInput(),
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.id).toBe('blk-1');
    expect(body.coupleId).toBe(COUPLE_ID);
    expect(body.userId).toBe(UID);
    expect(body.startUtc).toBe(100000);

    // Broadcast: block:set to the couple, excluding the caller.
    expect(sendToCouple).toHaveBeenCalledTimes(1);
    const [cplId, msg, excludeUid] = sendToCouple.mock.calls[0];
    expect(cplId).toBe(COUPLE_ID);
    expect((msg as { t: string }).t).toBe('block:set');
    expect((msg as { block: { id: string } }).block.id).toBe('blk-1');
    expect(excludeUid).toBe(UID);

    // The INSERT must use a server-generated UUID (crypto.randomUUID).
    const insertCall = mockQuery.mock.calls.find(
      (c) => typeof c[0] === 'string' && /INSERT INTO timeblocks/.test(c[0] as string)
    );
    expect(insertCall).toBeDefined();
    const params = insertCall![1] as unknown[];
    expect(params[0]).toEqual(expect.any(String));
    expect((params[0] as string).length).toBeGreaterThan(10); // UUID-ish
    await app.close();
  });

  it('returns 400 when required fields are missing', async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/blocks',
      headers: authHeader(),
      payload: { coupleId: COUPLE_ID, userId: UID }, // no title/type/etc
    });
    expect(res.statusCode).toBe(400);
    expect(sendToCouple).not.toHaveBeenCalled();
    await app.close();
  });
});

describe('PUT /blocks/:id', () => {
  it('updates fields and broadcasts block:set with the full updated block', async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ couple_id: COUPLE_ID }] }) // existing lookup
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] }) // assertMember
      .mockResolvedValueOnce({ rows: [makeBlockRow({ title: 'Updated' })] }); // UPDATE RETURNING

    const app = await buildApp();
    const res = await app.inject({
      method: 'PUT',
      url: '/blocks/blk-1',
      headers: authHeader(),
      payload: { title: 'Updated' },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().title).toBe('Updated');
    expect(sendToCouple).toHaveBeenCalledTimes(1);
    const [, msg] = sendToCouple.mock.calls[0];
    expect((msg as { t: string }).t).toBe('block:set');
    expect((msg as { block: { title: string } }).block.title).toBe('Updated');
    await app.close();
  });

  it('returns 404 when the block does not exist', async () => {
    mockQuery.mockResolvedValue({ rows: [] });
    const app = await buildApp();
    const res = await app.inject({
      method: 'PUT',
      url: '/blocks/missing',
      headers: authHeader(),
      payload: { title: 'x' },
    });
    expect(res.statusCode).toBe(404);
    await app.close();
  });

  it('returns 400 (not 500) when startUtc is a non-integer', async () => {
    // existing lookup + assertMember succeed; the push() validator must throw 400.
    mockQuery
      .mockResolvedValueOnce({ rows: [{ couple_id: COUPLE_ID }] }) // existing lookup
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] }); // assertMember
    const app = await buildApp();
    const res = await app.inject({
      method: 'PUT',
      url: '/blocks/blk-1',
      headers: authHeader(),
      payload: { startUtc: 'hello' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('bad_request');
    // No UPDATE must run and no broadcast must fire on a bad body.
    const updateCall = mockQuery.mock.calls.find(
      (c) => typeof c[0] === 'string' && /UPDATE timeblocks/.test(c[0] as string)
    );
    expect(updateCall).toBeUndefined();
    expect(sendToCouple).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns 400 when endUtc is a non-integer', async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ couple_id: COUPLE_ID }] })
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] });
    const app = await buildApp();
    const res = await app.inject({
      method: 'PUT',
      url: '/blocks/blk-1',
      headers: authHeader(),
      payload: { endUtc: false },
    });
    expect(res.statusCode).toBe(400);
    await app.close();
  });
});

describe('DELETE /blocks/:id', () => {
  it('deletes and broadcasts block:del with the id', async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ couple_id: COUPLE_ID }] }) // existing
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] }) // assertMember
      .mockResolvedValueOnce({ rows: [] }); // DELETE

    const app = await buildApp();
    const res = await app.inject({
      method: 'DELETE',
      url: '/blocks/blk-1',
      headers: authHeader(),
    });

    expect(res.statusCode).toBe(200);
    expect(sendToCouple).toHaveBeenCalledTimes(1);
    const [cplId, msg, excludeUid] = sendToCouple.mock.calls[0];
    expect(cplId).toBe(COUPLE_ID);
    expect((msg as { t: string }).t).toBe('block:del');
    expect((msg as { id: string }).id).toBe('blk-1');
    expect(excludeUid).toBe(UID);
    await app.close();
  });
});

describe('GET /blocks', () => {
  it('returns all blocks for the couple (both partners)', async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] }) // assertMember
      .mockResolvedValueOnce({
        rows: [
          makeBlockRow({ id: 'b1', user_id: UID }),
          makeBlockRow({ id: 'b2', user_id: PARTNER }),
        ],
      }); // SELECT

    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/blocks?coupleId=${COUPLE_ID}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.blocks).toHaveLength(2);
    expect(body.blocks[0].id).toBe('b1');
    expect(body.blocks[1].userId).toBe(PARTNER);
    await app.close();
  });

  it('returns 403 for a non-member', async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [makeCoupleRow({ user_a_uid: 'other', user_b_uid: 'partner' })],
    });

    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/blocks?coupleId=${COUPLE_ID}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(403);
    await app.close();
  });
});

describe('POST /blocks/batch', () => {
  it('deletes old google blocks for the user, inserts new ones in one tx, returns counts, and broadcasts both del + set', async () => {
    // assertMember lookup (pool query), then the tx client takes over.
    mockQuery.mockResolvedValueOnce({ rows: [makeCoupleRow()] }); // assertMember

    // Tx client query sequence:
    //   1) BEGIN
    //   2) DELETE ... RETURNING id   -> 2 deleted
    //   3) INSERT block A RETURNING  -> row
    //   4) INSERT block B RETURNING  -> row
    //   5) COMMIT
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({
        rows: [{ id: 'old-1' }, { id: 'old-2' }],
      }) // DELETE RETURNING
      .mockResolvedValueOnce({ rows: [makeBlockRow({ id: 'new-1' })] })
      .mockResolvedValueOnce({ rows: [makeBlockRow({ id: 'new-2' })] })
      .mockResolvedValueOnce({ rows: [] }); // COMMIT

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/blocks/batch',
      headers: authHeader(),
      payload: {
        coupleId: COUPLE_ID,
        userId: UID,
        source: 'google',
        blocks: [blockInput(), blockInput()],
      },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.deletedCount).toBe(2);
    expect(body.createdCount).toBe(2);

    // BEGIN + COMMIT were issued.
    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /BEGIN/.test(s))).toBe(true);
    expect(txSqls.some((s) => /COMMIT/.test(s))).toBe(true);

    // Broadcasts: 2 del + 2 set = 4.
    expect(sendToCouple).toHaveBeenCalledTimes(4);
    const dels = sendToCouple.mock.calls.filter(
      (c) => (c[1] as { t: string }).t === 'block:del'
    );
    const sets = sendToCouple.mock.calls.filter(
      (c) => (c[1] as { t: string }).t === 'block:set'
    );
    expect(dels).toHaveLength(2);
    expect(sets).toHaveLength(2);
    // All exclude the caller.
    for (const c of sendToCouple.mock.calls) {
      expect(c[2]).toBe(UID);
    }
    expect(mockClientRelease).toHaveBeenCalledTimes(1);
    await app.close();
  });

  it('rolls back on insert failure', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [makeCoupleRow()] }); // assertMember
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({ rows: [{ id: 'old-1' }] }) // DELETE
      .mockRejectedValueOnce(new Error('insert blew up')) // INSERT A
      .mockResolvedValueOnce({ rows: [] }); // ROLLBACK

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/blocks/batch',
      headers: authHeader(),
      payload: {
        coupleId: COUPLE_ID,
        userId: UID,
        source: 'google',
        blocks: [blockInput()],
      },
    });
    expect(res.statusCode).toBe(500);
    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /ROLLBACK/.test(s))).toBe(true);
    expect(mockClientRelease).toHaveBeenCalledTimes(1);
    // No broadcasts on failure.
    expect(sendToCouple).not.toHaveBeenCalled();
    await app.close();
  });

  it('403 when replacing another user\'s blocks', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [makeCoupleRow()] }); // assertMember ok
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/blocks/batch',
      headers: authHeader(),
      payload: {
        coupleId: COUPLE_ID,
        userId: PARTNER, // not the caller
        source: 'google',
        blocks: [],
      },
    });
    expect(res.statusCode).toBe(403);
    await app.close();
  });
});

describe('GET /users/:uid', () => {
  function makeUserRow(overrides: Partial<{
    uid: string;
    email: string;
    display_name: string | null;
    photo_url: string | null;
    timezone: string;
    couple_id: string | null;
    fcm_tokens: string[];
    show_late_night_windows: boolean;
    created_at: number;
  }> = {}) {
    return {
      uid: UID,
      email: 'alex@example.com',
      display_name: 'Alex',
      photo_url: null,
      timezone: 'UTC',
      couple_id: COUPLE_ID,
      fcm_tokens: ['fcm-1'],
      show_late_night_windows: false,
      created_at: 1000,
      ...overrides,
    };
  }

  it('returns the caller\'s own profile (with fcmTokens)', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [makeUserRow()] });
    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/users/${UID}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.uid).toBe(UID);
    expect(body.timezone).toBe('UTC');
    expect(body.coupleId).toBe(COUPLE_ID);
    expect(body.fcmTokens).toEqual(['fcm-1']);
    await app.close();
  });

  it('returns the partner\'s profile (without fcmTokens)', async () => {
    // assertCanReadUser: load target (partner), then getCoupleOr404.
    mockQuery
      .mockResolvedValueOnce({ rows: [makeUserRow({ uid: PARTNER, fcm_tokens: ['secret'] })] }) // target
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] }) // couple lookup
      .mockResolvedValueOnce({ rows: [makeUserRow({ uid: PARTNER, fcm_tokens: ['secret'] })] }); // reload

    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/users/${PARTNER}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.uid).toBe(PARTNER);
    expect(body.fcmTokens).toBeUndefined(); // partner path hides fcmTokens
    await app.close();
  });

  it('403 for a non-partner (different couple)', async () => {
    // target exists, in a different couple whose members don't include UID.
    mockQuery
      .mockResolvedValueOnce({
        rows: [makeUserRow({ uid: 'stranger', couple_id: OTHER_COUPLE })],
      }) // target
      .mockResolvedValueOnce({
        rows: [makeCoupleRow({ id: OTHER_COUPLE, user_a_uid: 'x', user_b_uid: 'y' })],
      }); // couple lookup -> caller not a member

    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: '/users/stranger',
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(403);
    await app.close();
  });
});

describe('PATCH /users/:uid', () => {
  function makeUserRow(overrides: Record<string, unknown> = {}) {
    return {
      uid: UID,
      email: 'alex@example.com',
      display_name: 'Alex',
      photo_url: null,
      timezone: 'UTC',
      couple_id: COUPLE_ID,
      fcm_tokens: ['fcm-1'],
      show_late_night_windows: false,
      created_at: 1000,
      ...overrides,
    };
  }

  it('partial-updates timezone + showLateNightWindows and broadcasts user:update to the couple', async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserRow({ timezone: 'Europe/London', show_late_night_windows: true })],
    });
    const app = await buildApp();
    const res = await app.inject({
      method: 'PATCH',
      url: `/users/${UID}`,
      headers: authHeader(),
      payload: { timezone: 'Europe/London', showLateNightWindows: true },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.timezone).toBe('Europe/London');
    expect(body.showLateNightWindows).toBe(true);
    expect(sendToCouple).toHaveBeenCalledTimes(1);
    const [cplId, msg, excludeUid] = sendToCouple.mock.calls[0];
    expect(cplId).toBe(COUPLE_ID);
    expect((msg as { t: string }).t).toBe('user:update');
    expect((msg as { user: { timezone: string } }).user.timezone).toBe('Europe/London');
    expect(excludeUid).toBe(UID);

    // Verify the UPDATE used partial SETs.
    const updateCall = mockQuery.mock.calls.find(
      (c) => typeof c[0] === 'string' && /UPDATE users SET/.test(c[0] as string)
    );
    expect(updateCall).toBeDefined();
    const sql = updateCall![0] as string;
    const setClause = sql.split('WHERE')[0];
    expect(setClause).toMatch(/timezone = \$1/);
    expect(setClause).toMatch(/show_late_night_windows = \$2/);
    // displayName was NOT in the body — must not appear in the SET clause.
    expect(setClause).not.toMatch(/display_name/);
    await app.close();
  });

  it('403 when patching another user', async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: 'PATCH',
      url: `/users/${PARTNER}`,
      headers: authHeader(),
      payload: { timezone: 'UTC' },
    });
    expect(res.statusCode).toBe(403);
    expect(mockQuery).not.toHaveBeenCalled();
    await app.close();
  });

  it('does not leak fcmTokens in the user:update broadcast to the partner', async () => {
    // The PATCH response goes to the caller themself (self path) and may
    // include fcmTokens. But the user:update broadcast goes to the partner
    // over the socket and MUST NOT include fcmTokens.
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserRow({ fcm_tokens: ['secret-fcm-1', 'secret-fcm-2'] })],
    });
    const app = await buildApp();
    const res = await app.inject({
      method: 'PATCH',
      url: `/users/${UID}`,
      headers: authHeader(),
      payload: { timezone: 'Asia/Kolkata' },
    });
    expect(res.statusCode).toBe(200);
    // Self response still includes the caller's own fcmTokens.
    expect(res.json().fcmTokens).toEqual(['secret-fcm-1', 'secret-fcm-2']);
    // Broadcast to partner must omit fcmTokens.
    expect(sendToCouple).toHaveBeenCalledTimes(1);
    const [, msg] = sendToCouple.mock.calls[0];
    expect((msg as { t: string }).t).toBe('user:update');
    expect((msg as { user: Record<string, unknown> }).user.fcmTokens).toBeUndefined();
    await app.close();
  });
});

describe('GET /couples/:id', () => {
  it('returns the couple doc for a member', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [makeCoupleRow()] });
    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/couples/${COUPLE_ID}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.userAUid).toBe(UID);
    expect(body.userBUid).toBe(PARTNER);
    expect(body.status).toBe('active');
    await app.close();
  });

  it('403 for a non-member', async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [makeCoupleRow({ user_a_uid: 'x', user_b_uid: 'y' })],
    });
    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/couples/${COUPLE_ID}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(403);
    await app.close();
  });
});
