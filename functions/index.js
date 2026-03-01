/* eslint-disable max-len */
"use strict";

const admin = require("firebase-admin");
const functions = require("firebase-functions");

admin.initializeApp();
const db = admin.firestore();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Maximum number of ranked overlap windows stored per couple. */
const MAX_WINDOWS = 20;

/** Minimum overlap duration to surface (in minutes). */
const MIN_DURATION_MINUTES = 30;

/** Quiet hours: windows that start before this local hour are deprioritised. */
const QUIET_HOUR_START = 8;   // 08:00 local

/** Quiet hours: windows that start at or after this local hour are deprioritised. */
const QUIET_HOUR_END = 22;    // 22:00 local

// ---------------------------------------------------------------------------
// Trigger: run overlap engine whenever a time block changes for a couple
// ---------------------------------------------------------------------------

exports.onBlockWrite = functions.firestore
    .document("timeblocks/{coupleId}/blocks/{blockId}")
    .onWrite(async (change, context) => {
      const {coupleId} = context.params;
      await runOverlapEngine(coupleId);
    });

// ---------------------------------------------------------------------------
// Trigger: send FCM notification when new overlap windows are computed
// ---------------------------------------------------------------------------

exports.onOverlapWrite = functions.firestore
    .document("overlapWindows/{coupleId}")
    .onWrite(async (change, context) => {
      const {coupleId} = context.params;
      const after = change.after.exists ? change.after.data() : null;
      if (!after || !after.windows || after.windows.length === 0) return;

      // Fetch couple's user uids to send notifications
      const coupleDoc = await db.collection("couples").doc(coupleId).get();
      if (!coupleDoc.exists) return;
      const {userAUid, userBUid} = coupleDoc.data();

      const uids = [userAUid, userBUid];
      const tokens = [];

      for (const uid of uids) {
        const userDoc = await db.collection("users").doc(uid).get();
        if (userDoc.exists && userDoc.data().fcmToken) {
          tokens.push(userDoc.data().fcmToken);
        }
      }

      if (tokens.length === 0) return;

      const topWindow = after.windows[0];
      const start = new Date(topWindow.startUtc).toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"});

      const message = {
        notification: {
          title: "New Free Window Found!",
          body: `You both have free time starting at ${start}. Plan something!`,
        },
        data: {
          coupleId,
          type: "overlap_update",
        },
        tokens,
      };

      try {
        const result = await admin.messaging().sendEachForMulticast(message);
        functions.logger.info(`FCM sent: ${result.successCount} success, ${result.failureCount} failures`);
      } catch (err) {
        functions.logger.error("FCM error", err);
      }
    });

// ---------------------------------------------------------------------------
// HTTP callable: manually trigger overlap engine for a couple
// ---------------------------------------------------------------------------

exports.computeOverlap = functions.https.onCall(async (data) => {
  const {coupleId} = data;
  if (!coupleId) throw new functions.https.HttpsError("invalid-argument", "coupleId required");
  const windows = await runOverlapEngine(coupleId);
  return {windows};
});

// ---------------------------------------------------------------------------
// Core overlap algorithm
// ---------------------------------------------------------------------------

/**
 * @param {string} coupleId
 * @returns {Promise<Array>} ranked overlap windows
 */
async function runOverlapEngine(coupleId) {
  // 1. Fetch couple document to get user uids
  const coupleDoc = await db.collection("couples").doc(coupleId).get();
  if (!coupleDoc.exists) {
    functions.logger.warn(`Couple ${coupleId} not found`);
    return [];
  }
  const {userAUid, userBUid} = coupleDoc.data();

  // 2. Fetch user timezones
  const [userADoc, userBDoc] = await Promise.all([
    db.collection("users").doc(userAUid).get(),
    db.collection("users").doc(userBUid).get(),
  ]);

  const tzA = userADoc.exists ? (userADoc.data().timezone || "UTC") : "UTC";
  const tzB = userBDoc.exists ? (userBDoc.data().timezone || "UTC") : "UTC";

  // 3. Define search horizon: next 14 days in UTC
  const now = Date.now();
  const horizonMs = 14 * 24 * 60 * 60 * 1000;
  const fromMs = now;
  const toMs = now + horizonMs;

  // 4. Fetch all blocks for the couple in the horizon
  const blocksSnap = await db
      .collection("timeblocks")
      .doc(coupleId)
      .collection("blocks")
      .where("startUtc", ">=", admin.firestore.Timestamp.fromMillis(fromMs))
      .where("startUtc", "<", admin.firestore.Timestamp.fromMillis(toMs))
      .get();

  const blocks = blocksSnap.docs.map((doc) => {
    const d = doc.data();
    return {
      userId: d.userId,
      type: d.type,
      startMs: d.startUtc.toMillis(),
      endMs: d.endUtc.toMillis(),
      visibility: d.visibility,
    };
  });

  // 5. Build busy timelines per user (only busy blocks visible to both)
  const busyA = buildBusyTimeline(blocks, userAUid);
  const busyB = buildBusyTimeline(blocks, userBUid);

  // 6. Compute free intervals for each user within the horizon
  const freeA = invertBusyToFree(busyA, fromMs, toMs);
  const freeB = invertBusyToFree(busyB, fromMs, toMs);

  // 7. Intersect free intervals
  const intersected = intersectIntervals(freeA, freeB);

  // 8. Filter by minimum duration
  const minMs = MIN_DURATION_MINUTES * 60 * 1000;
  const filtered = intersected.filter((w) => w.endMs - w.startMs >= minMs);

  // 9. Score and rank windows
  const ranked = filtered
      .map((w) => scoreWindow(w, tzA, tzB))
      .sort((a, b) => b.score - a.score)
      .slice(0, MAX_WINDOWS);

  // 10. Persist to Firestore
  const output = ranked.map((w) => ({
    startUtc: w.startMs,
    endUtc: w.endMs,
    durationMinutes: Math.floor((w.endMs - w.startMs) / 60000),
    score: w.score,
    reasonableBoth: w.reasonableBoth,
  }));

  await db.collection("overlapWindows").doc(coupleId).set({
    windows: output,
    computedAt: admin.firestore.FieldValue.serverTimestamp(),
    coupleId,
  });

  return output;
}

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

