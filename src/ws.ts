import type { WsMessage } from '../backend/src/wire';
import { api, baseUrl } from './api';
import { getIdToken, hydrateFromServer } from './auth';
import { useStore } from './store';

/**
 * WS `/sync` client. Server -> client only: nothing is ever sent up this socket, so there is no
 * outbound queue and no offline buffer. `ws` answers protocol pings itself, which is the whole
 * keepalive contract.
 */

/** 1s doubling to a 30s ceiling. A phone off wifi must not hammer the backend for hours. */
const MAX_BACKOFF_MS = 30_000;

/**
 * React Native's WebSocket takes a third `options` argument carrying request headers; the DOM lib
 * type does not declare it. The token goes in a header (§4) rather than `?token=`, which the backend
 * also accepts but which would put a credential in every access log line.
 */
type WebSocketWithHeaders = new (
  url: string,
  protocols: string[] | null,
  options: { headers: Record<string, string> },
) => WebSocket;

let socket: WebSocket | null = null;
/** Set synchronously by connect(), because the token read is async and two calls would race. */
let opening = false;
let closedByUs = false;
let retryTimer: ReturnType<typeof setTimeout> | null = null;
let attempt = 0;
/** Opens in this app session. The second one onward is a reconnect, which owes an overlap refetch. */
let opens = 0;

/** Idempotent: a second call while a socket is open or opening is a no-op, never a second socket. */
export function connect(): void {
  closedByUs = false;
  if (socket || opening) return;
  opening = true;
  void openSocket();
}

export function disconnect(): void {
  closedByUs = true;
  if (retryTimer) {
    clearTimeout(retryTimer);
    retryTimer = null;
  }
  attempt = 0;
  opening = false;
  const ws = socket;
  socket = null;
  ws?.close(1000, 'client');
}

async function openSocket(): Promise<void> {
  let token: string | null = null;
  try {
    token = await getIdToken();
  } catch {
    token = null;
  }
  // Signed out, or the token read failed: the auth listener calls connect() again when a uid
  // arrives, so retrying here would spin against a state only sign-in can change.
  if (!token || closedByUs) {
    opening = false;
    return;
  }

  const Ctor = globalThis.WebSocket as unknown as WebSocketWithHeaders;
  const ws = new Ctor(`${baseUrl().replace(/^http/, 'ws')}/sync`, null, {
    headers: { Authorization: `Bearer ${token}` },
  });
  socket = ws;

  ws.onopen = () => {
    opening = false;
    attempt = 0;
    opens += 1;
  };
  ws.onmessage = (event: { data: unknown }) => {
    if (typeof event.data === 'string') handleMessage(event.data);
  };
  ws.onerror = () => {
    // `close` always follows, and that is where reconnection is decided. Nothing to do here.
  };
  ws.onclose = (event: { code?: number }) => {
    opening = false;
    if (socket === ws) socket = null;
    if (closedByUs) return;
    // 4001 is the server saying the token is invalid (sync.ts). Reconnecting with the same token
    // just repeats it; the auth listener reconnects when a fresh one exists.
    if (event.code === 4001) return;
    scheduleReconnect();
  };
}

function scheduleReconnect(): void {
  if (retryTimer) return;
  const delay = Math.min(MAX_BACKOFF_MS, 1000 * 2 ** attempt);
  attempt += 1;
  retryTimer = setTimeout(() => {
    retryTimer = null;
    if (closedByUs) return;
    opening = true;
    void openSocket();
  }, delay);
}

/** A failed refetch is not fatal: the next message, a tab focus, or pull-to-refresh redoes it. */
function fireAndForget(work: Promise<unknown>): void {
  void work.catch(() => undefined);
}

/**
 * A block:set carries a BlockRow with no `occurrences` — the server cannot know this client's
 * visible week — so it is a signal to refetch the range, never something to merge into state. When
 * the Calendar tab has never been opened there is no range and nothing rendering blocks: skip.
 */
async function refetchVisibleBlocks(coupleId: string): Promise<void> {
  const { visibleRange, setBlocks } = useStore.getState();
  if (!visibleRange) return;
  setBlocks(await api.listBlocks(coupleId, visibleRange.from, visibleRange.to));
}

async function refetchOverlap(coupleId: string): Promise<void> {
  const { windows, computed_at } = await api.latestOverlap(coupleId);
  useStore.getState().setWindows(windows, computed_at);
}

function handleMessage(raw: string): void {
  let msg: WsMessage;
  try {
    msg = JSON.parse(raw) as WsMessage;
  } catch {
    return;
  }
  const store = useStore.getState();

  switch (msg.t) {
    case 'hello': {
      // The server reads couple_id live per connect and it is authoritative — this is the safety net
      // for a `pairing` message that arrived while the socket was still connecting.
      const local = store.user?.couple_id ?? null;
      if (msg.couple_id === null) {
        store.resetCouple();
      } else if (msg.couple_id !== local) {
        fireAndForget(hydrateFromServer());
      } else if (opens > 1) {
        // Same couple, so no rehydrate: four requests on every reconnect is a refetch storm. The
        // overlap is the one thing that can have moved while the socket was down.
        fireAndForget(refetchOverlap(msg.couple_id));
      }
      break;
    }
    case 'block:set':
      fireAndForget(refetchVisibleBlocks(msg.block.couple_id));
      break;
    case 'blocks:changed':
      fireAndForget(refetchVisibleBlocks(msg.couple_id));
      break;
    case 'block:del':
      store.removeBlock(msg.id);
      break;
    case 'overlap':
      store.setWindows(msg.windows, msg.computed_at);
      break;
    case 'user:update':
      if (store.user && msg.user.uid === store.user.uid) {
        // fcm_tokens are stripped on the wire; keeping the local ones stops the own row losing them.
        store.setUser({ ...msg.user, fcm_tokens: store.user.fcm_tokens });
      } else {
        store.setPartner(msg.user);
      }
      break;
    case 'unpair':
      // No router call: resetCouple() nulls user.couple_id, the guard chain drops the (tabs) screens
      // from the navigator, and /pairing is the only branch left. Navigating as well would race it.
      store.resetCouple();
      break;
    case 'pairing':
      fireAndForget(hydrateFromServer());
      break;
    default:
      // Unknown `t` is dropped, per the forward-compat rule (§6).
      break;
  }
}
