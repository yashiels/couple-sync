import { query } from './db.js';
import type { UserRow } from './dto.js';
import { messaging } from './firebase.js';
import type { OverlapWindow } from './overlap/index.js';

// Only these two mean "this token is dead". Everything else (quota, transport, internal) is
// transient and must not cost the user their registration.
const HARD_INVALID = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

export async function pushOverlap(partner: UserRow, windows: OverlapWindow[]): Promise<void> {
  if (!partner.notifications_enabled) return;
  const tokens = partner.fcm_tokens ?? [];
  if (tokens.length === 0) return;

  const next = windows[0];
  const res = await messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: 'New free time together',
      body: next
        ? `${windows.length} window${windows.length === 1 ? '' : 's'} available`
        : 'Your shared free time changed',
    },
    data: { type: 'overlap', windows: JSON.stringify(windows.slice(0, 5)) },
  });

  const dead = res.responses
    .map((r, i) => (!r.success && HARD_INVALID.has(r.error?.code ?? '') ? tokens[i]! : null))
    .filter((t): t is string => t !== null);
  if (dead.length === 0) return;

  const keep = tokens.filter((t) => !dead.includes(t));
  await query('UPDATE users SET fcm_tokens = $2 WHERE uid = $1', [partner.uid, keep]);
}
