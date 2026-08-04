import { DateTime } from 'luxon';
import { query } from './db.js';
import { sendEach } from './firebase.js';
import type { OverlapWindow } from './wire.js';

// Only these two mean "this token is dead". Everything else (quota, transport, internal) is
// transient and must not cost the user their registration.
const HARD_INVALID = new Set([
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
]);

/**
 * Sends to every token for uid and prunes only hard-invalid ones. No-op when tokens is empty.
 * async throughout, so a failure rejects rather than throwing synchronously and the caller can
 * Promise.allSettled a fan-out. Tokens are passed in rather than re-read: the caller already loaded
 * the row inside its transaction, and a second query after commit could see a different value.
 */
export async function pushOverlapChanged(
  uid: string,
  tokens: string[],
  windows: OverlapWindow[],
  timezone: string,
): Promise<void> {
  if (tokens.length === 0) return;

  const results = await sendEach(tokens, {
    notification: { title: 'New free time together', body: body(windows, timezone) },
    // Only a routing hint. The payload has no other channel, which is what keeps a block title —
    // or a category, or the windows themselves — out of a notification the OS may render on a
    // locked screen. The app fetches the windows over WS or REST once it is opened.
    data: { type: 'overlap' },
  });

  const dead = results
    .filter((r) => r.errorCode !== null && HARD_INVALID.has(r.errorCode))
    .map((r) => r.token);
  if (dead.length === 0) return;

  // Subtract in SQL rather than writing back a computed array: a token registered between the read
  // and this write survives.
  await query(
    `UPDATE users
        SET fcm_tokens = ARRAY(SELECT t FROM unnest(fcm_tokens) AS t WHERE t <> ALL($2::text[]))
      WHERE uid = $1`,
    [uid, dead],
  );
}

function body(windows: OverlapWindow[], timezone: string): string {
  if (windows.length === 0) return 'Your shared free time changed';
  // NOT windows[0]: the engine sorts by score descending (overlap/score.ts compareWindows), so the
  // first element is the best window, not the soonest one. "next" has to mean earliest start.
  const next = windows.reduce((a, w) => (w.startUtc < a.startUtc ? w : a));
  // The recipient's own zone — the same window reads as a different day for each partner.
  const when = DateTime.fromMillis(next.startUtc, { zone: timezone }).toFormat('ccc d MMM, HH:mm');
  return `${windows.length} window${windows.length === 1 ? '' : 's'} — next ${when}`;
}
