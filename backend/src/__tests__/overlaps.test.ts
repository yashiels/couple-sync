import { describe, it, expect, beforeEach, vi } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';

/**
 * V8 — GET /overlaps/latest route tests.
 *
 * Covers:
 *  - 401 when no bearer token
 *  - 400 when coupleId query param missing
 *  - 403 when caller is not a member of the couple
 *  - 404 when no stored overlap row exists (Flutter maps → null)
 *  - 200 with the stored row, camelCase wire shape, on the happy path
 *
 * Mocks mirror blocks.test.ts: firebase verifyIdToken, db query, and the
 * assertMember couple lookup (which reads from couples via db.query).
 */

const verifyIdToken = vi.fn();

vi.mock('../firebase.js', () => ({
  getAuth: () => ({ verifyIdToken }),
  initFirebaseAdmin: vi.fn(),
  getMessaging: vi.fn(),
  isFirebaseReady: () => true,
}));

vi.mock('../config.js', () => ({
  getConfig: () => ({
    databaseUrl: 'postgres://test',
    firebaseProjectId: 'test',
    firebaseServiceAccountJson: '{}',
    domain: 'api.test',
    port: 3000,
    adminToken: '',
  }),
  loadConfig: () => ({
    databaseUrl: 'postgres://test',
    firebaseProjectId: 'test',
    firebaseServiceAccountJson: '{}',
    domain: 'api.test',
    port: 3000,
    adminToken: '',
  }),
}));

const mockQuery = vi.fn();

vi.mock('../db.js', () => ({
  query: (...args: unknown[]) => mockQuery(...args),
  getPool: () => ({ query: mockQuery, connect: () => ({ query: mockQuery, release: vi.fn() }) }),
  endPool: vi.fn(),
}));

vi.mock('../routes/sync.js', () => ({
  sendToCouple: vi.fn(),
  sendToUid: vi.fn(),
  sockets: new Map(),
  coupleMembers: new Map(),
  authorizeOverlapMessage: vi.fn(),
}));

import { overlapRoutes } from '../routes/overlaps.js';

const UID = 'uid-alex';
const PARTNER = 'uid-sam';
const COUPLE_ID = 'cpl-1';

const decodedToken = { uid: UID, email: 'alex@example.com', email_verified: true };

function makeCoupleRow(overrides: Record<string, unknown> = {}) {
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

function makeOverlapRow(overrides: Record<string, unknown> = {}) {
  return {
    couple_id: COUPLE_ID,
    windows: [{ startUtc: 1000, endUtc: 960000, durationMinutes: 15, score: 0.9, reasonableBoth: true }],
    computed_at: 5000,
    input_hash: 'hash-abc',
    computed_by: UID,
    ...overrides,
  };
}

async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });
  await app.register(overlapRoutes);
  return app;
}

function authHeader(): Record<string, string> {
  return { authorization: 'Bearer valid-id-token' };
}

beforeEach(() => {
  verifyIdToken.mockReset();
  mockQuery.mockReset();
  verifyIdToken.mockResolvedValue(decodedToken);
});

describe('GET /overlaps/latest', () => {
  it('returns 401 when no bearer token', async () => {
    verifyIdToken.mockRejectedValue(new Error('bad token'));
    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: `/overlaps/latest?coupleId=${COUPLE_ID}` });
    expect(res.statusCode).toBe(401);
  });

  it('returns 400 when coupleId query param is missing', async () => {
    const app = await buildApp();
    const res = await app.inject({ method: 'GET', url: '/overlaps/latest', headers: authHeader() });
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('bad_request');
  });

  it('returns 403 when caller is not a member of the couple', async () => {
    // assertMember → couple exists but caller is not a member.
    mockQuery.mockResolvedValueOnce({
      rows: [makeCoupleRow({ user_a_uid: 'someone-else', user_b_uid: 'partner-else' })],
    });
    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/overlaps/latest?coupleId=${COUPLE_ID}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(403);
    expect(res.json().error).toBe('forbidden');
  });

  it('returns 403 when the couple does not exist (no existence leak)', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/overlaps/latest?coupleId=${COUPLE_ID}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(403);
  });

  it('returns 404 when no stored overlap row exists', async () => {
    // assertMember ok, then overlaps_latest SELECT returns 0 rows.
    mockQuery
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] }) // couples lookup (assertMember)
      .mockResolvedValueOnce({ rows: [] }); // overlaps_latest SELECT
    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/overlaps/latest?coupleId=${COUPLE_ID}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(404);
    expect(res.json().error).toBe('not_found');
  });

  it('returns 200 with the stored row in camelCase wire shape', async () => {
    const row = makeOverlapRow();
    mockQuery
      .mockResolvedValueOnce({ rows: [makeCoupleRow()] }) // assertMember
      .mockResolvedValueOnce({ rows: [row] }); // overlaps_latest SELECT
    const app = await buildApp();
    const res = await app.inject({
      method: 'GET',
      url: `/overlaps/latest?coupleId=${COUPLE_ID}`,
      headers: authHeader(),
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.windows).toEqual(row.windows);
    expect(body.computedAt).toBe(5000);
    expect(body.inputHash).toBe('hash-abc');
    expect(body.computedBy).toBe(UID);
  });
});
