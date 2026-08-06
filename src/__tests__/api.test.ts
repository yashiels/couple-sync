import { beforeEach, describe, expect, it, vi } from 'vitest';

import { api, ApiError } from '../api';

// expo-constants and src/auth both reach native modules, so both are mocked. Mocking auth is also
// what makes "the token the client actually sent" observable.
vi.mock('expo-constants', () => ({
  default: { expoConfig: { extra: { apiBaseUrl: 'http://api.test' } } },
}));

const getIdToken = vi.fn<() => Promise<string | null>>();
vi.mock('../auth', () => ({ getIdToken: () => getIdToken() }));

function jsonResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as unknown as Response;
}

const fetchMock = vi.fn<(url: string, init: RequestInit) => Promise<Response>>();

/** The (url, init) of the nth fetch, typed. */
function call(n = 0): { url: string; init: RequestInit } {
  const args = fetchMock.mock.calls[n];
  if (!args) throw new Error(`no fetch call at index ${n}`);
  return { url: args[0], init: args[1] };
}

function headers(n = 0): Record<string, string> {
  return call(n).init.headers as Record<string, string>;
}

beforeEach(() => {
  fetchMock.mockReset();
  getIdToken.mockReset();
  getIdToken.mockResolvedValue('id-token-1');
  vi.stubGlobal('fetch', fetchMock);
});

describe('request plumbing', () => {
  it('sends Authorization: Bearer with the current id token on every call', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ user: { uid: 'u1' } }));
    await api.me();

    getIdToken.mockResolvedValue('id-token-2'); // e.g. after a refresh
    await api.me();

    expect(headers(0).Authorization).toBe('Bearer id-token-1');
    expect(headers(1).Authorization).toBe('Bearer id-token-2');
  });

  it('does not call the server at all when there is no session', async () => {
    getIdToken.mockResolvedValue(null);
    await expect(api.me()).rejects.toMatchObject({ status: 401, code: 'no_session' });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('throws ApiError carrying the status and the server error code on a 4xx', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ error: 'forbidden' }, 403));
    const err = await api.getCouple('c1').catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err).toMatchObject({ status: 403, code: 'forbidden' });
  });

  it('throws ApiError on a 5xx', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ error: 'internal' }, 500));
    await expect(api.me()).rejects.toMatchObject({ status: 500, code: 'internal' });
  });

  it('does not retry a 4xx', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ error: 'invalid_timezone' }, 400));
    await expect(api.patchUser('u1', { timezone: 'nope' })).rejects.toBeInstanceOf(ApiError);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('surfaces a network failure as an ApiError rather than a raw TypeError', async () => {
    fetchMock.mockRejectedValue(new TypeError('Network request failed'));
    const err = await api.me().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect(err).not.toBeInstanceOf(TypeError);
    expect((err as ApiError).status).toBe(0);
  });

  it('falls back to an http_<status> code when the error body is not JSON', async () => {
    fetchMock.mockResolvedValue({
      ok: false,
      status: 502,
      json: async () => {
        throw new Error('not json');
      },
    } as unknown as Response);
    await expect(api.me()).rejects.toMatchObject({ status: 502, code: 'http_502' });
  });
});

describe('envelopes and shapes', () => {
  it('unwraps { user } from /users/me', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ user: { uid: 'u1', couple_id: 'c1' } }));
    await expect(api.me()).resolves.toEqual({ uid: 'u1', couple_id: 'c1' });
    expect(call().url).toBe('http://api.test/users/me');
  });

  it('unwraps { couple } from /couples/:id', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ couple: { id: 'c1', user_a_uid: 'u1' } }));
    await expect(api.getCouple('c1')).resolves.toEqual({ id: 'c1', user_a_uid: 'u1' });
  });

  it('unwraps { blocks } from /blocks and puts the range in the query string', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ blocks: [{ id: 'b1', occurrences: [] }] }));
    await expect(api.listBlocks('c1', 100, 200)).resolves.toEqual([{ id: 'b1', occurrences: [] }]);
    expect(call().url).toBe('http://api.test/blocks?coupleId=c1&from=100&to=200');
  });

  it('returns the invite body flat, not wrapped', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ code: 'ABC123', expires_at: 42 }));
    await expect(api.createInvite()).resolves.toEqual({ code: 'ABC123', expires_at: 42 });
  });

  it('sends couple_id in the body on a write and coupleId in the query on a delete', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ block: { id: 'b1' } }));
    await api.createBlock('c1', {
      title: 'Gym',
      type: 'busy',
      category: null,
      start_utc: 1,
      end_utc: 2,
      timezone: 'Europe/Berlin',
      recurrence_rule: null,
      visibility: 'bothPartners',
    });
    expect(JSON.parse(call().init.body as string)).toMatchObject({ couple_id: 'c1' });

    fetchMock.mockResolvedValue(jsonResponse({ ok: true }));
    await api.deleteBlock('c1', 'b1');
    expect(call(1).url).toBe('http://api.test/blocks/b1?coupleId=c1');
    expect(call(1).init.method).toBe('DELETE');
  });

  it('sends timestamps as integers, never as ISO strings', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ block: { id: 'b1' } }));
    const start = Date.UTC(2026, 7, 4, 18, 0);
    await api.createBlock('c1', {
      title: 'Gym',
      type: 'busy',
      category: null,
      start_utc: start,
      end_utc: start + 3_600_000,
      timezone: 'Europe/Berlin',
      recurrence_rule: null,
      visibility: 'bothPartners',
    });
    const body = JSON.parse(call().init.body as string) as Record<string, unknown>;
    expect(body.start_utc).toBe(start);
    expect(typeof body.start_utc).toBe('number');
    expect(call().init.body as string).not.toMatch(/\d{4}-\d{2}-\d{2}T/);
  });

  it('sends the token body on DELETE /auth/fcm-token', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ fcm_tokens: [] }));
    await api.deleteFcmToken('device-token');
    expect(call().url).toBe('http://api.test/auth/fcm-token');
    expect(call().init.method).toBe('DELETE');
    expect(JSON.parse(call().init.body as string)).toEqual({ token: 'device-token' });
  });

  it('returns the stored count from PUT /blocks/google', async () => {
    fetchMock.mockResolvedValue(jsonResponse({ count: 3 }));
    await expect(api.putGoogleBlocks('c1', [{ start_utc: 1, end_utc: 2 }])).resolves.toBe(3);
    expect(JSON.parse(call().init.body as string)).toEqual({
      couple_id: 'c1',
      intervals: [{ start_utc: 1, end_utc: 2 }],
    });
  });
});
