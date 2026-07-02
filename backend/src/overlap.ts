import { query } from './db.js';
import { getMessaging } from './firebase.js';
import { sockets, sendToUid } from './routes/sync.js';

/**
 * V5 — overlap WS message handler + FCM push for the offline partner.
 *
 * Ported from `functions/src/onOverlapWrite.ts` + `functions/src/lib/overlap.ts`:
 *   - validateWindows         (pure; throws on malformed input)
 *   - formatOverlapBody       (pure; Intl-based, no luxon dep)
 *   - filterInvalidFcmTokens  (pure; prunes only hard-invalid codes)
 *
 * The device computes overlap and sends `{"t":"overlap",...}` over WS. The
 * server stores `overlaps_latest` (dedup via `inputHash`), forwards the
 * message to the partner's live socket, or — if the partner is offline —
 * sends an FCM push and prunes invalid tokens.
 */

export interface OverlapWindow {
  startUtc: number;
  endUtc: number;
  durationMinutes: number;
  score: number;
  reasonableBoth: boolean;
}

/** FCM error codes that mean the token is permanently dead → prune. */
export const INVALID_TOKEN_CODES = [
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
];

/**
 * Given a list of tokens and the per-message responses from
 * sendEachForMulticast, returns only the tokens that should be pruned
 * (those with a hard-invalid code). Transient errors (quota exceeded,
 * internal, etc.) are logged but NOT pruned.
 *
 * Ported verbatim from `functions/src/onOverlapWrite.ts`.
 */
export function filterInvalidFcmTokens(
  tokens: string[],
  responses: Array<{ success: boolean; error?: { code: string } }>,
  log: { warn: (msg: string) => void } = console
): string[] {
  const invalid: string[] = [];
  for (const [i, result] of responses.entries()) {
    if (!result.success) {
      const code = result.error?.code ?? '';
      if (INVALID_TOKEN_CODES.includes(code)) {
        invalid.push(tokens[i]);
      } else {
        log.warn(
          `[overlap] Transient FCM error for token[${i}], code=${code} — not pruning`
        );
      }
    }
  }
  return invalid;
}

/**
 * Format the FCM body for the next upcoming window.
 *   "<X>h free together on <EEE, MMM d>"
 *
 * Ported from `formatOverlapBody` but uses Intl (no luxon dependency).
 * `EEE, MMM d` in en-US UTC → e.g. "Mon, Jan 5".
 */
