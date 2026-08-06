import type { WebSocket } from 'ws';
import type { WsMessage } from './wire.js';

// A Set per uid, so one user with two devices gets both sockets.
// Ceiling: this registry is process-local, so the API is single-replica only. Scaling out needs
// Redis pub/sub (publish per-uid, every replica subscribes and writes to its own sockets).
const sockets = new Map<string, Set<WebSocket>>();

export function register(uid: string, ws: WebSocket): void {
  const set = sockets.get(uid) ?? new Set<WebSocket>();
  set.add(ws);
  sockets.set(uid, set);
}

export function unregister(uid: string, ws: WebSocket): void {
  const set = sockets.get(uid);
  if (!set) return;
  set.delete(ws);
  if (set.size === 0) sockets.delete(uid);
}

export function isOnline(uid: string): boolean {
  return (sockets.get(uid)?.size ?? 0) > 0;
}

/** false when uid has no live socket — that is what makes the caller fall back to FCM. */
export function sendTo(uid: string, msg: WsMessage): boolean {
  const set = sockets.get(uid);
  if (!set) return false;
  const data = JSON.stringify(msg);
  let sent = false;
  for (const ws of set) {
    if (ws.readyState !== 1) continue; // 1 === OPEN; literal keeps this a type-only ws import
    ws.send(data);
    sent = true;
  }
  return sent;
}
