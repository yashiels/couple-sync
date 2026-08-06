/**
 * The IANA zone list for the timezone picker, taken from the runtime rather than a checked-in table:
 * ECMA-402 exposes the tzdb the platform already ships, so it cannot go stale, and it returns only
 * canonical ids — never a fixed offset like '+02:00', which the backend rejects outright
 * (`backend/src/tz.ts`). Offering a zone the server refuses is the one failure mode worth designing
 * out, so the source of the list is the point of this module.
 *
 * Ceiling: a runtime without full ICU returns nothing, and the picker is then empty — the detected
 * zone is still confirmable, which is the path almost everyone takes. The upgrade path is a bundled
 * zone list, not a hand-maintained one.
 */
const ZONES: readonly string[] =
  typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : [];

/**
 * Every zone, already sorted by id — which groups them by region for free, since the region is the
 * first path segment ('Africa/…', 'America/…'). A section list would buy nothing over that.
 */
export function allZones(): readonly string[] {
  return ZONES;
}

/** 'America/New_York' -> 'america new york', so a human's spacing matches the id's punctuation. */
function normalize(text: string): string {
  return text.toLowerCase().replace(/[_/]/g, ' ').replace(/\s+/g, ' ').trim();
}

/** Substring match on the normalized id. An empty query is the whole list, not an empty result. */
export function searchZones(query: string): readonly string[] {
  const needle = normalize(query);
  if (!needle) return ZONES;
  return ZONES.filter((zone) => normalize(zone).includes(needle));
}
