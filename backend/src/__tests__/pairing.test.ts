import { describe, it, expect, beforeEach, vi } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

/**
 * Pairing lifecycle tests — V4.
 *
 * Covers:
 *  - POST /invites          — mint a 6-char code + 48h expiry
 *  - POST /invites/:code/redeem — atomic pairing, idempotent re-redeem, expired
 *  - POST /couples/:id/unpair — sets inactive, clears couple_id on both users,
 *    appends history, deletes timeblocks + overlaps_latest
 *  - cleanupExpiredInvites  — flips pending+expired invites to 'expired'
 *
 * Mocks mirror blocks.test.ts: firebase verifyIdToken, db query + pool.connect
 * (tx client), and routes/sync.sendToUid (broadcast spy).
 */

const verifyIdToken = vi.fn();
const sendToUid = vi.fn();

vi.mock('../firebase.js', () => ({
  getAuth: () => ({ verifyIdToken }),
  initFirebaseAdmin: vi.fn(),
  getMessaging: vi.fn(),
}));

vi.mock('../config.js', () => ({
  getConfig: () => ({
    databaseUrl: 'postgres://test',
    firebaseProjectId: 'test',
    firebaseServiceAccountJson: '{}',
    domain: 'api.test',
    port: 3000,
    adminToken: 'secret-admin-token',
  }),
  loadConfig: () => ({
    databaseUrl: 'postgres://test',
    firebaseProjectId: 'test',
    firebaseServiceAccountJson: '{}',
    domain: 'api.test',
    port: 3000,
    adminToken: 'secret-admin-token',
  }),
}));

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
  sendToUid: (...args: unknown[]) => sendToUid(...args),
  sendToCouple: vi.fn(),
  sockets: new Map(),
  coupleMembers: new Map(),
}));

import { inviteRoutes } from '../routes/invites.js';
import { coupleRoutes } from '../routes/couples.js';
import { adminRoutes, cleanupExpiredInvites } from '../cron.js';

const UID = 'uid-alex';
const PARTNER = 'uid-sam';
const THIRD = 'uid-eve';
const COUPLE_ID = 'cpl-1';
const CODE = 'ABC234';

const decodedToken = { uid: UID, email: 'alex@example.com', email_verified: true };
const partnerToken = { uid: PARTNER, email: 'sam@example.com', email_verified: true };
const thirdToken = { uid: THIRD, email: 'eve@example.com', email_verified: true };

function makeInviteRow(overrides: Partial<{
  code: string;
  created_by_uid: string;
  couple_id: string | null;
  expires_at: number;
  status: string;
}> = {}) {
  const now = Date.now();
  return {
    code: CODE,
    created_by_uid: UID,
    couple_id: null,
    expires_at: now + 48 * 60 * 60 * 1000,
    status: 'pending',
    ...overrides,
  };
}

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

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  await app.register(inviteRoutes);
  await app.register(coupleRoutes);
  await app.register(adminRoutes);
  return app;
}

function authHeader(uid: string = UID): Record<string, string> {
  if (uid === UID) verifyIdToken.mockResolvedValue(decodedToken);
  if (uid === PARTNER) verifyIdToken.mockResolvedValue(partnerToken);
  if (uid === THIRD) verifyIdToken.mockResolvedValue(thirdToken);
  return { authorization: 'Bearer valid-id-token' };
}

beforeEach(() => {
  verifyIdToken.mockReset();
  mockQuery.mockReset();
  mockClientQuery.mockReset();
  mockClientRelease.mockReset();
  sendToUid.mockReset();
  verifyIdToken.mockResolvedValue(decodedToken);
});

