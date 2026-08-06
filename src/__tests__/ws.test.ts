import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { BlockRow, BlockWithOccurrences, UserRow, WsMessage } from '../../backend/src/wire';

const mocks = vi.hoisted(() => ({
  getIdToken: vi.fn<() => Promise<string | null>>(),
  hydrateFromServer: vi.fn<() => Promise<string | null>>(),
  listBlocks: vi.fn<(coupleId: string, from: number, to: number) => Promise<BlockWithOccurrences[]>>(),
  latestOverlap: vi.fn<(coupleId: string) => Promise<{ windows: []; computed_at: number }>>(),
}));

vi.mock('../auth', () => ({
  getIdToken: mocks.getIdToken,
  hydrateFromServer: mocks.hydrateFromServer,
}));
vi.mock('../api', () => ({
  api: { listBlocks: mocks.listBlocks, latestOverlap: mocks.latestOverlap },
  baseUrl: () => 'http://api.test',
}));

/** A WebSocket the test drives: nothing happens until open()/send()/serverClose() is called. */
class FakeSocket {
  static instances: FakeSocket[] = [];
  readyState = 0;
  onopen: ((e: unknown) => void) | null = null;
  onmessage: ((e: { data: unknown }) => void) | null = null;
  onclose: ((e: { code?: number }) => void) | null = null;
  onerror: ((e: unknown) => void) | null = null;
  closedWith: number | undefined;

  constructor(
    readonly url: string,
    readonly protocols: unknown,
    readonly options: { headers: Record<string, string> },
  ) {
    FakeSocket.instances.push(this);
  }

  /** The client closing. */
  close(code?: number): void {
    this.readyState = 3;
    this.closedWith = code;
    this.onclose?.({ code });
  }

  open(): void {
    this.readyState = 1;
    this.onopen?.({});
  }

  /** Anything other than an explicit client close: dropped wifi is 1006. */
  serverClose(code = 1006): void {
    this.readyState = 3;
    this.onclose?.({ code });
  }

  deliver(msg: WsMessage | Record<string, unknown>): void {
    this.onmessage?.({ data: JSON.stringify(msg) });
  }
}

function userRow(overrides: Partial<UserRow> = {}): UserRow {
  return {
    uid: 'u1',
    email: 'a@example.com',
    display_name: 'A',
    photo_url: null,
    timezone: 'Europe/Berlin',
    couple_id: 'c1',
    show_late_night_windows: false,
    notifications_enabled: true,
    fcm_tokens: ['device-1'],
    created_at: 0,
    ...overrides,
  };
}

/** What every path except GET /users/me sends: the row with fcm_tokens stripped. */
function publicUser(overrides: Partial<UserRow> = {}): Omit<UserRow, 'fcm_tokens'> {
  const { fcm_tokens: _stripped, ...rest } = userRow(overrides);
  return rest;
}

function blockRow(overrides: Partial<BlockRow> = {}): BlockRow {
  return {
    id: 'b1',
    couple_id: 'c1',
    user_id: 'u1',
    title: 'Gym',
    type: 'busy',
    category: null,
    start_utc: 1,
    end_utc: 2,
    timezone: 'Europe/Berlin',
    recurrence_rule: null,
    source: 'manual',
    visibility: 'bothPartners',
    created_at: 0,
    ...overrides,
  };
}

/** Microtasks only — safe under fake timers, unlike setImmediate. */
async function flush(): Promise<void> {
  for (let i = 0; i < 5; i++) await Promise.resolve();
}

type Ws = typeof import('../ws');
type Store = typeof import('../store');
type StoreState = ReturnType<(typeof import('../store'))['useStore']['getState']>;

async function setup(): Promise<Ws & Store> {
  vi.resetModules();
  FakeSocket.instances = [];
  vi.stubGlobal('WebSocket', FakeSocket);
  const ws = await import('../ws');
  const store = await import('../store');
  return { ...ws, ...store };
}