/**
 * Extract busy intervals for a user, including only blocks they own
 * that are visible to both partners, sorted by start time.
 */
function buildBusyTimeline(blocks, userId) {
  return blocks
      .filter((b) => b.userId === userId && b.type === "busy" && b.visibility !== "onlyMe")
      .map((b) => ({startMs: b.startMs, endMs: b.endMs}))
      .sort((a, b) => a.startMs - b.startMs);
}

/**
 * Merge overlapping intervals and invert within [fromMs, toMs].
 * Returns an array of free intervals.
 */
function invertBusyToFree(busy, fromMs, toMs) {
  if (busy.length === 0) return [{startMs: fromMs, endMs: toMs}];

  // Merge overlapping busy intervals
  const merged = [];
  for (const interval of busy) {
    if (merged.length === 0 || interval.startMs > merged[merged.length - 1].endMs) {
      merged.push({...interval});
    } else {
      merged[merged.length - 1].endMs = Math.max(merged[merged.length - 1].endMs, interval.endMs);
    }
  }

  // Invert
  const free = [];
  let cursor = fromMs;
  for (const busy of merged) {
    if (busy.startMs > cursor) {
      free.push({startMs: cursor, endMs: busy.startMs});
    }
    cursor = Math.max(cursor, busy.endMs);
  }
  if (cursor < toMs) {
    free.push({startMs: cursor, endMs: toMs});
  }
  return free;
}

/**
 * Intersect two sorted free interval lists.
 */
function intersectIntervals(a, b) {
  const result = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const start = Math.max(a[i].startMs, b[j].startMs);
    const end = Math.min(a[i].endMs, b[j].endMs);
    if (start < end) {
      result.push({startMs: start, endMs: end});
    }
    if (a[i].endMs < b[j].endMs) i++;
    else j++;
  }
  return result;
}

/**
 * Assign a score to a free window based on time-of-day heuristics.
 * Higher is better.
 *
 * @param {{startMs: number, endMs: number}} window
 * @param {string} tzA - IANA timezone of user A
 * @param {string} tzB - IANA timezone of user B
 * @returns {{startMs, endMs, score, reasonableBoth}}
 */
function scoreWindow(window, tzA, tzB) {
  const {startMs, endMs} = window;
  const durationMin = (endMs - startMs) / 60000;

  // Get local hours for both users at window start
  const hourA = getLocalHour(startMs, tzA);
  const hourB = getLocalHour(startMs, tzB);

  const reasonableA = hourA >= QUIET_HOUR_START && hourA < QUIET_HOUR_END;
  const reasonableB = hourB >= QUIET_HOUR_START && hourB < QUIET_HOUR_END;
  const reasonableBoth = reasonableA && reasonableB;

  // Base score: duration (log scale to prevent very long windows dominating)
  let score = Math.log2(durationMin + 1) * 10;

  // Bonus for both users being in reasonable hours
  if (reasonableBoth) score += 50;
  else if (reasonableA || reasonableB) score += 20;

  // Bonus for evening / weekend times (heuristic for couple time)
  const dayOfWeek = new Date(startMs).getUTCDay(); // 0 Sun, 6 Sat
  if (dayOfWeek === 0 || dayOfWeek === 6) score += 15;

  // Slight preference for sooner windows
  const daysFromNow = (startMs - Date.now()) / (24 * 60 * 60 * 1000);
  score -= daysFromNow * 0.5;

  return {startMs, endMs, score: Math.round(score * 10) / 10, reasonableBoth};
}

/**
 * Get the local hour (0-23) for a UTC timestamp in a given IANA timezone.
 * Falls back to UTC hour if the timezone is invalid.
 */
function getLocalHour(utcMs, timezone) {
  try {
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      hour: "numeric",
      hour12: false,
    });
    const parts = formatter.formatToParts(new Date(utcMs));
    const hourPart = parts.find((p) => p.type === "hour");
    return hourPart ? parseInt(hourPart.value, 10) % 24 : 0;
  } catch (_) {
    return new Date(utcMs).getUTCHours();
  }
}
