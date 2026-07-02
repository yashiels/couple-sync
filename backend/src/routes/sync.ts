import type { FastifyPluginCallback, FastifyRequest } from 'fastify';
import type { WebSocket } from 'ws';
import { authenticate } from '../auth.js';
import { query } from '../db.js';

/**
 * In-memory connection registry.
 *
 *   sockets         : uid -> WebSocket           (a user's single live socket)
 *   coupleMembers   : coupleId -> Set<uid>       (who is paired with whom)
 *
 * V3 (block broadcast) and V5 (overlap fan-out + FCM fallback) read from these
 * maps. Couple membership is populated on connect from the users table and
 * kept fresh as sockets come and go; pairing/unpairing (V4) will mutate the
 * couples table and subsequent connects will reflect the new state.
 */
export const sockets = new Map<string, WebSocket>();
export const coupleMembers = new Map<string, Set<string>>();

/**
 * Send a JSON message to a single uid's live socket.
 * Returns false if the user has no open socket (so the caller can fall back
 * to FCM — see §8 of the spec).
 */
export function sendToUid(uid: string, msg: unknown): boolean {
  const socket = sockets.get(uid);
  if (!socket || socket.readyState !== socket.OPEN) return false;
  socket.send(JSON.stringify(msg));
  return true;
}

/**
 * Broadcast a message to every member of a couple. Optionally exclude the
 * originator (so a block:set from one partner does not echo back to them).
 */
export function sendToCouple(coupleId: string, msg: unknown, excludeUid?: string): void {
  const members = coupleMembers.get(coupleId);
  if (!members) return;
  for (const uid of members) {
    if (excludeUid && uid === excludeUid) continue;
    sendToUid(uid, msg);
  }
}

/**
 * Register the WS route: GET /sync upgraded.
 *
 * Auth: the token is read from `?token=` (browsers cannot set headers on the
 * WS upgrade) or the Authorization header (non-browser clients). On invalid
 * token the socket is closed with code 4001. On success the uid is stashed
 * on the socket and the registries are populated.
 */
export const syncRoutes: FastifyPluginCallback = (app) => {
  app.get('/sync', { websocket: true }, async (socket: WebSocket, req: FastifyRequest) => {
    let uid: string;
    try {
      const decoded = await authenticate(req);
      uid = decoded.uid;
    } catch (err) {
      socket.close(4001, err instanceof Error ? err.message : 'Unauthorized');
      return;
    }

    // Look up the user's couple so broadcasts can find their partner.
    let coupleId: string | null = null;
    try {
      const res = await query<{ couple_id: string | null }>(
        'SELECT couple_id FROM users WHERE uid = $1',
        [uid]
      );
      coupleId = res.rows[0]?.couple_id ?? null;
    } catch {
      // If the DB is unreachable we still let the socket connect — V3/V5
      // will surface DB errors per-message. Downgrade silently here.
    }

    (socket as WebSocket & { uid?: string }).uid = uid;
    sockets.set(uid, socket);
    if (coupleId) {
      let members = coupleMembers.get(coupleId);
      if (!members) {
        members = new Set();
        coupleMembers.set(coupleId, members);
      }
      members.add(uid);
    }

    socket.send(JSON.stringify({ t: 'hello', uid, coupleId }));

    socket.on('close', () => {
      sockets.delete(uid);
      if (coupleId) {
        const members = coupleMembers.get(coupleId);
        if (members) {
          members.delete(uid);
          if (members.size === 0) coupleMembers.delete(coupleId);
        }
      }
    });
  });
};

export default syncRoutes;