function last(): FakeSocket {
  const socket = FakeSocket.instances.at(-1);
  if (!socket) throw new Error('no socket was opened');
  return socket;
}

beforeEach(() => {
  mocks.getIdToken.mockReset().mockResolvedValue('id-token-1');
  mocks.hydrateFromServer.mockReset().mockResolvedValue('c1');
  mocks.listBlocks.mockReset().mockResolvedValue([]);
  mocks.latestOverlap.mockReset().mockResolvedValue({ windows: [], computed_at: 7 });
});

afterEach(() => {
  vi.useRealTimers();
});

describe('connection lifecycle', () => {
  it('connects with the id token in the Authorization header', async () => {
    const { connect } = await setup();
    connect();
    await flush();
    expect(last().url).toBe('ws://api.test/sync');
    expect(last().options.headers).toEqual({ Authorization: 'Bearer id-token-1' });
  });

  it('does not open a second socket when connect is called twice', async () => {
    const { connect } = await setup();
    connect();
    connect(); // synchronously, while the first token read is still in flight
    await flush();
    connect(); // and again once it is open
    last().open();
    await flush();
    expect(FakeSocket.instances).toHaveLength(1);
  });

  it('does not connect when there is no session', async () => {
    mocks.getIdToken.mockResolvedValue(null);
    const { connect } = await setup();
    connect();
    await flush();
    expect(FakeSocket.instances).toHaveLength(0);
  });

  it('reconnects with exponential backoff, capped, after an unexpected close', async () => {
    vi.useFakeTimers();
    const { connect } = await setup();
    connect();
    await flush();
    last().open();

    last().serverClose();
    await vi.advanceTimersByTimeAsync(999);
    expect(FakeSocket.instances).toHaveLength(1); // nothing yet
    await vi.advanceTimersByTimeAsync(1);
    expect(FakeSocket.instances).toHaveLength(2); // 1s

    last().serverClose();
    await vi.advanceTimersByTimeAsync(1999);
    expect(FakeSocket.instances).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(1);
    expect(FakeSocket.instances).toHaveLength(3); // 2s

    last().serverClose();
    await vi.advanceTimersByTimeAsync(4000);
    expect(FakeSocket.instances).toHaveLength(4); // 4s

    // Straight to the ceiling: 8s, 16s, then 30s and 30s again, never 32s or 64s.
    for (const delay of [8000, 16_000, 30_000, 30_000]) {
      const before = FakeSocket.instances.length;
      last().serverClose();
      await vi.advanceTimersByTimeAsync(delay - 1);
      expect(FakeSocket.instances).toHaveLength(before);
      await vi.advanceTimersByTimeAsync(1);
      expect(FakeSocket.instances).toHaveLength(before + 1);
    }
  });

  it('resets the backoff once a socket actually opens', async () => {
    vi.useFakeTimers();
    const { connect } = await setup();
    connect();
    await flush();
    last().open();
    last().serverClose();
    await vi.advanceTimersByTimeAsync(1000);
    last().serverClose(); // never opened: the delay would be 2s
    await vi.advanceTimersByTimeAsync(2000);
    last().open(); // this one connects, so the next failure starts over at 1s
    last().serverClose();
    await vi.advanceTimersByTimeAsync(1000);
    expect(FakeSocket.instances).toHaveLength(4);
  });

  it('does not reconnect after an explicit disconnect', async () => {
    vi.useFakeTimers();
    const { connect, disconnect } = await setup();
    connect();
    await flush();
    last().open();
    disconnect();
    expect(last().closedWith).toBe(1000);
    await vi.advanceTimersByTimeAsync(120_000);
    expect(FakeSocket.instances).toHaveLength(1);
  });

  it('does not reconnect after a 4001 unauthorized close', async () => {
    vi.useFakeTimers();
    const { connect } = await setup();
    connect();
    await flush();
    last().open();
    last().serverClose(4001); // the token is bad; retrying with it just repeats the rejection
    await vi.advanceTimersByTimeAsync(120_000);
    expect(FakeSocket.instances).toHaveLength(1);
  });
});

