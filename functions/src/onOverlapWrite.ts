import { DateTime } from 'luxon';
import * as admin from 'firebase-admin';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { CoupleDoc, OverlapResult, OverlapWindow } from './lib/types';

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

export async function handleOnOverlapWrite(
  coupleId: string,
  windows: OverlapWindow[],
  deps: OverlapWriteDeps
): Promise<void> {
  if (windows.length === 0) return;

  const couple = await deps.getCouple(coupleId);
  if (!couple) return;

  const [tokensA, tokensB] = await Promise.all([
    deps.getFcmTokens(couple.userAUid),
    deps.getFcmTokens(couple.userBUid),
  ]);

  // Pick next upcoming window for the notification body
  const nextWindow = windows.reduce((best, w) => (w.startUtc < best.startUtc ? w : best));
  const notification: Notification = {
    title: "You have free time together!",
    body: formatOverlapBody(nextWindow),
    data: { coupleId },
  };

  const sendIfTokens = async (uid: string, tokens: string[]) => {
    if (tokens.length === 0) return;
    const invalidTokens = await deps.sendNotification(tokens, notification);
    if (invalidTokens.length > 0) {
      const valid = tokens.filter((t) => !invalidTokens.includes(t));
      await deps.updateFcmTokens(uid, valid);
    }
  };

  await Promise.all([
    sendIfTokens(couple.userAUid, tokensA),
    sendIfTokens(couple.userBUid, tokensB),
  ]);
}

// ─── Cloud Function export ────────────────────────────────────────────────────

export const onOverlapWrite = onDocumentWritten(
  { document: 'overlaps/{coupleId}/windows/latest', region: 'us-central1' },
  async (event) => {
    const db = admin.firestore();
    const messaging = admin.messaging();
    const { coupleId } = event.params;
    const after = event.data?.after;
    const overlapResult: OverlapResult | undefined = after?.data() as OverlapResult | undefined;
    const windows = overlapResult?.windows ?? [];

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
        const INVALID_TOKEN_CODES = [
          'messaging/invalid-registration-token',
          'messaging/registration-token-not-registered',
        ];
        const invalid: string[] = [];
        for (const [i, result] of response.responses.entries()) {
          if (!result.success) {
            const code = result.error?.code ?? '';
            if (INVALID_TOKEN_CODES.includes(code)) {
              invalid.push(tokens[i]);
            }
            // Transient errors (quota exceeded, internal error, etc.): log but don't prune
          }
        }
        return invalid;
      },
      updateFcmTokens: async (uid, validTokens) => {
        await db.collection('users').doc(uid).update({ fcmTokens: validTokens });
      },
    });
  }
);