describe('POST /invites', () => {
  it('mints a 6-char alphanumeric code with 48h expiry and inserts it', async () => {
    // INSERT ... ON CONFLICT DO NOTHING, then SELECT verify.
    mockQuery
      .mockResolvedValueOnce({ rows: [] }) // INSERT
      .mockResolvedValueOnce({ rows: [{ code: 'XYZ987' }] }); // SELECT verify

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/invites',
      headers: authHeader(),
      payload: {},
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.code).toMatch(/^[A-Z2-9]{6}$/);
    expect(body.expiresAt).toBeGreaterThan(Date.now() + 47 * 60 * 60 * 1000);

    // The INSERT used status='pending' and the authed uid as created_by_uid.
    const insertCall = mockQuery.mock.calls.find(
      (c) => typeof c[0] === 'string' && /INSERT INTO invites/.test(c[0] as string)
    );
    expect(insertCall).toBeDefined();
    const params = insertCall![1] as unknown[];
    expect(params).toContain('pending');
    expect(params).toContain(UID);

    await app.close();
  });

  it('retries on a code collision until it wins', async () => {
    // First INSERT+verify loses (collision — verify SELECT returns empty),
    // second INSERT+verify wins (verify SELECT returns our code).
    const winningCode = 'WINNR9';
    mockQuery
      .mockResolvedValueOnce({ rows: [] }) // INSERT attempt 1
      .mockResolvedValueOnce({ rows: [] }) // SELECT verify 1 (collision — not ours)
      .mockResolvedValueOnce({ rows: [] }) // INSERT attempt 2
      .mockResolvedValueOnce({ rows: [{ code: winningCode }] }); // SELECT verify 2 (won)

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/invites',
      headers: authHeader(),
      payload: {},
    });
    expect(res.statusCode).toBe(201);
    // The route returns the locally-generated candidate that the verify SELECT
    // confirmed is ours. Here that's whatever genCode produced on attempt 2.
    const code = res.json().code;
    expect(code).toMatch(/^[A-Z2-9]{6}$/);

    // Two full INSERT+verify cycles happened (proving the retry).
    const insertCalls = mockQuery.mock.calls.filter(
      (c) => typeof c[0] === 'string' && /INSERT INTO invites/.test(c[0] as string)
    );
    const verifyCalls = mockQuery.mock.calls.filter(
      (c) => typeof c[0] === 'string' && /SELECT code FROM invites WHERE code/.test(c[0] as string)
    );
    expect(insertCalls).toHaveLength(2);
    expect(verifyCalls).toHaveLength(2);
    await app.close();
  });
});

