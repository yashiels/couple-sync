import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { DateTime } from "luxon";
import { suggestActivities } from "./gemini";

const getDb = () => admin.firestore();

interface RecurringWindow {
  dayOfWeek: string;
  startTime: string;
  endTime: string;
  consistency: "strong" | "moderate";
  weeksDetected: number;
  suggestedActivity: string | null;
  confirmed: boolean;
}

export const detectPatterns = functions.pubsub
  .schedule("every sunday 00:00")
  .timeZone("UTC")
  .onRun(async () => {
    const couplesSnap = await getDb().collection("couples").get();
    for (const coupleDoc of couplesSnap.docs) {
      await analyzePatterns(coupleDoc.id);
    }
  });

export const detectPatternsManual = functions.firestore
  .document("couples/{coupleId}/patternRequests/{requestId}")
  .onCreate(async (_snap, context) => {
    await analyzePatterns(context.params.coupleId);
  });

async function analyzePatterns(coupleId: string): Promise<void> {
  const days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];

  const windowsDoc = await getDb()
    .collection("overlaps")
    .doc(coupleId)
    .collection("windows")
    .doc("latest")
    .get();

  if (!windowsDoc.exists) return;
  const data = windowsDoc.data();
  if (!data?.windows || data.windows.length === 0) return;

  const dayBuckets: Map<string, Array<{ startHour: number; startMin: number; endHour: number; endMin: number }>> = new Map();

  for (const w of data.windows) {
    const start = DateTime.fromMillis(w.startUtc, { zone: "UTC" });
    const end = DateTime.fromMillis(w.endUtc, { zone: "UTC" });
    if (!start.isValid || !end.isValid) continue;

    const dayName = days[start.weekday - 1];
    if (!dayBuckets.has(dayName)) dayBuckets.set(dayName, []);
    dayBuckets.get(dayName)!.push({
      startHour: start.hour, startMin: start.minute,
      endHour: end.hour, endMin: end.minute,
    });
  }

  const patterns: RecurringWindow[] = [];

  for (const [day, windows] of dayBuckets) {
    const hourGroups: Map<number, typeof windows> = new Map();
    for (const w of windows) {
      const key = Math.round(w.startHour + w.startMin / 60);
      if (!hourGroups.has(key)) hourGroups.set(key, []);
      hourGroups.get(key)!.push(w);
    }

    for (const [, group] of hourGroups) {
      if (group.length >= 2) {
        const avgStartH = Math.round(group.reduce((sum, w) => sum + w.startHour, 0) / group.length);
        const avgStartM = Math.round(group.reduce((sum, w) => sum + w.startMin, 0) / group.length);
        const avgEndH = Math.round(group.reduce((sum, w) => sum + w.endHour, 0) / group.length);
        const avgEndM = Math.round(group.reduce((sum, w) => sum + w.endMin, 0) / group.length);

        patterns.push({
          dayOfWeek: day,
          startTime: `${String(avgStartH).padStart(2, "0")}:${String(avgStartM).padStart(2, "0")}`,
          endTime: `${String(avgEndH).padStart(2, "0")}:${String(avgEndM).padStart(2, "0")}`,
          consistency: group.length >= 3 ? "strong" : "moderate",
          weeksDetected: group.length,
          suggestedActivity: null,
          confirmed: false,
        });
      }
    }
  }

  if (patterns.length === 0) return;

  const suggestions = await suggestActivities(
    patterns.map((p) => {
      const startH = parseInt(p.startTime.split(":")[0]);
      const endH = parseInt(p.endTime.split(":")[0]);
      const duration = (endH - startH) * 60;
      return { startMs: Date.now(), endMs: Date.now() + duration * 60000, durationMinutes: duration > 0 ? duration : 60 };
    })
  );

  for (let i = 0; i < patterns.length; i++) {
    patterns[i].suggestedActivity = suggestions.get(i) || null;
  }

  const batch = getDb().batch();
  const patternsRef = getDb().collection("couples").doc(coupleId).collection("recurringWindows");

  const oldPatterns = await patternsRef.where("confirmed", "==", false).get();
  for (const doc of oldPatterns.docs) {
    batch.delete(doc.ref);
  }

  for (const pattern of patterns) {
    batch.set(patternsRef.doc(), { ...pattern, createdAt: admin.firestore.FieldValue.serverTimestamp() });
  }

  await batch.commit();
  functions.logger.info(`Detected ${patterns.length} patterns for couple ${coupleId}`);
}
