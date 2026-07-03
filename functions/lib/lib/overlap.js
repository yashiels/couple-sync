"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mergeIntervals = mergeIntervals;
exports.intersectIntervals = intersectIntervals;
exports.expandBlock = expandBlock;
exports.computeFreeIntervals = computeFreeIntervals;
exports.clipIntervalToWakingHours = clipIntervalToWakingHours;
exports.clipToWakingHours = clipToWakingHours;
exports.clipToDayBoundaries = clipToDayBoundaries;
exports.scoreWindow = scoreWindow;
exports.computeBlockHash = computeBlockHash;
exports.computeOverlap = computeOverlap;
const crypto_1 = require("crypto");
const luxon_1 = require("luxon");
const rrule_1 = require("rrule");
// ─── Interval utilities ───────────────────────────────────────────────────────
function mergeIntervals(intervals) {
    if (intervals.length === 0)
        return [];
    const sorted = [...intervals].sort((a, b) => a[0] - b[0]);
    const result = [[...sorted[0]]];
    for (let i = 1; i < sorted.length; i++) {
        const last = result[result.length - 1];
        if (sorted[i][0] <= last[1]) {
            last[1] = Math.max(last[1], sorted[i][1]);
        }
        else {
            result.push([...sorted[i]]);
        }
    }
    return result;
}
function intersectIntervals(a, b) {
    const result = [];
    let i = 0;
    let j = 0;
    while (i < a.length && j < b.length) {
        const start = Math.max(a[i][0], b[j][0]);
        const end = Math.min(a[i][1], b[j][1]);
        if (start < end)
            result.push([start, end]);
        if (a[i][1] < b[j][1])
            i++;
        else
            j++;
    }
    return result;
}
// ─── Block expansion ──────────────────────────────────────────────────────────
function expandBlock(block, windowStart, windowEnd) {
    const duration = block.endUtc - block.startUtc;
    if (!block.recurrenceRule) {
        if (block.endUtc <= windowStart || block.startUtc >= windowEnd)
            return [];
        return [[Math.max(block.startUtc, windowStart), Math.min(block.endUtc, windowEnd)]];
    }
    const ruleStr = block.recurrenceRule.startsWith('RRULE:')
        ? block.recurrenceRule.slice(6)
        : block.recurrenceRule;
    const rule = new rrule_1.RRule(Object.assign(Object.assign({}, rrule_1.RRule.parseString(ruleStr)), { dtstart: new Date(block.startUtc) }));
    // Look back by one duration so occurrences starting just before the window
    // that extend into it are included.
    const occurrences = rule.between(new Date(windowStart - duration), new Date(windowEnd), true);
    return occurrences
        .map((occ) => [occ.getTime(), occ.getTime() + duration])
        .filter(([s, e]) => e > windowStart && s < windowEnd)
        .map(([s, e]) => [Math.max(s, windowStart), Math.min(e, windowEnd)]);
}
// ─── Free interval computation ────────────────────────────────────────────────
function computeFreeIntervals(blocks, windowStart, windowEnd) {
    const busy = mergeIntervals(blocks
        .filter((b) => b.type === 'busy' || b.type === 'tentative')
        .flatMap((b) => expandBlock(b, windowStart, windowEnd)));
    const free = [];
    let cursor = windowStart;
    for (const [busyStart, busyEnd] of busy) {
        if (cursor < busyStart)
            free.push([cursor, busyStart]);
        cursor = Math.max(cursor, busyEnd);
    }
    if (cursor < windowEnd)
        free.push([cursor, windowEnd]);
    return free;
}
// ─── Waking-hours clipping ────────────────────────────────────────────────────
const WAKE_HOUR = 7;
const SLEEP_HOUR = 23; // 11 pm
function clipIntervalToWakingHours(start, end, timezone, wakeHour = WAKE_HOUR, sleepHour = SLEEP_HOUR) {
    const result = [];
    let dayStart = luxon_1.DateTime.fromMillis(start, { zone: timezone }).startOf('day');
    while (dayStart.toMillis() < end) {
        const wakeMs = dayStart.set({ hour: wakeHour }).toMillis();
        const sleepMs = dayStart.set({ hour: sleepHour }).toMillis();
        const clipStart = Math.max(start, wakeMs);
        const clipEnd = Math.min(end, sleepMs);
        if (clipStart < clipEnd)
            result.push([clipStart, clipEnd]);
        dayStart = dayStart.plus({ days: 1 });
    }
    return result;
}
function clipToWakingHours(intervals, timezone) {
    return intervals.flatMap(([s, e]) => clipIntervalToWakingHours(s, e, timezone));
}
// Splits multi-day intervals into per-day segments (00:00–24:00 local).
// Used when showLateNightWindows=true so the calendar gets one window per day
// instead of a single interval spanning the whole horizon.
function clipToDayBoundaries(intervals, timezone) {
    const result = [];
    for (const [s, e] of intervals) {
        let dayStart = luxon_1.DateTime.fromMillis(s, { zone: timezone }).startOf('day');
        while (dayStart.toMillis() < e) {
            const dayEnd = dayStart.plus({ days: 1 }).toMillis();
            const clipStart = Math.max(s, dayStart.toMillis());
            const clipEnd = Math.min(e, dayEnd);
            if (clipStart < clipEnd)
                result.push([clipStart, clipEnd]);
            dayStart = dayStart.plus({ days: 1 });
        }
    }
    return result;
}
// ─── Scoring ──────────────────────────────────────────────────────────────────
function scoreWindow(startUtc, endUtc, timezoneA, _timezoneB, now = Date.now()) {
    const durationHours = (endUtc - startUtc) / (60 * 60 * 1000);
    const base = Math.log2(durationHours + 1) * 10;
    const localA = luxon_1.DateTime.fromMillis(startUtc, { zone: timezoneA });
    const eveningBonus = localA.hour >= 18 && localA.hour < 21 ? 5 : 0;
    const weekendBonus = localA.weekday >= 6 ? 5 : 0; // 6=Sat, 7=Sun in Luxon
    const daysFromNow = (startUtc - now) / (24 * 60 * 60 * 1000);
    const timeDecay = Math.max(0, 10 - daysFromNow * 0.5);
    return base + eveningBonus + weekendBonus + timeDecay;
}
// ─── Block hash ───────────────────────────────────────────────────────────────
function computeBlockHash(blocks) {
    const sorted = [...blocks].sort((a, b) => a.startUtc - b.startUtc);
    const str = sorted
        .map((b) => { var _a; return `${b.startUtc}:${b.endUtc}:${(_a = b.recurrenceRule) !== null && _a !== void 0 ? _a : ''}:${b.type}`; })
        .join('|');
    return (0, crypto_1.createHash)('sha256').update(str).digest('hex').slice(0, 16);
}
// ─── Main overlap computation ─────────────────────────────────────────────────
const HORIZON_DAYS = 14;
const MIN_WINDOW_MINUTES = 30;
const MAX_WINDOWS = 20;
function computeOverlap(blocksA, blocksB, timezoneA, timezoneB, now = Date.now(), prefsA = {}, prefsB = {}) {
    const windowEnd = now + HORIZON_DAYS * 24 * 60 * 60 * 1000;
    const freeA = computeFreeIntervals(blocksA, now, windowEnd);
    const freeB = computeFreeIntervals(blocksB, now, windowEnd);
    // Intersect, then clip per partner. Late-night mode uses day boundaries (00:00–24:00)
    // instead of waking hours so intervals stay split per day for calendar rendering.
    let clipped = intersectIntervals(freeA, freeB);
    if (!prefsA.showLateNightWindows) {
        clipped = clipToWakingHours(clipped, timezoneA);
    }
    else {
        clipped = clipToDayBoundaries(clipped, timezoneA);
    }
    if (!prefsB.showLateNightWindows) {
        clipped = clipToWakingHours(clipped, timezoneB);
    }
    else {
        clipped = clipToDayBoundaries(clipped, timezoneB);
    }
    const reasonableBoth = !prefsA.showLateNightWindows && !prefsB.showLateNightWindows;
    const windows = clipped
        .map(([s, e]) => ({
        startUtc: s,
        endUtc: e,
        durationMinutes: Math.round((e - s) / 60000),
        score: scoreWindow(s, e, timezoneA, timezoneB, now),
        reasonableBoth,
    }))
        .filter((w) => w.durationMinutes >= MIN_WINDOW_MINUTES);
    return windows.sort((a, b) => b.score - a.score).slice(0, MAX_WINDOWS);
}
//# sourceMappingURL=overlap.js.map