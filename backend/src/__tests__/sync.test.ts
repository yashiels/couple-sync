import Fastify, { type FastifyInstance } from 'fastify';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { WebSocket } from 'ws';
import type { WsMessage } from '../wire.js';

// A real ws client against a real server on an ephemeral port. A fake socket would hide everything
// that actually matters here: the upgrade handshake, the close code, and the registry side effects.
vi.mock('../firebase.js', () => ({ verifyIdToken: vi.fn() }));
vi.mock('../db.js', () => ({ query: vi.fn() }));

const { verifyIdToken } = await import('../firebase.js');
const { query } = await import('../db.js');
const { attachSyncServer } = await import('../sync.js');
// The real registry: this suite's whole job is proving sync.ts keeps it honest.
const { isOnline, sendTo } = await import('../sockets.js');

let app: FastifyInstance;
let url: string;
/** Every client a test opened, closed in afterEach so the registry never leaks across tests. */
let clients: WebSocket[] = [];
let coupleId: string | null = 'c1';

beforeAll(async () => {
  // `good-<uid>` verifies to that uid; anything else is a rejected token.
  vi.mocked(verifyIdToken).mockImplementation(async (token: string) => {
    if (!token.startsWith('good-')) throw new Error('Decoding Firebase ID token failed');
    const uid = token.slice('good-'.length);
    return { uid, sub: uid } as DecodedIdToken;
  });
  vi.mocked(query).mockImplementation((async (sql: string) => {
    if (/SELECT couple_id FROM users WHERE uid = \$1/.test(sql)) return [{ couple_id: coupleId }];
    throw new Error(`unexpected statement on the WS path: ${sql}`);
  }) as typeof query);

  app = Fastify();
  attachSyncServer(app);
  await app.listen({ port: 0, host: '127.0.0.1' });
  const addr = app.server.address();
  if (addr === null || typeof addr === 'string') throw new Error('no ephemeral port');
  url = `ws://127.0.0.1:${addr.port}/sync`;
});

afterAll(async () => {
  await app.close();
});

beforeEach(() => {
  coupleId = 'c1';
  vi.mocked(query).mockClear();
});

afterEach(async () => {
  for (const c of clients) c.close();
  clients = [];
  // The registry is cleaned by the server's 'close' handler, which lands a tick later.
  await settle();
});

function connect(token: string | null, via: 'header' | 'query' = 'header'): WebSocket {
  const ws =
    token === null
      ? new WebSocket(url)
      : via === 'header'
        ? new WebSocket(url, { headers: { authorization: `Bearer ${token}` } })
        : new WebSocket(`${url}?token=${token}`);
  clients.push(ws);
  return ws;
}

/** Resolves with the next JSON frame; rejects if the socket closes first. */
function nextMessage(ws: WebSocket): Promise<WsMessage> {
  return new Promise((resolve, reject) => {
    ws.once('message', (data) => resolve(JSON.parse(String(data)) as WsMessage));
    ws.once('close', (code) => reject(new Error(`closed before any message: ${code}`)));
  });
}

function closeCode(ws: WebSocket): Promise<number> {
  return new Promise((resolve) => {
    ws.once('close', (code) => resolve(code));
  });
}

/** Lets the server finish whatever it started — nothing here waits longer than a few macrotasks. */
const settle = () => new Promise((res) => setTimeout(res, 30));

/** Resolves only if NO frame arrives, which is what "silently ignored" means. */
async function expectNothingBack(ws: WebSocket): Promise<void> {
  let got: string | null = null;
  const onMessage = (d: unknown) => {
    got = String(d);
  };
  ws.on('message', onMessage);
  await settle();
  ws.off('message', onMessage);
  expect(got).toBeNull();
}

describe('the /sync upgrade', () => {
  it('closes with 4001 when no token is supplied', async () => {
    await expect(closeCode(connect(null))).resolves.toBe(4001);
  });

  it('closes with 4001 when verifyIdToken rejects', async () => {
    await expect(closeCode(connect('rubbish', 'query'))).resolves.toBe(4001);
  });

  it('accepts a token from the Authorization header on the upgrade', async () => {
    const ws = connect('good-u-header', 'header');
    await expect(nextMessage(ws)).resolves.toMatchObject({ t: 'hello', uid: 'u-header' });
  });

  it('accepts a token from ?token= when no header is present', async () => {
    const ws = connect('good-u-query', 'query');
    await expect(nextMessage(ws)).resolves.toMatchObject({ t: 'hello', uid: 'u-query' });
  });

  it('closes with 1011, not 4001, when the couple lookup fails', async () => {
    // A database blip is not an auth failure; 4001 would send the app back through sign-in.
    vi.mocked(query).mockRejectedValueOnce(new Error('ECONNREFUSED 127.0.0.1:5432'));
    await expect(closeCode(connect('good-u-dberr'))).resolves.toBe(1011);
  });
});

