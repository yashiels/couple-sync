import type { FastifyInstance } from 'fastify';
import type { IncomingMessage } from 'node:http';
import { WebSocketServer, type WebSocket } from 'ws';
import { uidFromRequest } from './auth.js';
import { query } from './db.js';
import { register, unregister } from './sockets.js';
import type { WsMessage } from './wire.js';

/**
 * WS `/sync`. Server -> client only (§6).
 *
 * There is deliberately no `message` listener: the device neither computes nor publishes overlap
 * windows, so every inbound frame is discarded by construction — including an `overlap` publish from
 * an old build that still thinks it owns the computation. Unknown `t` values are dropped for the same
 * reason, which is exactly the forward-compat rule the spec asks for. `ws` answers protocol-level
 * pings itself, and that is the whole keepalive contract.
 */
export function attachSyncServer(app: FastifyInstance): void {
  const wss = new WebSocketServer({ noServer: true });

  app.server.on('upgrade', (req, socket, head) => {
    if (new URL(req.url ?? '/', 'http://localhost').pathname !== '/sync') {
      socket.destroy();
      return;
    }
    // Handshake first, authenticate second, so a rejection can carry close code 4001. A client that
    // gets a bare HTTP 401 on an upgrade cannot tell auth failure from a dropped network and retries
    // forever.
    wss.handleUpgrade(req, socket, head, (ws) => void onConnection(ws, req));
  });
}

async function onConnection(ws: WebSocket, req: IncomingMessage): Promise<void> {
  let uid: string;
  try {
    // Authorization header first, `?token=` as the fallback — see auth.ts.
    uid = await uidFromRequest(req);
  } catch {
    ws.close(4001, 'unauthorized');
    return;
  }

  let coupleId: string | null;
  try {
    const rows = await query<{ couple_id: string | null }>(
      'SELECT couple_id FROM users WHERE uid = $1',
      [uid],
    );
    coupleId = rows[0]?.couple_id ?? null;
  } catch {
    // Not 4001: a database blip is not an auth failure, and saying otherwise sends the app back
    // through sign-in.
    ws.close(1011, 'internal');
    return;
  }

  ws.on('close', () => unregister(uid, ws));
  ws.on('error', () => unregister(uid, ws));
  // Authentication is a round trip, so the client may already be gone. Registering a dead socket
  // would make isOnline() lie and silently suppress this user's pushes.
  if (ws.readyState !== ws.OPEN) return;

  register(uid, ws);
  // couple_id is read live, per connect, and the app treats it as authoritative: this is how a
  // device that missed the `pairing` broadcast discovers it is paired. Never a cached value.
  const hello: WsMessage = { t: 'hello', uid, couple_id: coupleId };
  ws.send(JSON.stringify(hello));
}
