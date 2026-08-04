import { createHash } from 'node:crypto';
import { ALGO_VERSION, type Block, type OverlapInput } from './types.js';

/** Only the fields that can change the computed windows. `userId` cannot, so it is not in here. */
function blockKey(b: Block): string {
  return `${b.startUtc}:${b.endUtc}:${b.recurrenceRule ?? ''}:${b.type}:${b.timezone}`;
}

/**
 * Normalised, order-independent digest of one partner's blocks: sorted by startUtc, then by the rest
 * of the tuple. The db returns rows in whatever order it likes; the cache key must not care.
 * Sorts a copy — computeInputHash never mutates its input.
 */
function blocksKey(blocks: Block[]): string {
  const keyed = blocks.map((b) => [b.startUtc, blockKey(b)] as const);
  keyed.sort((x, y) => x[0] - y[0] || x[1].localeCompare(y[1]));
  return keyed.map(([, k]) => k).join(',');
}

/** 16-hex-char cache key over the semantic inputs, bucketed to the hour. */
export function computeInputHash(input: OverlapInput): string {
  const parts = [
    ALGO_VERSION,
    Math.floor(input.now / 3_600_000), // same hour bucket the engine computes for
    input.timezoneA,
    input.timezoneB,
    input.prefsA.showLateNightWindows,
    input.prefsB.showLateNightWindows,
    blocksKey(input.blocksA),
    blocksKey(input.blocksB),
  ];
  return createHash('sha256').update(parts.join('|')).digest('hex').slice(0, 16);
}
