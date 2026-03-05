import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { DateTime } from "luxon";
import { suggestActivities } from "./gemini";

const getDb = () => admin.firestore();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_WINDOWS = 20;
const MIN_DURATION_MINUTES = 30;
const LOOKAHEAD_DAYS = 14;

/** Local hour (inclusive) below which a window start is considered quiet. */
const QUIET_HOUR_BEFORE = 7;
/** Local hour (inclusive) at or above which a window start is considered quiet. */
const QUIET_HOUR_AFTER = 23;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Interval {
  startMs: number;
  endMs: number;
}

interface ScoredWindow extends Interval {
  score: number;
  reasonableBoth: boolean;
}

interface OverlapWindowDoc {
  startUtc: number;
  endUtc: number;
  durationMinutes: number;
  score: number;
  reasonableBoth: boolean;
  suggestedActivity: string | null;
}

// ---------------------------------------------------------------------------
// Trigger
// ---------------------------------------------------------------------------

export const onBlockWrite = functions.firestore
  .document("timeblocks/{coupleId}/blocks/{blockId}")
  .onWrite(async (_change, context) => {
    const { coupleId } = context.params as { coupleId: string };
    await runOverlapEngine(coupleId);
  });

// ---------------------------------------------------------------------------
// Core algorithm
// ---------------------------------------------------------------------------

async function runOverlapEngine(coupleId: string): Promise<OverlapWindowDoc[]> {
  // 1. Fetch couple document
  const coupleDoc = await getDb().collection("couples").doc(coupleId).get();
  if (!coupleDoc.exists) {
    functions.logger.warn(`Couple ${coupleId} not found`);
    return [];
  }
  const { userAUid, userBUid } = coupleDoc.data() as { userAUid: string; userBUid: string };

  // 2. Fetch user timezones
  const [userADoc, userBDoc] = await Promise.all([
    getDb().collection("users").doc(userAUid).get(),
    getDb().collection("users").doc(userBUid).get(),
  ]);

  const tzA: string = (userADoc.exists && userADoc.data()?.timezone) ? userADoc.data()!.timezone : "UTC";
  const tzB: string = (userBDoc.exists && userBDoc.data()?.timezone) ? userBDoc.data()!.timezone : "UTC";

  // 3. 2-week lookahead horizon in UTC milliseconds
  const fromMs = Date.now();
  const toMs = fromMs + LOOKAHEAD_DAYS * 24 * 60 * 60 * 1000;

  // 4. Fetch all blocks within the horizon.
  // Widen query start by 24 h so we don't miss blocks that started before
  // `fromMs` but are still active (same approach as the Flutter side).
  const queryFromMs = fromMs - 24 * 60 * 60 * 1000;
  const blocksSnap = await getDb()
    .collection("timeblocks")
    .doc(coupleId)
    .collection("blocks")
    .where("startUtc", ">=", admin.firestore.Timestamp.fromMillis(queryFromMs))
    .where("startUtc", "<", admin.firestore.Timestamp.fromMillis(toMs))
    .get();

  const blocks = blocksSnap.docs.map((doc) => {
    const d = doc.data();
    return {
      userId: d.userId as string,
      type: d.type as string,
      startMs: (d.startUtc as admin.firestore.Timestamp).toMillis(),
      endMs: (d.endUtc as admin.firestore.Timestamp).toMillis(),
      visibility: d.visibility as string,
    };
  });

  // 5. Build sorted busy timelines per user (skip "onlyMe" blocks)
  const busyA = buildBusyTimeline(blocks, userAUid);
  const busyB = buildBusyTimeline(blocks, userBUid);

  // 6. Invert busy → free within the horizon
  const freeA = invertBusyToFree(busyA, fromMs, toMs);
  const freeB = invertBusyToFree(busyB, fromMs, toMs);

  // 7. Intersect the two free timelines
  const intersected = intersectIntervals(freeA, freeB);

  // 8. Clip windows to reasonable waking hours for both partners, then
  //    filter by minimum duration.  Instead of discarding an entire window
  //    whose start falls before 7 AM, we clip to the later of the two
  //    partners' quiet-hour-end times (7 AM local) and the earlier of
  //    their quiet-hour-start times (11 PM local).
  const minMs = MIN_DURATION_MINUTES * 60_000;

  const filtered = intersected
    .map((w) => {
      // --- clip start to 7 AM local for each partner ---
      const dtStartA = DateTime.fromMillis(w.startMs, { zone: tzA });
      const dayStartA = dtStartA.startOf("day").toMillis();
      const validStartA = dayStartA + QUIET_HOUR_BEFORE * 3_600_000;

      const dtStartB = DateTime.fromMillis(w.startMs, { zone: tzB });
      const dayStartB = dtStartB.startOf("day").toMillis();
      const validStartB = dayStartB + QUIET_HOUR_BEFORE * 3_600_000;

      // --- clip end to 11 PM local for each partner ---
      const dtEndA = DateTime.fromMillis(w.endMs, { zone: tzA });
      const dayEndA = dtEndA.startOf("day").toMillis();
      const validEndA = dayEndA + QUIET_HOUR_AFTER * 3_600_000;

      const dtEndB = DateTime.fromMillis(w.endMs, { zone: tzB });
      const dayEndB = dtEndB.startOf("day").toMillis();
      const validEndB = dayEndB + QUIET_HOUR_AFTER * 3_600_000;

      const clippedStart = Math.max(w.startMs, validStartA, validStartB);
      const clippedEnd = Math.min(w.endMs, validEndA, validEndB);

      return { startMs: clippedStart, endMs: clippedEnd };
    })
    .filter((w) => w.endMs - w.startMs >= minMs);

  // 9. Score, rank, slice
  const ranked: ScoredWindow[] = filtered
    .map((w) => scoreWindow(w, tzA, tzB))
    .sort((a, b) => b.score - a.score)
    .slice(0, MAX_WINDOWS);

  // 10. Fetch Gemini activity suggestions for ranked windows
  const suggestions = await suggestActivities(
    ranked.map((w) => ({
      startMs: w.startMs,
      endMs: w.endMs,
      durationMinutes: Math.floor((w.endMs - w.startMs) / 60_000),
    }))
  );

  // 11. Persist top windows
  const output: OverlapWindowDoc[] = ranked.map((w, i) => ({
    startUtc: w.startMs,
    endUtc: w.endMs,
    durationMinutes: Math.floor((w.endMs - w.startMs) / 60_000),
    score: w.score,
    reasonableBoth: w.reasonableBoth,
    suggestedActivity: suggestions.get(i) || null,
  }));

  await getDb().collection("overlaps").doc(coupleId).collection("windows").doc("latest").set({
    windows: output,
    computedAt: admin.firestore.FieldValue.serverTimestamp(),
    coupleId,
  });

  return output;
}

