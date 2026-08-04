import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// These tests exist because the previous build console.warn'ed on a bad Firebase credential and an
// unreachable database and then listened anyway: the container reported healthy and 401'd every
// request. index.ts is therefore split into start() (throws) and main() (exits non-zero), so both
// halves are observable here — no child process, no real port.

let listen: ReturnType<typeof vi.fn>;
let routes: Map<string, () => Promise<unknown>>;
let order: string[];

function fakeApp() {
  return {
    log: { error: vi.fn() },
    setErrorHandler: vi.fn(),
    register: vi.fn(async () => {}),
    get: vi.fn((path: string, handler: () => Promise<unknown>) => routes.set(path, handler)),
    listen,
  };
}

async function loadIndex({ db = 'ok', creds = 'ok' }: { db?: 'ok' | 'fail'; creds?: 'ok' | 'fail' }) {
  vi.resetModules();
  vi.doMock('../config.js', () => ({
    config: { port: 0, corsOrigins: ['https://app.example'] },
  }));
  vi.doMock('../db.js', () => ({
    assertReachable: vi.fn(async () => {
      order.push('db');
      if (db === 'fail') throw new Error('ECONNREFUSED 127.0.0.1:5432');
    }),
  }));
  vi.doMock('../firebase.js', () => ({
    assertCredentials: vi.fn(async () => {
      order.push('creds');
      if (creds === 'fail') throw new Error('invalid_grant: account not found');
    }),
  }));
  vi.doMock('fastify', () => ({ default: vi.fn(() => fakeApp()) }));
  return import('../index.js');
}

beforeEach(() => {
  listen = vi.fn(async () => {
    order.push('listen');
    return 'http://127.0.0.1:0';
  });
  routes = new Map();
  order = [];
  vi.spyOn(console, 'error').mockImplementation(() => {});
  vi.spyOn(process, 'exit').mockImplementation((() => undefined) as never);
});

afterEach(() => {
  // doMock registrations outlive resetModules, so they have to be dropped explicitly — otherwise
  // the credential-probe suite below would import the mocked firebase.ts instead of the real one.
  for (const id of ['fastify', '../config.js', '../db.js', '../firebase.js']) vi.doUnmock(id);
  vi.restoreAllMocks();
});

describe('boot', () => {
  it('exits non-zero when the service account parses but the credential is rejected', async () => {
    const { main } = await loadIndex({ creds: 'fail' });
    await main();
    expect(process.exit).toHaveBeenCalledWith(1);
  });

  it('exits non-zero when the database is unreachable', async () => {
    const { main } = await loadIndex({ db: 'fail' });
    await main();
    expect(process.exit).toHaveBeenCalledWith(1);
  });

  it('does NOT begin listening in either case', async () => {
    const badCreds = await loadIndex({ creds: 'fail' });
    await expect(badCreds.start()).rejects.toThrow(/invalid_grant/);
    expect(listen).not.toHaveBeenCalled();
    // Not even the health route is registered, so there is nothing to answer 200.
    expect(routes.size).toBe(0);

    routes = new Map();
    order = [];
    const badDb = await loadIndex({ db: 'fail' });
    await expect(badDb.start()).rejects.toThrow(/ECONNREFUSED/);
    expect(listen).not.toHaveBeenCalled();
    expect(routes.size).toBe(0);
  });

  it('reports healthy only after both probes passed', async () => {
    const { start } = await loadIndex({});
    await start();
    expect(order).toEqual(['db', 'creds', 'listen']);
    expect(listen).toHaveBeenCalledWith({ port: 0, host: '0.0.0.0' });
    expect(process.exit).not.toHaveBeenCalled();
    await expect(routes.get('/health')?.()).resolves.toMatchObject({ status: 'ok' });
  });
});

describe('credential probe', () => {
  // Real firebase.ts, with only the Admin SDK's app module faked, so the probe's own logic is under
  // test rather than a mock of it.
  const getAccessToken = vi.fn(async () => ({ access_token: 'tok', expires_in: 3600 }));

  async function loadFirebase(projectId: string, serviceAccountProjectId: string) {
    vi.resetModules();
    getAccessToken.mockClear();
    vi.doMock('firebase-admin/app', () => ({
      cert: vi.fn(() => ({ getAccessToken })),
      initializeApp: vi.fn(() => ({ name: 'test' })),
    }));
    vi.doMock('../config.js', () => ({
      config: {
        firebaseProjectId: projectId,
        firebaseServiceAccount: {
          projectId: serviceAccountProjectId,
          clientEmail: 'sa@example.iam.gserviceaccount.com',
          privateKey: 'fake',
        },
      },
    }));
    return import('../firebase.js');
  }

  afterEach(() => {
    vi.doUnmock('firebase-admin/app');
  });

  it('exits non-zero when FIREBASE_PROJECT_ID does not match the service account projectId', async () => {
    const { assertCredentials } = await loadFirebase('right-project', 'other-project');
    await expect(assertCredentials()).rejects.toThrow(/does not match the service account/);
    // Cheap check first: a mismatch is decidable without a network call.
    expect(getAccessToken).not.toHaveBeenCalled();
  });

  it('mints an access token, which is the only thing that exercises the private key', async () => {
    // verifyIdToken('not-a-token') would reject during JWT decoding, before the credential is used,
    // so it passes with a bogus key. getAccessToken() is the real probe.
    const { assertCredentials } = await loadFirebase('p', 'p');
    await expect(assertCredentials()).resolves.toBeUndefined();
    expect(getAccessToken).toHaveBeenCalledTimes(1);
  });

  it('rejects when the private key cannot mint a token', async () => {
    const { assertCredentials } = await loadFirebase('p', 'p');
    getAccessToken.mockRejectedValueOnce(new Error('error:1E08010C:DECODER routines'));
    await expect(assertCredentials()).rejects.toThrow(/DECODER/);
  });
});
