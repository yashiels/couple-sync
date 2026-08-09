import { GoogleSignin, type User } from '@react-native-google-signin/google-signin';
import * as SecureStore from 'expo-secure-store';

import { api } from './api';
import { CALENDAR_SCOPE, getGoogleAccessToken } from './auth';
import { deviceBusy } from './deviceCalendar';
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
 * Google is the only metered source, so only Google gets an hourly gate (§5). The device OS calendar
 * read is local and unmetered, so it runs on every sync and has no gate — only a freshness stamp.
 *
 * All three are persisted, not module variables: an in-memory timestamp resets on every launch, which
 * is exactly when auto-sync fires, so the ≤1-automatic-Google-call-per-hour rule would be broken by
 * the one code path it exists to protect.
 */
const GOOGLE_GATE_KEY = 'calendar.googleGateMs';
const GOOGLE_SUCCESS_KEY = 'calendar.googleSuccessMs';
const DEVICE_SUCCESS_KEY = 'calendar.deviceSuccessMs';

/** 429/503 only. Anything else is either fatal or a permission problem, and retrying repeats it. */
const RETRY_DELAYS_MS = [1000, 2000, 4000];

/**
 * The result of one sync, per source. The two sources are independent: a Google failure never masks a
 * device success and vice-versa.
 *   device 'empty'   = the OS read succeeded but had no busy times (device blocks cleared).
 *   device 'skipped' = the native read returned null (a read failure) — device blocks left untouched.
 *   google 'rate-limited' = the hourly gate suppressed an automatic call (or its reservation failed).
 */
export interface SyncSummary {
  device: 'synced' | 'empty' | 'failed' | 'skipped';
  google: 'synced' | 'rate-limited' | 'scope-missing' | 'no-session' | 'failed';
}

/** freeBusy's response, narrowed to the fields we read. There is deliberately no title field. The
 *  `errors` array is why we can't treat a missing `busy` as "no busy times": Google returns HTTP 200
 *  with a per-calendar error (e.g. rate/notFound), and a naive read would post [] and delete blocks. */