describe('message handling', () => {
  async function connected(state: Partial<StoreState> = {}) {
    const mod = await setup();
    mod.useStore.setState({ user: userRow(), ...state });
    mod.connect();
    await flush();
    last().open();
    return mod;
  }

  it('refetches the visible range via listBlocks on block:set, and calls setBlocks', async () => {
    const fetched = [{ ...blockRow(), occurrences: [{ start_utc: 1, end_utc: 2 }] }];
    mocks.listBlocks.mockResolvedValue(fetched);
    const { useStore } = await connected({ visibleRange: { from: 10, to: 20 } });

    last().deliver({ t: 'block:set', block: blockRow() });
    await flush();

    expect(mocks.listBlocks).toHaveBeenCalledWith('c1', 10, 20);
    expect(useStore.getState().blocks).toEqual(fetched);
  });

  it('does NOT refetch on block:set when visibleRange is null', async () => {
    await connected();
    last().deliver({ t: 'block:set', block: blockRow() });
    await flush();
    expect(mocks.listBlocks).not.toHaveBeenCalled();
  });

  it('refetches exactly once on blocks:changed', async () => {
    await connected({ visibleRange: { from: 10, to: 20 } });
    last().deliver({ t: 'blocks:changed', couple_id: 'c1' });
    await flush();
    expect(mocks.listBlocks).toHaveBeenCalledTimes(1);
    expect(mocks.listBlocks).toHaveBeenCalledWith('c1', 10, 20);
  });

  it('does NOT refetch on blocks:changed when visibleRange is null', async () => {
    await connected();
    last().deliver({ t: 'blocks:changed', couple_id: 'c1' });
    await flush();
    expect(mocks.listBlocks).not.toHaveBeenCalled();
  });

  it('applies block:del to the store via removeBlock', async () => {
    const { useStore } = await connected({
      blocks: [
        { ...blockRow({ id: 'b1' }), occurrences: [] },
        { ...blockRow({ id: 'b2' }), occurrences: [] },
      ],
    });
    last().deliver({ t: 'block:del', id: 'b1' });
    expect(useStore.getState().blocks.map((b) => b.id)).toEqual(['b2']);
  });

  it('applies overlap to the store via setWindows', async () => {
    const { useStore } = await connected();
    const window = {
      startUtc: 100,
      endUtc: 200,
      durationMinutes: 30,
      score: 1,
      reasonableBoth: true,
    };
    last().deliver({ t: 'overlap', couple_id: 'c1', windows: [window], computed_at: 99 });
    expect(useStore.getState().windows).toEqual([window]);
    expect(useStore.getState().computedAt).toBe(99);
  });

  it("applies a partner's user:update to partner, not user", async () => {
    const { useStore } = await connected();
    last().deliver({ t: 'user:update', user: publicUser({ uid: 'u2', display_name: 'B' }) });
    expect(useStore.getState().partner?.uid).toBe('u2');
    expect(useStore.getState().user?.uid).toBe('u1');
  });

  it('applies an own user:update to user, keeping the local fcm_tokens', async () => {
    const { useStore } = await connected();
    // fcm_tokens are stripped on the wire, so the handler must keep the local ones.
    last().deliver({ t: 'user:update', user: publicUser({ display_name: 'Renamed' }) });
    expect(useStore.getState().user?.display_name).toBe('Renamed');
    expect(useStore.getState().user?.fcm_tokens).toEqual(['device-1']);
    expect(useStore.getState().partner).toBeNull();
  });

  it('drops couple state on unpair, which is what sends the guard chain to /pairing', async () => {
    const { useStore } = await connected({
      couple: {
        id: 'c1',
        user_a_uid: 'u1',
        user_b_uid: 'u2',
        status: 'active',
        paired_at: 0,
        created_at: 0,
      },
      partner: userRow({ uid: 'u2' }),
    });
    last().deliver({ t: 'unpair', couple_id: 'c1' });
    expect(useStore.getState().couple).toBeNull();
    expect(useStore.getState().partner).toBeNull();
    expect(useStore.getState().user?.couple_id).toBeNull();
  });

  it('refetches user and couple on pairing', async () => {
    await connected({ user: userRow({ couple_id: null }) });
    last().deliver({ t: 'pairing', couple_id: 'c9', partner_uid: 'u2' });
    await flush();
    expect(mocks.hydrateFromServer).toHaveBeenCalledTimes(1);
  });

  it('ignores a message with an unknown t', async () => {
    const { useStore } = await connected({ visibleRange: { from: 10, to: 20 } });
    const before = useStore.getState();
    last().deliver({ t: 'something:new', payload: 1 });
    await flush();
    expect(mocks.hydrateFromServer).not.toHaveBeenCalled();
    expect(mocks.listBlocks).not.toHaveBeenCalled();
    expect(useStore.getState()).toEqual(before);
  });

  it('ignores an unparseable frame', async () => {
    await connected();
    expect(() => last().onmessage?.({ data: 'not json' })).not.toThrow();
  });
});