describe('hello', () => {
  it('sends hello with uid and couple_id immediately on connect', async () => {
    const ws = connect('good-u1');
    await expect(nextMessage(ws)).resolves.toEqual({ t: 'hello', uid: 'u1', couple_id: 'c1' });
  });

  it('reads couple_id live from the database, because the app treats it as authoritative', async () => {
    // A device that missed the `pairing` broadcast reconciles from this value, so a cached or
    // token-derived couple id would leave it permanently unpaired.
    coupleId = 'c-paired-while-offline';
    const ws = connect('good-u2');

    await expect(nextMessage(ws)).resolves.toEqual({
      t: 'hello',
      uid: 'u2',
      couple_id: 'c-paired-while-offline',
    });
    expect(vi.mocked(query).mock.calls[0]?.[1]).toEqual(['u2']);
  });

  it('sends couple_id null for an unpaired user', async () => {
    coupleId = null;
    const ws = connect('good-u3');
    await expect(nextMessage(ws)).resolves.toEqual({ t: 'hello', uid: 'u3', couple_id: null });
  });
});

describe('the socket registry', () => {
  it('registers the socket so sendTo reaches it', async () => {
    const ws = connect('good-u4');
    await nextMessage(ws);

    const inbound = nextMessage(ws);
    expect(sendTo('u4', { t: 'unpair', couple_id: 'c1' })).toBe(true);
    await expect(inbound).resolves.toEqual({ t: 'unpair', couple_id: 'c1' });
  });

  it('unregisters on close, after which isOnline is false', async () => {
    const ws = connect('good-u5');
    await nextMessage(ws);
    expect(isOnline('u5')).toBe(true);

    ws.close();
    await settle();

    expect(isOnline('u5')).toBe(false);
    expect(sendTo('u5', { t: 'unpair', couple_id: 'c1' })).toBe(false);
  });

  it('supports two concurrent sockets for the same uid', async () => {
    const phone = connect('good-u6');
    const tablet = connect('good-u6');
    await Promise.all([nextMessage(phone), nextMessage(tablet)]);

    const both = Promise.all([nextMessage(phone), nextMessage(tablet)]);
    expect(sendTo('u6', { t: 'blocks:changed', couple_id: 'c1' })).toBe(true);
    await expect(both).resolves.toEqual([
      { t: 'blocks:changed', couple_id: 'c1' },
      { t: 'blocks:changed', couple_id: 'c1' },
    ]);

    // One device signing out must not take the other offline.
    phone.close();
    await settle();
    expect(isOnline('u6')).toBe(true);
  });
});

describe('inbound frames', () => {
  it('silently ignores an inbound message with an unrecognised t', async () => {
    const ws = connect('good-u7');
    await nextMessage(ws);

    ws.send(JSON.stringify({ t: 'some:future:message', payload: 1 }));
    await expectNothingBack(ws);

    // Dropped, not fatal: forward-compat means the socket survives.
    expect(ws.readyState).toBe(WebSocket.OPEN);
    expect(isOnline('u7')).toBe(true);
  });

  it('ignores an inbound overlap message — clients no longer publish windows', async () => {
    const ws = connect('good-u8');
    await nextMessage(ws);
    const queriesAfterHello = vi.mocked(query).mock.calls.length;

    ws.send(
      JSON.stringify({
        t: 'overlap',
        couple_id: 'c1',
        computed_at: Date.now(),
        windows: [
          { startUtc: 1, endUtc: 2, durationMinutes: 60, score: 99, reasonableBoth: true },
        ],
      }),
    );
    await expectNothingBack(ws);

    // No statement ran, so nothing was stored: the device-computes-overlap path is gone and the
    // server must not honour it even when an old build still speaks it.
    expect(vi.mocked(query).mock.calls.length).toBe(queriesAfterHello);
    // Not fanned out either — the partner sees nothing.
    expect(ws.readyState).toBe(WebSocket.OPEN);
  });

  it('ignores a garbage frame that is not even JSON', async () => {
    const ws = connect('good-u9');
    await nextMessage(ws);

    ws.send('}{not json');
    await expectNothingBack(ws);

    expect(ws.readyState).toBe(WebSocket.OPEN);
    expect(isOnline('u9')).toBe(true);
  });

  it('responds to a ping with a pong', async () => {
    // Protocol-level keepalive, answered by ws itself — the only thing a client may send.
    const ws = connect('good-u10');
    await nextMessage(ws);

    const pong = new Promise((res) => ws.once('pong', res));
    ws.ping();
    await expect(pong).resolves.toBeDefined();
  });
});
