import { describe, it, expect, beforeEach, vi } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

/**
 * Auth routes tests.
 *
 * Mocks:
 *  - firebase.ts -> getAuth().verifyIdToken (the Firebase Admin call)
 *  - db.ts       -> query (the pg pool)
 *
 * Covers deliverable 5: 401 on missing/invalid token; upsert new then existing;
 * FCM token dedup.
 */

const verifyIdToken = vi.fn();

vi.mock('../firebase.js', () => ({
  getAuth: () => ({ verifyIdToken }),
  initFirebaseAdmin: vi.fn(),
  getMessaging: vi.fn(),
  isFirebaseReady: () => true,
}));

const mockQuery = vi.fn();
vi.mock('../db.js', () => ({
  query: (...args: unknown[]) => mockQuery(...args),
  getPool: vi.fn(() => ({ query: mockQuery, end: vi.fn() })),
  endPool: vi.fn(),
}));

import { authRoutes, upsertUser, addFcmToken } from '../routes/auth.js';

const UID = 'uid-abc-123';
const EMAIL = 'alex@example.com';
const NAME = 'Alex Doe';
const PICTURE = 'https://img.example.com/alex.png';
const FCM = 'fcm-token-AAAA';

const decodedToken = {
  uid: UID,
  email: EMAIL,
  email_verified: true,
  name: NAME,
  picture: PICTURE,
  firebase: { sign_in_provider: 'password' },
};

function makeUserRow(overrides: Partial<{
  uid: string;
  email: string | null;
  display_name: string | null;
  photo_url: string | null;
  couple_id: string | null;
}> = {}) {
  return {
    uid: UID,
    email: EMAIL,
    display_name: NAME,
    photo_url: PICTURE,
    couple_id: null,
    ...overrides,
  };
}

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  await app.register(authRoutes);
  return app;
}

beforeEach(() => {
  verifyIdToken.mockReset();
  mockQuery.mockReset();
});

describe('POST /auth/verify', () => {
  it('returns 401 when the Authorization header is missing', async () => {
    const app = await buildApp();
    const res = await app.inject({ method: 'POST', url: '/auth/verify' });
    expect(res.statusCode).toBe(401);
    const body = res.json();
    expect(body.error).toBe('unauthorized');
    expect(verifyIdToken).not.toHaveBeenCalled();
    expect(mockQuery).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns 401 when verifyIdToken rejects (invalid token)', async () => {
    verifyIdToken.mockRejectedValue(new Error('Firebase ID token has expired.'));
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/auth/verify',
      headers: { authorization: 'Bearer expired-or-tampered' },
    });
    expect(res.statusCode).toBe(401);
    const body = res.json();
    expect(body.error).toBe('unauthorized');
    expect(body.message).toMatch(/expired/i);
    expect(verifyIdToken).toHaveBeenCalledTimes(1);
    expect(mockQuery).not.toHaveBeenCalled();
    await app.close();
  });

  it('upserts a new user and returns it with coupleId null', async () => {
    verifyIdToken.mockResolvedValue(decodedToken);
    mockQuery.mockResolvedValue({ rows: [makeUserRow({ couple_id: null })] });
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/auth/verify',
      headers: { authorization: 'Bearer valid-id-token' },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.user).toEqual({
      uid: UID,
      email: EMAIL,
      display_name: NAME,
      photo_url: PICTURE,
      couple_id: null,
    });

    // Verify the upsert SQL + params.
    expect(mockQuery).toHaveBeenCalledTimes(1);
    const [sql, params] = mockQuery.mock.calls[0];
    expect(sql).toMatch(/INSERT INTO users/);
    expect(sql).toMatch(/ON CONFLICT \(uid\) DO UPDATE/);
    expect(params).toEqual([UID, EMAIL, NAME, PICTURE, expect.any(Number)]);
    await app.close();
  });

  it('refreshes profile fields on re-login and returns the existing coupleId', async () => {
    verifyIdToken.mockResolvedValue(decodedToken);
    mockQuery.mockResolvedValue({
      rows: [makeUserRow({ couple_id: 'cpl-xyz', email: 'new@example.com' })],
    });
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/auth/verify',
      headers: { authorization: 'Bearer valid-id-token' },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.user.couple_id).toBe('cpl-xyz');
    // ON CONFLICT path preserves couple_id; the RETURNING row reflects the
    // stored state, not the token. Email refresh is driven by EXCLUDED.
    expect(mockQuery).toHaveBeenCalledTimes(1);
    const sql = mockQuery.mock.calls[0][0] as string;
    expect(sql).toMatch(/SET email = EXCLUDED\.email/);
    await app.close();
  });
});

describe('POST /auth/fcm-token', () => {
  it('returns 401 without a bearer token', async () => {
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/auth/fcm-token',
      payload: { token: FCM },
    });
    expect(res.statusCode).toBe(401);
    expect(mockQuery).not.toHaveBeenCalled();
    await app.close();
  });

  it('returns 400 when the body has no token', async () => {
    verifyIdToken.mockResolvedValue(decodedToken);
    const app = await buildApp();
    const res = await app.inject({
      method: 'POST',
      url: '/auth/fcm-token',
      headers: { authorization: 'Bearer valid-id-token' },
      payload: {},
    });
    expect(res.statusCode).toBe(400);
    expect(mockQuery).not.toHaveBeenCalled();
    await app.close();
  });

  it('appends the FCM token with dedup (array_remove then ||)', async () => {
    verifyIdToken.mockResolvedValue(decodedToken);
    mockQuery.mockResolvedValue({ rows: [] });
    const app = await buildApp();

    const res = await app.inject({
      method: 'POST',
      url: '/auth/fcm-token',
      headers: { authorization: 'Bearer valid-id-token' },
      payload: { token: FCM },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
    expect(mockQuery).toHaveBeenCalledTimes(1);
    const [sql, params] = mockQuery.mock.calls[0];
    expect(sql).toMatch(/array_remove\(fcm_tokens, \$2\)/);
    expect(sql).toMatch(/\|\| ARRAY\[\$2\]/);
    expect(params).toEqual([UID, FCM]);
    await app.close();
  });
});

describe('upsertUser / addFcmToken units', () => {
  it('upsertUser passes decoded fields through and returns the stored row', async () => {
    mockQuery.mockResolvedValue({ rows: [makeUserRow()] });
    const row = await upsertUser(decodedToken);
    expect(row).toEqual(makeUserRow());
    const params = mockQuery.mock.calls[0][1] as unknown[];
    expect(params[0]).toBe(UID);
    expect(params[1]).toBe(EMAIL);
    expect(params[2]).toBe(NAME);
    expect(params[3]).toBe(PICTURE);
  });

  it('addFcmToken dedups by removing-then-appending', async () => {
    mockQuery.mockResolvedValue({ rows: [] });
    await addFcmToken(UID, FCM);
    expect(mockQuery).toHaveBeenCalledTimes(1);
    const [sql, params] = mockQuery.mock.calls[0];
    expect(sql).toMatch(/array_remove/);
    expect(params).toEqual([UID, FCM]);
  });
});
