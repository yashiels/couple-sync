import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

const getDb = () => admin.firestore();

interface OverlapWindowDoc {
  startUtc: number;
  endUtc: number;
  durationMinutes: number;
  score: number;
  reasonableBoth: boolean;
}

interface WindowsDocument {
  windows: OverlapWindowDoc[];
  computedAt: admin.firestore.Timestamp;
  coupleId: string;
}

// ---------------------------------------------------------------------------
// Trigger: send FCM push when new overlap windows are stored
// ---------------------------------------------------------------------------

export const onOverlapWrite = functions.firestore
  .document("overlaps/{coupleId}/windows/latest")
  .onWrite(async (change, context) => {
    const { coupleId } = context.params as { coupleId: string };

    const after = change.after.exists ? (change.after.data() as WindowsDocument) : null;
    if (!after || !after.windows || after.windows.length === 0) return;

    // Skip if nothing actually changed (Firestore can re-trigger on metadata writes)
    if (change.before.exists) {
      const before = change.before.data() as WindowsDocument;
      if (before.windows?.length === after.windows.length &&
          before.windows[0]?.startUtc === after.windows[0]?.startUtc) {
        return;
      }
    }

    // Fetch couple to get user UIDs
    const coupleDoc = await getDb().collection("couples").doc(coupleId).get();
    if (!coupleDoc.exists) return;
    const { userAUid, userBUid } = coupleDoc.data() as { userAUid: string; userBUid: string };

    // Collect FCM tokens for both partners
    const tokens = await collectFcmTokens([userAUid, userBUid]);
    if (tokens.length === 0) return;

    // Format notification body using the top-ranked window
    const top = after.windows[0];
    const startDate = new Date(top.startUtc);
    const timeStr = startDate.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "UTC",
    });
    const dateStr = startDate.toLocaleDateString("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
      timeZone: "UTC",
    });
    const durationStr = formatDuration(top.durationMinutes);

    const message: admin.messaging.MulticastMessage = {
      notification: {
        title: "You both have free time!",
        body: `${dateStr} at ${timeStr} UTC for ${durationStr}. Plan something together!`,
      },
      data: {
        coupleId,
        type: "overlap_update",
        startUtc: String(top.startUtc),
        durationMinutes: String(top.durationMinutes),
      },
      android: {
        priority: "normal",
        notification: { channelId: "overlap_updates" },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
      tokens,
    };

    try {
      const result = await admin.messaging().sendEachForMulticast(message);
      functions.logger.info(
        `FCM overlap update: ${result.successCount} sent, ${result.failureCount} failed for couple ${coupleId}`
      );
      // Clean up stale tokens
      await pruneStaleTokens(result, tokens, [userAUid, userBUid]);
    } catch (err) {
      functions.logger.error("FCM send error", err);
    }
  });

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function collectFcmTokens(uids: string[]): Promise<string[]> {
  const tokens: string[] = [];
  for (const uid of uids) {
    const userDoc = await getDb().collection("users").doc(uid).get();
    if (userDoc.exists) {
      const token: string | undefined = userDoc.data()?.fcmToken;
      if (token) tokens.push(token);
    }
  }
  return tokens;
}

async function pruneStaleTokens(
  result: admin.messaging.BatchResponse,
  tokens: string[],
  uids: string[]
): Promise<void> {
  const batch = getDb().batch();
  let pruned = false;

  for (let i = 0; i < result.responses.length; i++) {
    const resp = result.responses[i];
    if (!resp.success && resp.error?.code === "messaging/registration-token-not-registered") {
      // Find which user held this token and clear it
      for (const uid of uids) {
        const userDoc = await getDb().collection("users").doc(uid).get();
        if (userDoc.exists && userDoc.data()?.fcmToken === tokens[i]) {
          batch.update(getDb().collection("users").doc(uid), { fcmToken: admin.firestore.FieldValue.delete() });
          pruned = true;
        }
      }
    }
  }

  if (pruned) await batch.commit();
}

function formatDuration(minutes: number): string {
  if (minutes < 60) return `${minutes}m`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}