describe('POST /invites/:code/redeem', () => {
  it('creates a couple, stamps the invite redeemed, links both users, returns coupleId', async () => {
    const now = Date.now();
    // Tx client sequence:
    //   1) BEGIN
    //   2) SELECT ... FOR UPDATE -> pending invite from UID
    //   3) INSERT couples
    //   4) UPDATE invites SET redeemed
    //   5) UPDATE users (inviter)
    //   6) UPDATE users (redeemer)
    //   7) COMMIT
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({ rows: [makeInviteRow({ created_by_uid: UID })] }) // SELECT FOR UPDATE
      .mockResolvedValueOnce({
        rows: [{ couple_id: null }, { couple_id: null }],
      }) // paired check -> both unpaired
      .mockResolvedValueOnce({ rows: [] }) // INSERT couples
      .mockResolvedValueOnce({ rows: [] }) // UPDATE invites
      .mockResolvedValueOnce({ rows: [] }) // UPDATE users inviter
      .mockResolvedValueOnce({ rows: [] }) // UPDATE users redeemer
      .mockResolvedValueOnce({ rows: [] }); // COMMIT

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/invites/${CODE}/redeem`,
      headers: authHeader(PARTNER), // PARTNER redeems UID's invite
      payload: {},
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.coupleId).toEqual(expect.any(String));
    expect(body.coupleId.length).toBeGreaterThan(10); // UUID

    // Tx issued BEGIN + COMMIT.
    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /BEGIN/.test(s))).toBe(true);
    expect(txSqls.some((s) => /COMMIT/.test(s))).toBe(true);
    // The invite was locked FOR UPDATE.
    expect(txSqls.some((s) => /FOR UPDATE/.test(s))).toBe(true);
    expect(mockClientRelease).toHaveBeenCalledTimes(1);

    // Post-commit WS broadcast to both partners.
    expect(sendToUid).toHaveBeenCalledTimes(2);
    const messages = sendToUid.mock.calls.map((c) => c[1] as { t: string });
    expect(messages.every((m) => m.t === 'pairing')).toBe(true);

    void now;
    await app.close();
  });

  it('is idempotent: redeeming an already-redeemed code returns the same coupleId', async () => {
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({
        rows: [makeInviteRow({ status: 'redeemed', couple_id: COUPLE_ID, created_by_uid: UID })],
      }) // SELECT FOR UPDATE -> already redeemed
      .mockResolvedValueOnce({
        rows: [{ user_a_uid: UID, user_b_uid: PARTNER }],
      }) // SELECT couple members (scope check)
      .mockResolvedValueOnce({ rows: [] }); // COMMIT (no further writes)

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/invites/${CODE}/redeem`,
      headers: authHeader(PARTNER), // PARTNER is the original redeemer
      payload: {},
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().coupleId).toBe(COUPLE_ID);

    // No couple INSERT happened (idempotent branch).
    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /INSERT INTO couples/.test(s))).toBe(false);
    await app.close();
  });

  it('returns 409 with no coupleId when a third party probes a redeemed code', async () => {
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({
        rows: [makeInviteRow({ status: 'redeemed', couple_id: COUPLE_ID, created_by_uid: UID })],
      }) // SELECT FOR UPDATE -> already redeemed
      .mockResolvedValueOnce({
        rows: [{ user_a_uid: UID, user_b_uid: PARTNER }],
      }) // SELECT couple members (scope check)
      .mockResolvedValueOnce({ rows: [] }); // ROLLBACK

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/invites/${CODE}/redeem`,
      headers: authHeader(THIRD), // THIRD is neither inviter nor redeemer
      payload: {},
    });

    expect(res.statusCode).toBe(409);
    const body = res.json();
    expect(body.coupleId).toBeUndefined();
    expect(body.error).toBe('conflict');
    expect(body.message).toMatch(/already been redeemed/i);

    // ROLLBACK issued, no couple INSERT, no post-commit WS broadcast.
    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /ROLLBACK/.test(s))).toBe(true);
    expect(txSqls.some((s) => /INSERT INTO couples/.test(s))).toBe(false);
    expect(sendToUid).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns 200 with coupleId when the inviter re-probes a redeemed code', async () => {
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({
        rows: [makeInviteRow({ status: 'redeemed', couple_id: COUPLE_ID, created_by_uid: UID })],
      }) // SELECT FOR UPDATE -> already redeemed
      .mockResolvedValueOnce({
        rows: [{ user_a_uid: UID, user_b_uid: PARTNER }],
      }) // SELECT couple members
      .mockResolvedValueOnce({ rows: [] }); // COMMIT

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/invites/${CODE}/redeem`,
      headers: authHeader(UID), // UID is the inviter (created_by_uid)
      payload: {},
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().coupleId).toBe(COUPLE_ID);
    await app.close();
  });

  it('returns 410 for an expired invite', async () => {
    const pastExpiry = Date.now() - 1000;
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({
        rows: [makeInviteRow({ expires_at: pastExpiry, status: 'pending' })],
      }) // SELECT FOR UPDATE -> expired
      .mockResolvedValueOnce({ rows: [] }); // ROLLBACK

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/invites/${CODE}/redeem`,
      headers: authHeader(PARTNER),
      payload: {},
    });

    expect(res.statusCode).toBe(410);
    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /ROLLBACK/.test(s))).toBe(true);
    await app.close();
  });

  it('returns 400 when the creator tries to redeem their own code', async () => {
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({ rows: [makeInviteRow({ created_by_uid: UID })] }) // SELECT FOR UPDATE
      .mockResolvedValueOnce({ rows: [] }); // ROLLBACK

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/invites/${CODE}/redeem`,
      headers: authHeader(UID), // UID redeems own invite
      payload: {},
    });
    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('rejects redeem when the redeemer is already paired (409, no coupleId leak, existing couple_id unchanged)', async () => {
    // Inviter (UID) has a pending invite; redeemer (PARTNER) already has a
    // couple_id. The guard must reject before any INSERT/UPDATE so the
    // redeemer's existing couple_id is left untouched.
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({ rows: [makeInviteRow({ created_by_uid: UID })] }) // SELECT FOR UPDATE -> pending
      .mockResolvedValueOnce({
        rows: [
          { couple_id: null }, // inviter (UID) unpaired
          { couple_id: COUPLE_ID }, // redeemer (PARTNER) already paired
        ],
      }) // paired check -> redeemer paired
      .mockResolvedValueOnce({ rows: [] }); // ROLLBACK

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/invites/${CODE}/redeem`,
      headers: authHeader(PARTNER), // PARTNER redeems UID's invite
      payload: {},
    });

    expect(res.statusCode).toBe(409);
    const body = res.json();
    expect(body.coupleId).toBeUndefined();
    expect(body.error).toBe('conflict');

    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /ROLLBACK/.test(s))).toBe(true);
    // No couple INSERT, no users couple_id UPDATE (existing pairing untouched).
    expect(txSqls.some((s) => /INSERT INTO couples/.test(s))).toBe(false);
    expect(txSqls.some((s) => /UPDATE users SET couple_id/.test(s))).toBe(false);
    expect(sendToUid).not.toHaveBeenCalled();
    await app.close();
  });

  it('rejects redeem when the inviter is already paired (409)', async () => {
    // Inviter (UID) created the invite, then got paired via a second invite,
    // now someone (PARTNER) tries to redeem the first (stale) invite.
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({ rows: [makeInviteRow({ created_by_uid: UID })] }) // SELECT FOR UPDATE -> pending
      .mockResolvedValueOnce({
        rows: [
          { couple_id: COUPLE_ID }, // inviter (UID) already paired
          { couple_id: null }, // redeemer (PARTNER) unpaired
        ],
      }) // paired check -> inviter paired
      .mockResolvedValueOnce({ rows: [] }); // ROLLBACK

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/invites/${CODE}/redeem`,
      headers: authHeader(PARTNER),
      payload: {},
    });

    expect(res.statusCode).toBe(409);
    expect(res.json().coupleId).toBeUndefined();

    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /ROLLBACK/.test(s))).toBe(true);
    expect(txSqls.some((s) => /INSERT INTO couples/.test(s))).toBe(false);
    expect(sendToUid).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns 404 when the invite code does not exist', async () => {
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({ rows: [] }) // SELECT FOR UPDATE -> empty
      .mockResolvedValueOnce({ rows: [] }); // ROLLBACK

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/invites/NOPE/redeem`,
      headers: authHeader(PARTNER),
      payload: {},
    });
    expect(res.statusCode).toBe(404);
    await app.close();
  });
});

describe('POST /couples/:id/unpair', () => {
  it('sets inactive, clears couple_id on both users, appends history, deletes blocks + overlaps', async () => {
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] }) // SELECT FOR UPDATE
      .mockResolvedValueOnce({ rows: [] }) // UPDATE couples status + history
      .mockResolvedValueOnce({ rows: [] }) // UPDATE users clear couple_id
      .mockResolvedValueOnce({ rows: [] }) // DELETE timeblocks
      .mockResolvedValueOnce({ rows: [] }) // DELETE overlaps_latest
      .mockResolvedValueOnce({ rows: [] }); // COMMIT

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/couples/${COUPLE_ID}/unpair`,
      headers: authHeader(UID),
      payload: {},
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().coupleId).toBe(COUPLE_ID);

    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    // status set to inactive + unpair_history appended (|| jsonb).
    const coupleUpdate = mockClientQuery.mock.calls.find(
      (c) => typeof c[0] === 'string' && /UPDATE couples SET status/.test(c[0] as string)
    );
    expect(coupleUpdate).toBeDefined();
    expect(coupleUpdate![0]).toMatch(/unpair_history = unpair_history \|\|/);
    // Both users' couple_id cleared.
    const usersUpdate = mockClientQuery.mock.calls.find(
      (c) => typeof c[0] === 'string' && /UPDATE users SET couple_id = NULL/.test(c[0] as string)
    );
    expect(usersUpdate).toBeDefined();
    // Timeblocks + overlaps deleted.
    expect(txSqls.some((s) => /DELETE FROM timeblocks/.test(s))).toBe(true);
    expect(txSqls.some((s) => /DELETE FROM overlaps_latest/.test(s))).toBe(true);
    expect(mockClientRelease).toHaveBeenCalledTimes(1);

    // WS broadcast to both partners.
    expect(sendToUid).toHaveBeenCalledTimes(2);
    const messages = sendToUid.mock.calls.map((c) => (c[1] as { t: string }).t);
    expect(messages.every((t) => t === 'unpair')).toBe(true);
    await app.close();
  });

  it('is idempotent: already-inactive couple clears caller couple_id and returns 200', async () => {
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({ rows: [makeCoupleRow({ status: 'inactive' })] }) // SELECT FOR UPDATE
      .mockResolvedValueOnce({ rows: [] }) // UPDATE users (clear caller's stale couple_id)
      .mockResolvedValueOnce({ rows: [] }); // COMMIT

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/couples/${COUPLE_ID}/unpair`,
      headers: authHeader(UID),
      payload: {},
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().idempotent).toBe(true);

    // No status update, no deletes in the idempotent branch.
    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /UPDATE couples SET status/.test(s))).toBe(false);
    expect(txSqls.some((s) => /DELETE FROM timeblocks/.test(s))).toBe(false);
    await app.close();
  });

  it('returns 403 for a non-member', async () => {
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({
        rows: [makeCoupleRow({ user_a_uid: 'other', user_b_uid: 'partner' })],
      }) // SELECT FOR UPDATE -> caller not a member
      .mockResolvedValueOnce({ rows: [] }); // ROLLBACK

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/couples/${COUPLE_ID}/unpair`,
      headers: authHeader(UID),
      payload: {},
    });
    expect(res.statusCode).toBe(403);
    const txSqls = mockClientQuery.mock.calls.map((c) => c[0] as string);
    expect(txSqls.some((s) => /ROLLBACK/.test(s))).toBe(true);
    await app.close();
  });

  it('returns 403 when the couple does not exist', async () => {
    mockClientQuery
      .mockResolvedValueOnce({ rows: [] }) // BEGIN
      .mockResolvedValueOnce({ rows: [] }) // SELECT FOR UPDATE -> empty
      .mockResolvedValueOnce({ rows: [] }); // ROLLBACK

    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: `/couples/missing/unpair`,
      headers: authHeader(UID),
      payload: {},
    });
    expect(res.statusCode).toBe(403);
    await app.close();
  });
});

