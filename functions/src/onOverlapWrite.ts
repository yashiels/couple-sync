import { DateTime } from 'luxon';
import * as admin from 'firebase-admin';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { CoupleDoc, OverlapResult, OverlapWindow } from './lib/types';

// ─── Module-scope constants ───────────────────────────────────────────────────

export const INVALID_TOKEN_CODES = [
  'messaging/invalid-registration-token',
  'messaging/registration-token-not-registered',
];

/**
 * Given a list of tokens and the per-message responses from sendEachForMulticast,
 * returns only the tokens that should be pruned (i.e. those with a hard-invalid code).
 * Transient errors (quota exceeded, internal, etc.) are logged but NOT pruned.
 */
export function filterInvalidFcmTokens(
  tokens: string[],
  responses: Array<{ success: boolean; error?: { code: string } }>
): string[] {
  const invalid: string[] = [];
  for (const [i, result] of responses.entries()) {
    if (!result.success) {
      const code = result.error?.code ?? '';
      if (INVALID_TOKEN_CODES.includes(code)) {
        invalid.push(tokens[i]);
      } else {
        logger.warn(
          `[onOverlapWrite] Transient FCM error for token[${i}], code=${code} — not pruning`
        );
      }
    }
  }
  return invalid;
}

// ─── Testable business logic ──────────────────────────────────────────────────

interface Notification {
  title: string;
  body: string;
  data?: Record<string, string>;
}

interface OverlapWriteDeps {
  getCouple(id: string): Promise<CoupleDoc | null>;
  getFcmTokens(uid: string): Promise<string[]>;
  sendNotification(tokens: string[], notification: Notification): Promise<string[]>;
  updateFcmTokens(uid: string, tokens: string[]): Promise<void>;
}

function formatOverlapBody(window: OverlapWindow): string {
  const dt = DateTime.fromMillis(window.startUtc, { zone: 'UTC' });
  const hours = (window.durationMinutes / 60).toFixed(1).replace(/\.0$/, '');
  return `${hours}h free together on ${dt.toFormat('EEE, MMM d')}`;
}

export function validateWindows(input: unknown[]): OverlapWindow[] {
  const out: OverlapWindow[] = [];
  for (const w of input as any[]) {
    if (typeof w.startUtc !== 'number' || !Number.isInteger(w.startUtc) ||
        typeof w.endUtc !== 'number' || !Number.isInteger(w.endUtc) ||
        typeof w.durationMinutes !== 'number' || !Number.isInteger(w.durationMinutes) ||
        typeof w.score !== 'number' || !Number.isFinite(w.score) ||
        typeof w.reasonableBoth !== 'boolean') {
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

export async function handleOnOverlapWrite(
  coupleId: string,
  windows: OverlapWindow[],
  deps: OverlapWriteDeps,
  computedBy?: string,
): Promise<void> {
  let valid: OverlapWindow[];
  try {
    valid = validateWindows(windows);
  } catch (e) {
    logger.warn(`[onOverlapWrite] rejected malformed windows: ${(e as Error).message}`);
    return;
  }
  if (valid.length === 0) return;

  const couple = await deps.getCouple(coupleId);
  if (!couple) return;

  const targets = [couple.userAUid, couple.userBUid].filter((uid) => uid !== computedBy);
  const tokensPerUid = await Promise.all(
    targets.map(async (uid) => [uid, await deps.getFcmTokens(uid)] as const),
  );

  const nextWindow = valid.reduce((best, w) => (w.startUtc < best.startUtc ? w : best));
  const notification: Notification = {
    title: 'You have free time together!',
    body: formatOverlapBody(nextWindow),
    data: { coupleId },
  };

  for (const [uid, tokens] of tokensPerUid) {
    if (tokens.length === 0) continue;
    const invalidTokens = await deps.sendNotification(tokens, notification);
    if (invalidTokens.length > 0) {
      const validTokens = tokens.filter((t) => !invalidTokens.includes(t));
      await deps.updateFcmTokens(uid, validTokens);
    }
  }
}

// ─── Cloud Function export ────────────────────────────────────────────────────

export const onOverlapWrite = onDocumentWritten(
  { document: 'overlaps/{coupleId}/windows/latest', region: 'us-central1' },
  async (event) => {
    const db = admin.firestore();
    const messaging = admin.messaging();
    const { coupleId } = event.params;
    const after = event.data?.after;
    const overlapResult = after?.data() as (OverlapResult & { computedBy?: string }) | undefined;
    const windows = overlapResult?.windows ?? [];
    const computedBy = overlapResult?.computedBy;

    await handleOnOverlapWrite(coupleId, windows, {
      getCouple: async (id) => {
        const snap = await db.collection('couples').doc(id).get();
        return snap.exists ? (snap.data() as CoupleDoc) : null;
      },
      getFcmTokens: async (uid) => {
        const snap = await db.collection('users').doc(uid).get();
        return snap.exists ? ((snap.data() as { fcmTokens?: string[] }).fcmTokens ?? []) : [];
      },
      sendNotification: async (tokens, notif) => {
        const response = await messaging.sendEachForMulticast({
          tokens,
          notification: { title: notif.title, body: notif.body },
          data: notif.data,
        });
        return filterInvalidFcmTokens(tokens, response.responses);
      },
      updateFcmTokens: async (uid, validTokens) => {
        await db.collection('users').doc(uid).update({ fcmTokens: validTokens });
      },
    }, computedBy);
  }
);