export function formatOverlapBody(window: OverlapWindow): string {
  const hours = (window.durationMinutes / 60).toFixed(1).replace(/\.0$/, '');
  const fmt = new Intl.DateTimeFormat('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });
  const when = fmt.format(new Date(window.startUtc));
  return `${hours}h free together on ${when}`;
}

/**
 * Validate a `windows[]` payload. Returns the typed windows or throws on
 * the first malformed entry. Ported from `validateWindows` in
 * `functions/src/onOverlapWrite.ts`.
 *
 * Rules:
 *   - startUtc / endUtc / durationMinutes are integers
 *   - score is finite
 *   - reasonableBoth is boolean
 *   - 0 < durationMinutes <= 1560
 *   - startUtc < endUtc
 *   - |endUtc - startUtc - durationMinutes*60000| <= 1000
 */
export function validateWindows(input: unknown[]): OverlapWindow[] {
  const out: OverlapWindow[] = [];
  for (const w of input as any[]) {
    if (
      typeof w.startUtc !== 'number' || !Number.isInteger(w.startUtc) ||
      typeof w.endUtc !== 'number' || !Number.isInteger(w.endUtc) ||
      typeof w.durationMinutes !== 'number' || !Number.isInteger(w.durationMinutes) ||
      typeof w.score !== 'number' || !Number.isFinite(w.score) ||
      typeof w.reasonableBoth !== 'boolean'
    ) {
      throw new Error('invalid window shape');
    }
    if (!(w.durationMinutes > 0 && w.durationMinutes <= 1560)) {
      throw new Error('durationMinutes out of bounds');
    }
    if (!(w.startUtc < w.endUtc)) {
      throw new Error('startUtc must be < endUtc');
    }
    if (Math.abs((w.endUtc - w.startUtc) - w.durationMinutes * 60_000) > 1000) {
      throw new Error('durationMinutes does not match start/end');
    }
    out.push(w);
  }
  return out;
}

// ─── WS message handler ─────────────────────────────────────────────────────

interface OverlapMessage {
  t: 'overlap';
  coupleId: string;
  windows: unknown[];
  inputHash: string;
  computedBy: string;
}

interface Notification {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Deps seam for `handleOverlapMessage`. Tests inject mocks; production wires
 * the real DB + Firebase + socket registry from the module's closures.
 */
export interface OverlapDeps {
  getStoredInputHash(coupleId: string): Promise<string | null>;
  upsertOverlap(
    coupleId: string,
    windows: OverlapWindow[],
    computedAt: number,
    inputHash: string,
    computedBy: string
  ): Promise<void>;
  getCouple(coupleId: string): Promise<{ userAUid: string; userBUid: string } | null>;
  getFcmTokens(uid: string): Promise<string[]>;
  sendFcm(tokens: string[], notification: Notification): Promise<string[]>;
  updateFcmTokens(uid: string, tokens: string[]): Promise<void>;
  isLive(uid: string): boolean;
  sendToUid(uid: string, msg: unknown): boolean;
  log: { warn: (msg: string) => void };
}

/**
 * Parse + validate an incoming `overlap` WS message. Returns the typed
 * message or `null` if the envelope itself is malformed (caller drops it).
 */
export function parseOverlapMessage(raw: unknown): OverlapMessage | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const m = raw as Record<string, unknown>;
  if (m.t !== 'overlap') return null;
  if (typeof m.coupleId !== 'string' || m.coupleId.length === 0) return null;
  if (!Array.isArray(m.windows)) return null;
  if (typeof m.inputHash !== 'string' || m.inputHash.length === 0) return null;
  if (typeof m.computedBy !== 'string' || m.computedBy.length === 0) return null;
  return {
    t: 'overlap',
    coupleId: m.coupleId,
    windows: m.windows,
    inputHash: m.inputHash,
    computedBy: m.computedBy,
  };
}

/**
 * Core handler: validate → dedup → broadcast/push.
 *
 * Returns:
 *   - 'ignored'   envelope or windows malformed; no state change
 *   - 'deduped'   inputHash matched stored; no-op
 *   - 'broadcast' partner live; overlap forwarded over WS (no FCM)
 *   - 'pushed'    partner offline; FCM sent (tokens pruned as needed)
 *   - 'no-push'   partner offline but has no FCM tokens
 */
export async function handleOverlapMessage(
  msg: OverlapMessage,
  deps: OverlapDeps
): Promise<'ignored' | 'deduped' | 'broadcast' | 'pushed' | 'no-push'> {
  // 1. Validate windows. Malformed → log + skip (no persist, no push).
  let valid: OverlapWindow[];
  try {
    valid = validateWindows(msg.windows);
  } catch (e) {
    deps.log.warn(`[overlap] rejected malformed windows: ${(e as Error).message}`);
    return 'ignored';
  }
  if (valid.length === 0) return 'ignored';

  // 2. Dedup via inputHash.
  const stored = await deps.getStoredInputHash(msg.coupleId);
  if (stored === msg.inputHash) return 'deduped';

  const computedAt = Date.now();
  await deps.upsertOverlap(
    msg.coupleId,
    valid,
    computedAt,
    msg.inputHash,
    msg.computedBy
  );

  // 3. Find the partner (the couple member who is NOT the writer).
  const couple = await deps.getCouple(msg.coupleId);
  if (!couple) return 'no-push'; // couple vanished — nothing to fan out
  const partnerUid =
    couple.userAUid === msg.computedBy
      ? couple.userBUid
      : couple.userAUid;

  if (!partnerUid) return 'no-push';

  // 4. Live socket → forward the overlap message; no FCM.
  if (deps.isLive(partnerUid)) {
    deps.sendToUid(partnerUid, {
      t: 'overlap',
      coupleId: msg.coupleId,
      windows: valid,
      inputHash: msg.inputHash,
      computedBy: msg.computedBy,
    });
    return 'broadcast';
  }

  // 5. Offline → FCM push. Build notification from the next-up window.
  const tokens = await deps.getFcmTokens(partnerUid);
  if (tokens.length === 0) return 'no-push';

  const nextWindow = valid.reduce((best, w) =>
    w.startUtc < best.startUtc ? w : best
  );
  const notification: Notification = {
    title: 'You have free time together!',
    body: formatOverlapBody(nextWindow),
    data: { coupleId: msg.coupleId },
  };

  const invalidTokens = await deps.sendFcm(tokens, notification);
  if (invalidTokens.length > 0) {
    const validTokens = tokens.filter((t) => !invalidTokens.includes(t));
    await deps.updateFcmTokens(partnerUid, validTokens);
  }
  return 'pushed';
}

// ─── Production deps wiring ─────────────────────────────────────────────────

/**
 * Build the production OverlapDeps: Postgres for dedup/couple/tokens,
 * Firebase Admin for FCM, and the in-memory socket registry for liveness.
 */
export function makeOverlapDeps(): OverlapDeps {
  return {
    async getStoredInputHash(coupleId) {
      const res = await query<{ input_hash: string }>(
        'SELECT input_hash FROM overlaps_latest WHERE couple_id = $1',
        [coupleId]
      );
      return res.rows[0]?.input_hash ?? null;
    },

    async upsertOverlap(coupleId, windows, computedAt, inputHash, computedBy) {
      await query(
        `INSERT INTO overlaps_latest (couple_id, windows, computed_at, input_hash, computed_by)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (couple_id) DO UPDATE SET
           windows = EXCLUDED.windows,
           computed_at = EXCLUDED.computed_at,
           input_hash = EXCLUDED.input_hash,
           computed_by = EXCLUDED.computed_by`,
        [coupleId, JSON.stringify(windows), computedAt, inputHash, computedBy]
      );
    },

    async getCouple(coupleId) {
      const res = await query<{ user_a_uid: string; user_b_uid: string }>(
        'SELECT user_a_uid, user_b_uid FROM couples WHERE id = $1 AND status = $2',
        [coupleId, 'active']
      );
      const r = res.rows[0];
      if (!r) return null;
      return { userAUid: r.user_a_uid, userBUid: r.user_b_uid };
    },

    async getFcmTokens(uid) {
      const res = await query<{ fcm_tokens: string[] }>(
        'SELECT fcm_tokens FROM users WHERE uid = $1',
        [uid]
      );
      return res.rows[0]?.fcm_tokens ?? [];
    },

    async sendFcm(tokens, notification) {
      const messaging = getMessaging();
      const response = await messaging.sendEachForMulticast({
        tokens,
        notification: { title: notification.title, body: notification.body },
        data: notification.data,
      });
      return filterInvalidFcmTokens(tokens, response.responses);
    },

    async updateFcmTokens(uid, tokens) {
      await query(
        'UPDATE users SET fcm_tokens = $1 WHERE uid = $2',
        [tokens, uid]
      );
    },

    isLive(uid) {
      const s = sockets.get(uid);
      return !!s && s.readyState === s.OPEN;
    },

    sendToUid,

    log: console,
  };
}
