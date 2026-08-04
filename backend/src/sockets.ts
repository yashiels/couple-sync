import type { WebSocket } from 'ws';

// Ceiling: this uid → socket map is process-local, so the API is single-replica only. Scaling out
// needs Redis pub/sub (publish per-uid, every replica subscribes and writes to its own sockets).
const sockets = new Map<string, Set<WebSocket>>();

export function addSocket(uid: string, ws: WebSocket): void {
  const set = sockets.get(uid) ?? new Set<WebSocket>();
  set.add(ws);
  sockets.set(uid, set);
}

export function removeSocket(uid: string, ws: WebSocket): void {
  const set = sockets.get(uid);
  if (!set) return;
  set.delete(ws);
  if (set.size === 0) sockets.delete(uid);
}

export function isOnline(uid: string): boolean {
  return (sockets.get(uid)?.size ?? 0) > 0;
}

export function sendTo(uid: string, msg: unknown): void {
  const set = sockets.get(uid);
  if (!set) return;
  const data = JSON.stringify(msg);
  for (const ws of set) {
    if (ws.readyState === 1) ws.send(data);
  }
}