describe('hello reconciliation', () => {
  it('calls hydrateFromServer on hello when the server couple_id differs from local', async () => {
    const mod = await setup();
    // The cold-start case: the socket beat hydration, so local couple_id is still null.
    mod.useStore.setState({ user: userRow({ couple_id: null }) });
    mod.connect();
    await flush();
    last().open();
    last().deliver({ t: 'hello', uid: 'u1', couple_id: 'c1' });
    await flush();
    expect(mocks.hydrateFromServer).toHaveBeenCalledTimes(1);
  });

  it('does NOT rehydrate on hello when the server couple_id matches local', async () => {
    const mod = await setup();
    mod.useStore.setState({ user: userRow({ couple_id: 'c1' }) });
    mod.connect();
    await flush();
    last().open();
    last().deliver({ t: 'hello', uid: 'u1', couple_id: 'c1' });
    await flush();
    expect(mocks.hydrateFromServer).not.toHaveBeenCalled();
    expect(mocks.latestOverlap).not.toHaveBeenCalled(); // first connect: hydration just ran
  });

  it('resetCouple()s on hello when the server reports couple_id null', async () => {
    const mod = await setup();
    mod.useStore.setState({
      user: userRow({ couple_id: 'c1' }),
      couple: {
        id: 'c1',
        user_a_uid: 'u1',
        user_b_uid: 'u2',
        status: 'active',
        paired_at: 0,
        created_at: 0,
      },
    });
    mod.connect();
    await flush();
    last().open();
    last().deliver({ t: 'hello', uid: 'u1', couple_id: null });
    await flush();
    expect(mod.useStore.getState().couple).toBeNull();
    expect(mod.useStore.getState().user?.couple_id).toBeNull();
    expect(mocks.hydrateFromServer).not.toHaveBeenCalled();
  });

  it('refetches the latest overlap after a reconnect', async () => {
    vi.useFakeTimers();
    const mod = await setup();
    mod.useStore.setState({ user: userRow({ couple_id: 'c1' }) });
    mod.connect();
    await flush();
    last().open();
    last().deliver({ t: 'hello', uid: 'u1', couple_id: 'c1' });
    await flush();
    expect(mocks.latestOverlap).not.toHaveBeenCalled();

    last().serverClose();
    await vi.advanceTimersByTimeAsync(1000);
    last().open();
    last().deliver({ t: 'hello', uid: 'u1', couple_id: 'c1' });
    await flush();

    expect(mocks.latestOverlap).toHaveBeenCalledWith('c1');
    expect(mocks.hydrateFromServer).not.toHaveBeenCalled(); // an overlap refetch, not a storm
    expect(mod.useStore.getState().computedAt).toBe(7);
  });
});
