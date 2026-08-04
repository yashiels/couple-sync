import Fastify from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import type { IncomingMessage } from 'node:http';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// firebase.ts initializes the Admin SDK at import, so it is mocked out entirely.
vi.mock('../firebase.js', () => ({ verifyIdToken: vi.fn() }));

const { verifyIdToken } = await import('../firebase.js');
const { requireAuth, uidFromRequest } = await import('../auth.js');
const { registerErrorHandler } = await import('../http.js');

const claims = (over: Partial<DecodedIdToken> = {}): DecodedIdToken =>
  ({
    uid: 'uid-a',
    sub: 'uid-a',
    email: 'a@example.com',
    name: 'Ada',
    picture: 'https://example.com/a.png',
    aud: 'nexion-ai-prod',
    iss: 'https://securetoken.google.com/nexion-ai-prod',
    iat: 1,
    exp: 2,
    auth_time: 1,
    firebase: { identities: {}, sign_in_provider: 'google.com' },
    ...over,
  }) as DecodedIdToken;

function app() {
  const a = Fastify();
  registerErrorHandler(a);
  a.get('/me', { preHandler: requireAuth }, async (req) => ({
    uid: req.uid,
    email: req.claims.email,
    name: req.claims.name as string | undefined,
    picture: req.claims.picture,
  }));
  return a;
}

// uidFromRequest takes a raw IncomingMessage off the WS upgrade, not a FastifyRequest.
const upgrade = (headers: Record<string, string>, url = '/sync') =>
  ({ headers, url }) as unknown as IncomingMessage;

beforeEach(() => {
  vi.mocked(verifyIdToken).mockReset();
});

describe('requireAuth', () => {
  it('401s with no Authorization header', async () => {
    const res = await app().inject({ method: 'GET', url: '/me' });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: 'missing_token' });
    expect(verifyIdToken).not.toHaveBeenCalled();
  });

  it('401s on a malformed Authorization header', async () => {
    const res = await app().inject({
      method: 'GET',
      url: '/me',
      headers: { authorization: 'abc.def.ghi' },
    });
    expect(res.statusCode).toBe(401);
    expect(verifyIdToken).not.toHaveBeenCalled();
  });

  it('401s when verifyIdToken rejects', async () => {
    vi.mocked(verifyIdToken).mockRejectedValue(new Error('expired'));
    const res = await app().inject({
      method: 'GET',
      url: '/me',
      headers: { authorization: 'Bearer stale' },
    });
    expect(res.statusCode).toBe(401);
    expect(res.json()).toEqual({ error: 'invalid_token' });
  });

  it('sets req.uid from a valid token', async () => {
    vi.mocked(verifyIdToken).mockResolvedValue(claims());
    const res = await app().inject({
      method: 'GET',
      url: '/me',
      headers: { authorization: 'Bearer good' },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().uid).toBe('uid-a');
    expect(verifyIdToken).toHaveBeenCalledWith('good');
  });

  it('sets req.claims with email, name and picture from the decoded token', async () => {
    // Task 6's /auth/verify upsert reads these off req.claims; a narrowed {uid} would lose them.
    vi.mocked(verifyIdToken).mockResolvedValue(claims());
    const res = await app().inject({
      method: 'GET',
      url: '/me',
      headers: { authorization: 'Bearer good' },
    });
    expect(res.json()).toEqual({
      uid: 'uid-a',
      email: 'a@example.com',
      name: 'Ada',
      picture: 'https://example.com/a.png',
    });
  });
});

describe('uidFromRequest', () => {
  it('reads the token from the Authorization header on a WS upgrade', async () => {
    vi.mocked(verifyIdToken).mockResolvedValue(claims());
    await expect(uidFromRequest(upgrade({ authorization: 'Bearer header-tok' }))).resolves.toBe(
      'uid-a',
    );
    expect(verifyIdToken).toHaveBeenCalledWith('header-tok');
  });

  it('falls back to ?token= on a WS upgrade when no header is present', async () => {
    vi.mocked(verifyIdToken).mockResolvedValue(claims());
    await expect(uidFromRequest(upgrade({}, '/sync?token=query-tok'))).resolves.toBe('uid-a');
    expect(verifyIdToken).toHaveBeenCalledWith('query-tok');
  });

  it('prefers the header over ?token= when both are present', async () => {
    vi.mocked(verifyIdToken).mockResolvedValue(claims());
    await uidFromRequest(upgrade({ authorization: 'Bearer header-tok' }, '/sync?token=query-tok'));
    expect(verifyIdToken).toHaveBeenCalledWith('header-tok');
  });

  it('throws 401 when neither is present', async () => {
    await expect(uidFromRequest(upgrade({}, '/sync'))).rejects.toMatchObject({
      status: 401,
      code: 'missing_token',
    });
  });

  it('throws 401 when verifyIdToken rejects', async () => {
    vi.mocked(verifyIdToken).mockRejectedValue(new Error('expired'));
    await expect(uidFromRequest(upgrade({ authorization: 'Bearer stale' }))).rejects.toMatchObject({
      status: 401,
      code: 'invalid_token',
    });
  });
});