// ---------------------------------------------------------------------------
// Helper: build busy timeline
// ---------------------------------------------------------------------------

function buildBusyTimeline(
  blocks: Array<{ userId: string; type: string; startMs: number; endMs: number; visibility: string }>,
  userId: string
): Interval[] {
  return blocks
    .filter((b) => b.userId === userId && (b.type === "busy" || b.type === "tentative") && b.visibility !== "onlyMe")
    .map((b) => ({ startMs: b.startMs, endMs: b.endMs }))
    .sort((a, b) => a.startMs - b.startMs);
}

// ---------------------------------------------------------------------------
// Helper: merge overlapping busy intervals then invert to free
// ---------------------------------------------------------------------------

function invertBusyToFree(busy: Interval[], fromMs: number, toMs: number): Interval[] {
  if (busy.length === 0) return [{ startMs: fromMs, endMs: toMs }];

  // Merge overlapping/adjacent busy blocks
  const merged: Interval[] = [];
  for (const b of busy) {
    if (merged.length === 0 || b.startMs > merged[merged.length - 1].endMs) {
      merged.push({ ...b });
    } else {
      merged[merged.length - 1].endMs = Math.max(merged[merged.length - 1].endMs, b.endMs);
    }
  }

  // Invert within [fromMs, toMs]
  const free: Interval[] = [];
  let cursor = fromMs;
  for (const b of merged) {
    if (b.startMs > cursor) free.push({ startMs: cursor, endMs: b.startMs });
    cursor = Math.max(cursor, b.endMs);
  }
  if (cursor < toMs) free.push({ startMs: cursor, endMs: toMs });

  return free;
}

// ---------------------------------------------------------------------------
// Helper: intersect two sorted free interval lists
// ---------------------------------------------------------------------------

function intersectIntervals(a: Interval[], b: Interval[]): Interval[] {
  const result: Interval[] = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const start = Math.max(a[i].startMs, b[j].startMs);
    const end = Math.min(a[i].endMs, b[j].endMs);
    if (start < end) result.push({ startMs: start, endMs: end });
    if (a[i].endMs < b[j].endMs) i++;
    else j++;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Helper: score a window
// ---------------------------------------------------------------------------

function scoreWindow(window: Interval, tzA: string, tzB: string): ScoredWindow {
  const { startMs, endMs } = window;
  const durationMin = (endMs - startMs) / 60_000;

  const hourA = getLocalHour(startMs, tzA);
  const hourB = getLocalHour(startMs, tzB);

  const eveningA = hourA >= 17 && hourA < 22;
  const eveningB = hourB >= 17 && hourB < 22;
  const reasonableBoth =
    hourA >= QUIET_HOUR_BEFORE && hourA < QUIET_HOUR_AFTER &&
    hourB >= QUIET_HOUR_BEFORE && hourB < QUIET_HOUR_AFTER;

  // Base: log-scale duration so very long windows don't dominate
  let score = Math.log2(durationMin + 1) * 10;

  // Both in reasonable hours already guaranteed by filter, but reward evening
  if (eveningA && eveningB) score += 30;
  else if (eveningA || eveningB) score += 10;

  // Weekend bonus
  const dt = DateTime.fromMillis(startMs, { zone: "UTC" });
  if (dt.weekday === 6 || dt.weekday === 7) score += 15; // Sat=6, Sun=7 in luxon

  // Prefer sooner windows slightly
  const daysFromNow = (startMs - Date.now()) / (24 * 60 * 60 * 1000);
  score -= daysFromNow * 0.5;

  return { startMs, endMs, score: Math.round(score * 10) / 10, reasonableBoth };
}

// ---------------------------------------------------------------------------
// Helper: local hour for a UTC timestamp in an IANA timezone
// ---------------------------------------------------------------------------

function getLocalHour(utcMs: number, timezone: string): number {
  const dt = DateTime.fromMillis(utcMs, { zone: timezone });
  return dt.isValid ? dt.hour : new Date(utcMs).getUTCHours();
}
