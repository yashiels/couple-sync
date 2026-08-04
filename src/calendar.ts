import { GoogleSignin, type User } from '@react-native-google-signin/google-signin';
import * as SecureStore from 'expo-secure-store';

import { api } from './api';
import { CALENDAR_SCOPE, getGoogleAccessToken } from './auth';
import { useStore } from './store';

/**
 * Google Calendar, freebusy only (§5). There is no connect/disconnect/isConnected: signing in with
 * Google *is* the grant, so this module only ever spends it. The one API call in the whole app is
 * `freeBusy.query` on the primary calendar — never `events.list`, and no `summary` is ever read, so
 * an event title cannot reach this process, let alone the server.
 */

const HOUR_MS = 60 * 60 * 1000;
const LOOKAHEAD_MS = 14 * 24 * HOUR_MS;
const FREEBUSY_URL = 'https://www.googleapis.com/calendar/v3/freeBusy';

/**
 * Persisted, not a module variable: an in-memory timestamp resets on every launch, which is exactly
 * when auto-sync fires, so the ≤1-automatic-call-per-hour rule would be broken by the one code path
 * it exists to protect.
 */
const LAST_SYNC_KEY = 'calendar.lastSyncMs';

/** 429/503 only. Anything else is either fatal or a permission problem, and retrying repeats it. */
const RETRY_DELAYS_MS = [1000, 2000, 4000];

export type SyncResult = 'synced' | 'rate-limited' | 'scope-missing' | 'no-session';

/** freeBusy's response, narrowed to the two fields we read. There is deliberately no title field. */
interface FreeBusyResponse {
  calendars?: Record<string, { busy?: { start?: string; end?: string }[] }>;
}

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * The §5 carve-out: `freeBusy.query` requires RFC3339 `timeMin`/`timeMax`, while every other
 * timestamp in this app is epoch ms. `Date#toISOString` is already RFC3339 in UTC; luxon would only
 * add a `string | null` return to unwrap for the same result.
 */
const rfc3339 = (ms: number): string => new Date(ms).toISOString();

/**
 * A cold start has a cached Google account but no live session, and `getTokens()` *rejects* until one
 * exists (it does not return null). Returns null when there is nothing to restore — the caller maps
 * that to 'no-session' rather than letting a native rejection escape.
 */
async function currentGoogleUser(): Promise<User | null> {
  const cached = GoogleSignin.getCurrentUser();
  if (cached) return cached;
  if (!GoogleSignin.hasPreviousSignIn()) return null;
  try {
    const res = await GoogleSignin.signInSilently();
    return res.type === 'success' ? res.data : null;
  } catch {
    return null;
  }
}

/** True when the current Google grant still includes calendar.readonly. */
export async function hasCalendarScope(): Promise<boolean> {
  return (await currentGoogleUser())?.scopes.includes(CALENDAR_SCOPE) ?? false;
}

/**
 * The only correct use of addScopes in this app: a user who declined the calendar consent while
 * completing sign-in, or revoked it later from their Google account. On success the caller syncs
 * immediately with `{ force: true }`. Resolves false on cancellation — that is not an error.
 */
export async function ensureScope(): Promise<boolean> {
  try {
    // An OBJECT argument. `addScopes([CALENDAR_SCOPE])` does not compile (google-signin types.ts).
    const res = await GoogleSignin.addScopes({ scopes: [CALENDAR_SCOPE] });
    return res?.type === 'success';
  } catch {
    return false;
  }
}

async function readLastSync(): Promise<number | null> {
  try {
    const raw = await SecureStore.getItemAsync(LAST_SYNC_KEY);
    const ms = raw === null ? Number.NaN : Number(raw);
    return Number.isFinite(ms) ? ms : null;
  } catch {
    // A keystore read can fail on a re-installed app. Treating it as "never synced" costs one extra
    // freebusy call; treating it as "just synced" would hide the calendar until the next launch.
    return null;
  }
}

/**
 * Cleared from both `reset()` and `resetCouple()` via the store's seam. An unpair deletes the
 * couple's google blocks, so a surviving timestamp would suppress the very sync that repopulates them
 * and the user would see an empty calendar under a "synced 20 minutes ago" label.
 */
export function clearSyncLimiter(): void {
  void SecureStore.deleteItemAsync(LAST_SYNC_KEY).catch(() => undefined);
}

