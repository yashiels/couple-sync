import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import type { WebSocket } from 'ws';
import { authenticate } from '../auth.js';
import { query } from '../db.js';
import { assertMember } from '../couples.js';
import {
  parseOverlapMessage,
  handleOverlapMessage,
  makeOverlapDeps,
  type OverlapMessage,
} from '../overlap.js';

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
 * V8 — authorize an incoming `overlap` WS message against the socket's authed
 * uid. Returns the parsed message only if:
 *   - the envelope parses (parseOverlapMessage ok), AND
 *   - `msg.computedBy === socketUid` (prevents a client forging another uid as
 *     the writer — which would otherwise let it overwrite the couple's
 *     overlaps_latest row + push FCM to the partner under a fake sender).
 *
 * On mismatch a warning is logged and `null` is returned so the caller skips
 * persist/push. Pure + exported so the security boundary is unit-tested
 * directly (see __tests__/sync.test.ts).
 */
export function authorizeOverlapMessage(
  raw: unknown,
  socketUid: string
): { msg: OverlapMessage } | null {
  const msg = parseOverlapMessage(raw);
  if (!msg) return null;
  if (msg.computedBy !== socketUid) {
    // eslint-disable-next-line no-console
    console.warn(
      `[sync] overlap rejected: computedBy ${msg.computedBy} !== socket uid ${socketUid} (coupleId=${msg.coupleId})`
    );
    return null;
  }
  return { msg };
}

/**
 * V9 — couple-membership gate for incoming `overlap` WS messages.
 *
 * `authorizeOverlapMessage` only checks `computedBy === socketUid`; it does
 * NOT verify the socket's uid is a member of `msg.coupleId`. This thin async
 * wrapper calls `assertMember(coupleId, uid)` (which queries the `couples`
 * table and throws 403 on non-membership) and converts any throw into a
 * logged rejection + `false`, so a single forbidden message never crashes
 * the server. Returns `true` only when the caller is a verified member of
 * the targeted couple.
 *
 * Exported so the WS membership boundary is unit-tested directly.
 */
export async function membershipCheck(
  coupleId: string,
  uid: string
): Promise<boolean> {
  try {
    await assertMember(coupleId, uid);
    return true;
  } catch (err) {
    // eslint-disable-next-line no-console
    console.warn(
      `[sync] overlap rejected: uid ${uid} is not a member of couple ${coupleId}` +
        (err instanceof Error ? ` (${err.message})` : '')
    );
    return false;
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
export const syncRoutes: FastifyPluginAsync = async (app) => {
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

    /**
     * V5 — incoming message dispatch. The device sends tagged JSON
     * messages; currently only `overlap` is handled here (block set/del
     * arrive over REST in V3). Malformed JSON or unknown `t` are dropped
     * silently; malformed overlap payloads are logged inside the handler.
     */
    socket.on('message', (data: unknown, isBinary: boolean) => {
      if (isBinary) return; // not used — all sync messages are JSON text
      let raw: unknown;
      try {
        let text: string;
        if (typeof data === 'string') {
          text = data;
        } else if (Buffer.isBuffer(data)) {
          text = data.toString();
        } else if (data instanceof ArrayBuffer) {
          text = Buffer.from(data).toString();
        } else if (Array.isArray(data)) {
          text = Buffer.concat(data as readonly Uint8Array[]).toString();
        } else {
          text = String(data);
        }
        raw = JSON.parse(text);
      } catch {
        return; // drop malformed JSON
      }
      if (typeof raw !== 'object' || raw === null) return;
      const tagged = raw as { t?: string };
      if (tagged.t === 'overlap') {
        const accepted = authorizeOverlapMessage(raw, uid);
        if (!accepted) return;
        const { msg } = accepted;
        // Membership check: the socket uid must belong to msg.coupleId.
        // authorizeOverlapMessage only asserts computedBy === socketUid; it
        // does NOT verify the socket is a member of the targeted couple. Without
        // this gate, any authed user who knows a couple UUID could overwrite
        // the victim's overlaps_latest + trigger FCM to a real member.
        // assertMember throws on non-membership (and on missing couples, to
        // avoid leaking existence). In the WS path we cannot surface a 403 —
        // log + skip the message instead of crashing the server.
        membershipCheck(msg.coupleId, uid)
          .then((ok) => {
            if (!ok) return;
            // Fire-and-forget; errors are logged inside the handler, not thrown
            // back at the socket (a single bad overlap must not kill the connection).
            handleOverlapMessage(msg, makeOverlapDeps()).catch((err) => {
              // eslint-disable-next-line no-console
              console.error('[sync] overlap handler failed:', err);
            });
          })
          .catch((err) => {
            // eslint-disable-next-line no-console
            console.error('[sync] overlap membership check failed:', err);
          });
      }
      // Unknown `t` → ignore (forward-compat with future message types).
    });

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