interface FreeBusyResponse {
  calendars?: Record<
    string,
    { busy?: { start?: string; end?: string }[]; errors?: { reason?: string }[] }
  >;
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

async function readMs(key: string): Promise<number | null> {
  try {
    const raw = await SecureStore.getItemAsync(key);
    const ms = raw === null ? Number.NaN : Number(raw);
    return Number.isFinite(ms) ? ms : null;
  } catch {
    // A keystore read can fail on a re-installed app. Treating it as "never synced" costs one extra
    // freebusy call; treating it as "just synced" would hide the calendar until the next launch.
    return null;
  }
}

/**
 * Cleared from both `reset()` and `resetCouple()` via the store's seam. Clears ONLY the per-source
 * freshness stamps (they back the Settings labels and would otherwise lie about a wiped source).
 *
 * The Google GATE is deliberately NOT cleared: it is the device-wide §5 quota window, and wiping it on
 * sign-out/unpair would let a sign-out-then-in within the hour fire a second automatic Google call. A
 * re-pair repopulates via the first-pair `force` sync, which bypasses the gate anyway — so nothing
 * needs the gate cleared. Also drops the pre-split legacy key best-effort.
 */
export function clearSyncLimiter(): void {
  // Enqueued onto the SAME chain sync() uses, not fired loose: an unawaited delete could otherwise
  // land after a concurrent re-pair `force` sync has already re-read (and mirrored) or re-written a
  // freshness stamp, erasing a fresh success or restoring a stale one. On the chain the deletes run
  // after any in-flight sync and before any sync enqueued later, so freshness cleanup is ordered
  // w.r.t. every read/write of these keys.
  void enqueue(clearFreshnessKeys);
}

async function clearFreshnessKeys(): Promise<void> {
  await SecureStore.deleteItemAsync(GOOGLE_SUCCESS_KEY).catch(() => undefined);
  await SecureStore.deleteItemAsync(DEVICE_SUCCESS_KEY).catch(() => undefined);
  await SecureStore.deleteItemAsync('calendar.lastSyncMs').catch(() => undefined); // legacy, pre-split
}

/**
 * Two independent busy sources for the next 14 days, each replacing its own server-side set:
 * Google freebusy (`source='google'`) and the device OS calendar (`source='device'`, which already
 * aggregates the user's accounts — work included). They are posted in SEPARATE PUTs so a failure of
 * one never deletes the other's blocks. Intervals go up raw and un-merged: unioning/deduplicating a
 * block that appears in both sources is the server engine's job (no client-side interval algebra).
 *
 * `force` has a fixed set of permitted callers — the Settings "Sync now" button, a successful
 * `ensureScope()`, the moment a couple first pairs, the Settings device-calendar toggle, and
 * pull-to-refresh (which adds its own client cooldown) — each a discrete user action, so none can
 * loop. It must never be passed from a render path, an effect that can re-run, or a retry loop.
 *
 * Ceiling: the Google gate is per *device*, not per user, so a phone plus a tablet gets two automatic
 * calls an hour. Server-side enforcement needs a `last_calendar_sync` column on `users` — that is the
 * upgrade path, and it is also what would stop repeated pair/unpair cycles forcing repeated syncs.
 */
// Serialises work on this device so nothing races the freshness/gate keys: a second sync (auto or
// forced) waits for the in-flight one rather than racing its PUTs or the gate's read/write (#2), and
// clearSyncLimiter's deletes are ordered the same way. Each step is isolated from the previous one's
// result so a rejection can never wedge the chain for the next caller.
let syncChain: Promise<unknown> = Promise.resolve();
function enqueue<T>(step: () => Promise<T>): Promise<T> {
  const run = syncChain.then(step, step);
  syncChain = run.then(
    () => undefined,
    () => undefined,
  );
  return run;
}

export function sync(coupleId: string, opts?: { force?: boolean }): Promise<SyncSummary> {
  return enqueue(() => runSync(coupleId, opts));
}

async function runSync(coupleId: string, opts?: { force?: boolean }): Promise<SyncSummary> {
  const now = Date.now();
  const force = opts?.force ?? false;

  // Mirror the persisted freshness stamps into the store on entry so Settings shows a real "last
  // synced" per source even when this run skips a source. ONLY move a stamp FORWARD: a PUT this run
  // may have updated the store to `now` while its SecureStore persist failed, and reading the older
  // persisted value back would rewind the label.
  const state = useStore.getState();
  const priorGoogle = await readMs(GOOGLE_SUCCESS_KEY);
  const priorDevice = await readMs(DEVICE_SUCCESS_KEY);
  if (priorGoogle !== null && priorGoogle > (state.lastGoogleSyncMs ?? -1)) {
    state.setLastGoogleSync(priorGoogle);
  }
  if (priorDevice !== null && priorDevice > (state.lastDeviceSyncMs ?? -1)) {
    state.setLastDeviceSync(priorDevice);
  }

  // The two sources run as INDEPENDENT concurrent pipelines: a hung/slow Google request must never
  // hold up the device PUT (source independence in time, not just in data). Each pipeline owns its
  // own try/catch, so a failure of one never touches the other, and each records its own freshness.
  const [google, device] = await Promise.all([
    syncGoogle(coupleId, now, force),
    syncDevice(coupleId, now),
  ]);
  return { device, google };
}

/** Google freebusy — the one metered source, so the hourly gate applies to it alone (§5). */
async function syncGoogle(
  coupleId: string,
  now: number,
  force: boolean,
): Promise<SyncSummary['google']> {
  if (!(await reserveGoogle(now, force))) return 'rate-limited';
  const user = await currentGoogleUser();
  if (!user) return 'no-session';
  if (!user.scopes.includes(CALENDAR_SCOPE)) return 'scope-missing';
  let busy: { start_utc: number; end_utc: number }[];
  try {
    // A cached account with no token means getTokens() rejected during recovery — a broken grant that
    // ensureScope() fixes. A thrown token read or a non-401/403 freebusy failure (network/500) fails
    // only the Google source. Only a `force` sync retries a 429/503; an automatic one is one request.
    const accessToken = await getGoogleAccessToken();
    const res = accessToken
      ? await fetchBusy(accessToken, now, now + LOOKAHEAD_MS, force)
      : 'scope-missing';
    if (res === 'scope-missing') return 'scope-missing';
    busy = res;
  } catch {
    return 'failed';
  }
  try {
    await api.putCalendarBlocks(coupleId, busy, 'google');
    await recordSuccess(GOOGLE_SUCCESS_KEY, now, useStore.getState().setLastGoogleSync);
    return 'synced';
  } catch {
    return 'failed';
  }
}

/** Device OS calendar — local + unmetered, so it always runs (never gated). */
async function syncDevice(coupleId: string, now: number): Promise<SyncSummary['device']> {
  // null = native read failure (preserve prior device blocks); [] = denied or genuinely empty (clear).
  const result = await deviceBusy(now, now + LOOKAHEAD_MS).catch(() => null);
  if (result === null) return 'skipped';
  try {
    await api.putCalendarBlocks(coupleId, result, 'device');
    await recordSuccess(DEVICE_SUCCESS_KEY, now, useStore.getState().setLastDeviceSync);
    return result.length === 0 ? 'empty' : 'synced';
  } catch {
    return 'failed';
  }
}

/**
 * Decides whether to spend a metered Google call this run, and — critically — reserves the quota
 * window BEFORE the HTTP request so a crash between reserve and request cannot leak a second call.
 *
 *  - `force` bypasses the gate READ but still stamps the window (best-effort), then proceeds.
 *  - an automatic call is allowed only when the gate is null or ≥ 1h old (`gate <= now` guards a
 *    clock that jumped backwards from wedging auto-sync off).
 *  - fail-closed: if the reservation write throws, the automatic call is SKIPPED. A failed write must
 *    not let Google retry on every foreground; one missed hour is the safe direction to fail.
 */
async function reserveGoogle(now: number, force: boolean): Promise<boolean> {
  if (force) {
    try {
      await SecureStore.setItemAsync(GOOGLE_GATE_KEY, String(now));
    } catch {
      // Ceiling: a lost stamp means the NEXT automatic sync is not suppressed by this forced one.
    }
    return true;
  }
  const gate = await readMs(GOOGLE_GATE_KEY);
  if (gate !== null && gate <= now && now - gate < HOUR_MS) return false;
  try {
    await SecureStore.setItemAsync(GOOGLE_GATE_KEY, String(now));
  } catch {
    return false; // fail-closed
  }
  return true;
}

async function recordSuccess(key: string, now: number, mirror: (ms: number) => void): Promise<void> {
  mirror(now);
  try {
    await SecureStore.setItemAsync(key, String(now));
  } catch {
    // Ceiling: a lost freshness stamp only makes Settings say "never synced" after a relaunch; the
    // gate above is what protects the quota, so this is cosmetic.
  }
}

async function fetchBusy(
  accessToken: string,
  fromMs: number,
  toMs: number,
  retry: boolean,
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
    // Only a forced sync retries: an AUTOMATIC call is exactly one request (§5), so a 429/503 there
    // falls straight through to the throw below and fails just the Google source for this run.
    if (retry && (res.status === 429 || res.status === 503) && attempt < RETRY_DELAYS_MS.length) {
      await sleep(RETRY_DELAYS_MS[attempt] ?? 1000);
      continue;
    }
    if (!res.ok) throw new Error(`freebusy_${res.status}`);
    const body = (await res.json()) as FreeBusyResponse;
    // A 200 can still carry a per-calendar error (rate limit, notFound, insufficient scope). Treat it
    // as a failed read — NOT an empty result — so the caller skips the PUT rather than replacing the
    // stored Google set with [] and deleting every previously-synced block.
    if (body.calendars?.['primary']?.errors?.length) return 'scope-missing';
    return intervals(body);
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