/**
 * freeBusy.query on the primary calendar for the next 14 days → `PUT /blocks/google`.
 *
 * `force` has exactly three permitted callers — the Settings "Sync now" button, a successful
 * `ensureScope()`, and the moment a couple first pairs — each a discrete user action, so none can
 * loop. It must never be passed from a render path, an effect that can re-run, or a retry loop.
 *
 * Ceiling: the limiter is per *device*, not per user, so a phone plus a tablet gets two automatic
 * calls an hour. Server-side enforcement needs a `last_calendar_sync` column on `users` — that is the
 * upgrade path, and it is also what would stop repeated pair/unpair cycles forcing repeated syncs.
 */
export async function sync(coupleId: string, opts?: { force?: boolean }): Promise<SyncResult> {
  const now = Date.now();
  const last = await readLastSync();
  // Mirrored into the store so Settings can show a real "last synced" even on the rate-limited path.
  if (last !== null) useStore.getState().setLastCalendarSync(last);
  // `last <= now` as well: a device clock that jumped backwards would otherwise wedge auto-sync off
  // until it caught up.
  if (!opts?.force && last !== null && last <= now && now - last < HOUR_MS) return 'rate-limited';

  const user = await currentGoogleUser();
  if (!user) return 'no-session';
  if (!user.scopes.includes(CALENDAR_SCOPE)) return 'scope-missing';

  const accessToken = await getGoogleAccessToken();
  // There IS a cached account (checked above), so a null token means getTokens() rejected during
  // token recovery — a broken grant, which ensureScope() is what fixes. Never a leaked native error.
  if (!accessToken) return 'scope-missing';

  const busy = await fetchBusy(accessToken, now, now + LOOKAHEAD_MS);
  if (busy === 'scope-missing') return 'scope-missing';

  await api.putGoogleBlocks(coupleId, busy);
  useStore.getState().setLastCalendarSync(now);
  try {
    await SecureStore.setItemAsync(LAST_SYNC_KEY, String(now));
  } catch {
    // Ceiling: a keystore write failure defeats the limiter for this device, so auto-sync would run
    // once per launch instead of once per hour. Moving the timestamp server-side is the upgrade path.
  }
  return 'synced';
}

async function fetchBusy(
  accessToken: string,
  fromMs: number,
  toMs: number,
): Promise<{ start_utc: number; end_utc: number }[] | 'scope-missing'> {
  for (let attempt = 0; ; attempt += 1) {
    const res = await fetch(FREEBUSY_URL, {
      method: 'POST',
      headers: {
        // The GOOGLE OAuth access token. The Firebase ID token authorizes our backend and is
        // rejected here; the two are not interchangeable and confusing them is the classic failure.
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      // freeBusy.query, primary calendar, 14 days. No event read, so there is no title in the
      // response for us to leak even by accident.
      body: JSON.stringify({
        timeMin: rfc3339(fromMs),
        timeMax: rfc3339(toMs),
        items: [{ id: 'primary' }],
      }),
    });

    // 401 is an expired/withdrawn token, 403 a missing scope or a disabled Calendar API. Both are
    // fixed by re-consenting, and neither is worth a retry.
    if (res.status === 401 || res.status === 403) return 'scope-missing';
    if ((res.status === 429 || res.status === 503) && attempt < RETRY_DELAYS_MS.length) {
      await sleep(RETRY_DELAYS_MS[attempt] ?? 1000);
      continue;
    }
    if (!res.ok) throw new Error(`freebusy_${res.status}`);
    return intervals((await res.json()) as FreeBusyResponse);
  }
}

function intervals(body: FreeBusyResponse): { start_utc: number; end_utc: number }[] {
  const out: { start_utc: number; end_utc: number }[] = [];
  for (const b of body.calendars?.['primary']?.busy ?? []) {
    // Straight back to epoch ms: RFC3339 exists only on Google's side of that one request.
    const start = Date.parse(b.start ?? '');
    const end = Date.parse(b.end ?? '');
    // A malformed or zero-length interval is dropped rather than posted: the server rejects the whole
    // batch on one bad interval, which would lose the other forty.
    if (Number.isFinite(start) && Number.isFinite(end) && end > start) {
      out.push({ start_utc: start, end_utc: end });
    }
  }
  return out;
}
