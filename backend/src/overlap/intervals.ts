export interface Interval {
  start: number;
  end: number;
}

/**
 * Sort by start and coalesce touching or overlapping intervals.
 * Returns fresh objects, so callers can mutate the result without touching the input.
 */
export function merge(intervals: Interval[]): Interval[] {
  const sorted = [...intervals].sort((a, b) => a.start - b.start);
  const out: Interval[] = [];
  for (const iv of sorted) {
    const last = out[out.length - 1];
    // `<=` not `<`: [1,2] and [2,3] touch, and a zero-length gap is not free time.
    if (last && iv.start <= last.end) last.end = Math.max(last.end, iv.end);
    else out.push({ start: iv.start, end: iv.end });
  }
  return out;
}

/** Complement of a merged busy list inside [start, end). */
export function invert(busy: Interval[], start: number, end: number): Interval[] {
  const out: Interval[] = [];
  let cursor = start;
  for (const b of busy) {
    if (cursor < b.start) out.push({ start: cursor, end: Math.min(b.start, end) });
    cursor = Math.max(cursor, b.end);
    if (cursor >= end) break;
  }
  if (cursor < end) out.push({ start: cursor, end });
  return out;
}

/** Two-pointer intersection of two sorted, non-overlapping lists. */
export function intersect(a: Interval[], b: Interval[]): Interval[] {
  const out: Interval[] = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const x = a[i]!;
    const y = b[j]!;
    const s = Math.max(x.start, y.start);
    const e = Math.min(x.end, y.end);
    if (s < e) out.push({ start: s, end: e });
    if (x.end < y.end) i++;
    else j++;
  }
  return out;
}