describe('cleanupExpiredInvites', () => {
  it('flips pending+expired invites to status=expired', async () => {
    mockQuery.mockResolvedValueOnce({ rowCount: 3 });

    const count = await cleanupExpiredInvites();
    expect(count).toBe(3);

    const [sql, params] = mockQuery.mock.calls[0];
    expect(sql).toMatch(/UPDATE invites SET status = \$1 WHERE status = \$2 AND expires_at < \$3/);
    expect(params).toEqual(['expired', 'pending', expect.any(Number)]);
    expect((params as unknown[])[2] as number).toBeLessThanOrEqual(Date.now());
  });

  it('POST /admin/cleanup requires a valid ADMIN_TOKEN', async () => {
    mockQuery.mockResolvedValueOnce({ rowCount: 5 });

    const app = await buildApp();
    // No token -> 401.
    const bad = await app.inject({
      method: 'POST',
      url: '/admin/cleanup',
      payload: {},
    });
    expect(bad.statusCode).toBe(401);

    // Wrong token -> 401.
    const wrong = await app.inject({
      method: 'POST',
      url: '/admin/cleanup',
      headers: { authorization: 'Bearer wrong' },
      payload: {},
    });
    expect(wrong.statusCode).toBe(401);

    // Correct token -> 200.
    const ok = await app.inject({
      method: 'POST',
      url: '/admin/cleanup',
      headers: { authorization: 'Bearer secret-admin-token' },
      payload: {},
    });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().expired).toBe(5);
    await app.close();
  });
});
