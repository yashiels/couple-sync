import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar.readonly';
const FREEBUSY_URL = 'https://www.googleapis.com/calendar/v3/freeBusy';
const HOUR_MS = 60 * 60 * 1000;
const NOW = Date.UTC(2026, 7, 4, 12, 0, 0);

const mocks = vi.hoisted(() => ({
  /** A real map, so "the timestamp survives a launch" is an actual property of these tests. */
  keychain: new Map<string, string>(),
  /** Keys whose SecureStore write should throw — drives the fail-closed reservation test. */
  throwOnSet: new Set<string>(),
  /** Ordered log of the native calls whose sequence matters. */
  calls: [] as string[],
  getCurrentUser: vi.fn<() => { scopes: string[] } | null>(),
  hasPreviousSignIn: vi.fn<() => boolean>(),
  signInSilently: vi.fn(),
  addScopes: vi.fn(),
  getGoogleAccessToken: vi.fn<() => Promise<string | null>>(),
  putCalendarBlocks: vi.fn<
    (
      coupleId: string,
      intervals: { start_utc: number; end_utc: number }[],
      source: 'google' | 'device',
    ) => Promise<number>
  >(),
  deviceBusy: vi.fn<
    (from: number, to: number) => Promise<{ start_utc: number; end_utc: number }[] | null>
  >(),
}));

vi.mock('@react-native-google-signin/google-signin', () => ({
  GoogleSignin: {
    getCurrentUser: mocks.getCurrentUser,
    hasPreviousSignIn: mocks.hasPreviousSignIn,
    signInSilently: async () => {
      mocks.calls.push('signInSilently');
      return mocks.signInSilently();
    },
    addScopes: mocks.addScopes,
  },
}));

vi.mock('expo-secure-store', () => ({
  getItemAsync: async (key: string) => mocks.keychain.get(key) ?? null,
  setItemAsync: async (key: string, value: string) => {
    if (mocks.throwOnSet.has(key)) throw new Error('keystore write failed');
    mocks.keychain.set(key, value);
  },
  deleteItemAsync: async (key: string) => {
    mocks.keychain.delete(key);
  },
}));

// src/auth.ts is stubbed: this module's contract with it is exactly two symbols, and the real one
// reaches Firebase, the Google client and expo-constants.
vi.mock('../auth', () => ({
  CALENDAR_SCOPE,
  getGoogleAccessToken: async () => {
    mocks.calls.push('getTokens');
    return mocks.getGoogleAccessToken();
  },
  // Present so the "not the Firebase ID token" assertion has something to be wrong about.
  getIdToken: async () => 'FIREBASE-ID-TOKEN',
}));

vi.mock('../api', () => ({ api: { putCalendarBlocks: mocks.putCalendarBlocks } }));

// Device calendar is stubbed (the real module pulls expo-calendar, a native module). Controllable per
// test; defaults to null in beforeEach = "device not read", so runSync skips the device PUT and only
// the Google source is posted — those assertions are exactly the Google result (device: 'skipped').
vi.mock('../deviceCalendar', () => ({ deviceBusy: mocks.deviceBusy }));

const fetchMock = vi.fn();

function freeBusyOk(busy: { start: string; end: string }[] = []) {
  return { ok: true, status: 200, json: async () => ({ calendars: { primary: { busy } } }) };
}

/** The request body of the nth freebusy call. */
function requestBody(call = 0): { timeMin: string; timeMax: string; items: { id: string }[] } {
  return JSON.parse(fetchMock.mock.calls[call]?.[1].body as string);
}

function requestHeaders(call = 0): Record<string, string> {
  return fetchMock.mock.calls[call]?.[1].headers as Record<string, string>;
}

async function setup() {
  vi.resetModules();
  return await import('../calendar');
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
  mocks.keychain.clear();
  mocks.throwOnSet.clear();
  mocks.calls.length = 0;
  mocks.getCurrentUser.mockReset().mockReturnValue({ scopes: [CALENDAR_SCOPE] });
  mocks.hasPreviousSignIn.mockReset().mockReturnValue(true);
  mocks.signInSilently
    .mockReset()
    .mockResolvedValue({ type: 'success', data: { scopes: [CALENDAR_SCOPE] } });
  mocks.addScopes.mockReset().mockResolvedValue({ type: 'success', data: {} });
  mocks.getGoogleAccessToken.mockReset().mockResolvedValue('GOOGLE-ACCESS-TOKEN');
  mocks.putCalendarBlocks.mockReset().mockResolvedValue(0);
  mocks.deviceBusy.mockReset().mockResolvedValue(null); // default: device not read → only Google posts
  fetchMock.mockReset().mockResolvedValue(freeBusyOk());
  vi.stubGlobal('fetch', fetchMock);
});

afterEach(() => {
  vi.useRealTimers();
});

describe('the Google session', () => {
  it('restores the Google session on cold start before requesting tokens', async () => {
    const { sync } = await setup();
    mocks.getCurrentUser.mockReturnValue(null); // cached account, no live session

    expect((await sync('c1')).google).toBe('synced');

    expect(mocks.calls).toEqual(['signInSilently', 'getTokens']);
  });

  it('returns no-session when there is no cached Google account', async () => {
    const { sync } = await setup();
    mocks.getCurrentUser.mockReturnValue(null);
    mocks.hasPreviousSignIn.mockReturnValue(false);

    expect((await sync('c1')).google).toBe('no-session');

    expect(mocks.calls).toEqual([]); // getTokens would REJECT here — it must never be reached
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('returns no-session rather than throwing when signInSilently rejects', async () => {
    const { sync } = await setup();
    mocks.getCurrentUser.mockReturnValue(null);
    mocks.signInSilently.mockRejectedValue(new Error('RNGoogleSignin: token recovery failed'));

    expect((await sync('c1')).google).toBe('no-session');
  });
});

describe('the calendar scope', () => {
  it('returns scope-missing when the calendar scope was declined at sign-in', async () => {
    const { sync } = await setup();
    // Sign-in completed; Google's own identity scopes are there, ours is not.
    mocks.getCurrentUser.mockReturnValue({ scopes: ['openid', 'email', 'profile'] });

    expect((await sync('c1')).google).toBe('scope-missing');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('returns scope-missing when the scope was revoked after having been granted', async () => {
    const { sync } = await setup();
    // The cached account still lists the scope; Google answers 403 because it was revoked server-side.
    fetchMock.mockResolvedValue({ ok: false, status: 403 });

    expect((await sync('c1')).google).toBe('scope-missing');
    expect(mocks.putCalendarBlocks).not.toHaveBeenCalled();
  });

  it('returns scope-missing rather than leaking a native error when getTokens() rejects', async () => {
    const { sync } = await setup();
    // getGoogleAccessToken swallows the native rejection into null; a crash here is the bug.
    mocks.getGoogleAccessToken.mockResolvedValue(null);

    expect((await sync('c1')).google).toBe('scope-missing');
  });

  it('reports the grant without touching the API', async () => {
    const { hasCalendarScope } = await setup();

    await expect(hasCalendarScope()).resolves.toBe(true);
    mocks.getCurrentUser.mockReturnValue({ scopes: ['email'] });
    await expect(hasCalendarScope()).resolves.toBe(false);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('asks for the calendar scope as an OBJECT, and reports a cancellation as false', async () => {
    const { ensureScope } = await setup();

    await expect(ensureScope()).resolves.toBe(true);
    expect(mocks.addScopes).toHaveBeenCalledWith({ scopes: [CALENDAR_SCOPE] });

    mocks.addScopes.mockResolvedValue({ type: 'cancelled' });
    await expect(ensureScope()).resolves.toBe(false);

    mocks.addScopes.mockRejectedValue(new Error('native'));
    await expect(ensureScope()).resolves.toBe(false);
  });
});

describe('the freebusy request', () => {
  it('authorizes the Calendar request with the Google access token, NOT the Firebase ID token', async () => {
    const { sync } = await setup();

    await sync('c1');

    expect(requestHeaders()['Authorization']).toBe('Bearer GOOGLE-ACCESS-TOKEN');
    expect(JSON.stringify(fetchMock.mock.calls)).not.toContain('FIREBASE-ID-TOKEN');
  });

  it('calls freeBusy.query and never events.list', async () => {
    const { sync } = await setup();

    await sync('c1');

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0]?.[0]).toBe(FREEBUSY_URL);
    // Not "the server rejects titles" — the client must never have ASKED for one.
    expect(JSON.stringify(fetchMock.mock.calls)).not.toMatch(/events|summary/i);
  });

  it('queries only the primary calendar', async () => {
    const { sync } = await setup();

    await sync('c1');

    expect(requestBody().items).toEqual([{ id: 'primary' }]);
  });

  it('sends timeMin/timeMax as RFC3339 strings', async () => {
    const { sync } = await setup();

    await sync('c1');

    const { timeMin, timeMax } = requestBody();
    // The documented §5 carve-out: everything else on the wire is epoch ms.
    expect(timeMin).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/);
    expect(timeMax).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/);
    expect(Date.parse(timeMin)).toBe(NOW);
    expect(Date.parse(timeMax) - Date.parse(timeMin)).toBe(14 * 24 * HOUR_MS);
  });

  it('sends no title field in the PUT /blocks/google payload', async () => {
    const { sync } = await setup();
    fetchMock.mockResolvedValue(
      freeBusyOk([{ start: '2026-08-04T14:00:00Z', end: '2026-08-04T15:30:00Z' }]),
    );

    await sync('c1');

    expect(mocks.putCalendarBlocks).toHaveBeenCalledWith(
      'c1',
      [
        // Epoch ms on the way back in, and exactly two keys — no title, category or summary.
        { start_utc: Date.UTC(2026, 7, 4, 14), end_utc: Date.UTC(2026, 7, 4, 15, 30) },
      ],
      'google',
    );
    const [, intervals] = mocks.putCalendarBlocks.mock.calls[0]!;
    expect(Object.keys(intervals[0]!).sort()).toEqual(['end_utc', 'start_utc']);
  });

  it('drops a malformed or zero-length interval instead of failing the whole batch', async () => {
    const { sync } = await setup();
    fetchMock.mockResolvedValue(
      freeBusyOk([
        { start: 'not-a-date', end: '2026-08-04T15:00:00Z' },
        { start: '2026-08-04T16:00:00Z', end: '2026-08-04T16:00:00Z' },
        { start: '2026-08-04T17:00:00Z', end: '2026-08-04T18:00:00Z' },
      ]),
    );

    await sync('c1');

    expect(mocks.putCalendarBlocks).toHaveBeenCalledWith(
      'c1',
      [{ start_utc: Date.UTC(2026, 7, 4, 17), end_utc: Date.UTC(2026, 7, 4, 18) }],
      'google',
    );
  });

  it('a forced sync backs off and retries a 429 rather than failing', async () => {
    const { sync } = await setup();
    fetchMock.mockResolvedValueOnce({ ok: false, status: 429 }).mockResolvedValueOnce(freeBusyOk());

    const promise = sync('c1', { force: true });
    await vi.advanceTimersByTimeAsync(1000);

    expect((await promise).google).toBe('synced');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('an AUTOMATIC sync makes exactly one request and does not retry a 429', async () => {
    const { sync } = await setup();
    fetchMock.mockResolvedValueOnce({ ok: false, status: 429 }).mockResolvedValue(freeBusyOk());

    // One request, no backoff: the 429 fails just the Google source for this run (§5).
    expect((await sync('c1')).google).toBe('failed');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

describe('the Google hourly gate', () => {
  it('within the hour, an automatic sync skips Google but still PUTs the device source', async () => {
    const { sync } = await setup();
    mocks.deviceBusy.mockResolvedValue([{ start_utc: NOW, end_utc: NOW + HOUR_MS }]);
    await sync('c1'); // opens the gate (and posts both sources)
    fetchMock.mockClear();
    mocks.putCalendarBlocks.mockClear();

    vi.setSystemTime(NOW + 30 * 60 * 1000);
    const summary = await sync('c1');

    expect(summary).toEqual({ device: 'synced', google: 'rate-limited' });
    expect(fetchMock).not.toHaveBeenCalled(); // no metered Google call
    // The device source is local + unmetered, so it still refreshes on this run.
    expect(mocks.putCalendarBlocks).toHaveBeenCalledWith(
      'c1',
      [{ start_utc: NOW, end_utc: NOW + HOUR_MS }],
      'device',
    );
    expect(mocks.putCalendarBlocks).not.toHaveBeenCalledWith('c1', expect.anything(), 'google');
  });

  it('calls Google when the gate is 90 minutes old', async () => {
    const { sync } = await setup();
    await sync('c1');
    fetchMock.mockClear();

    vi.setSystemTime(NOW + 90 * 60 * 1000);
    expect((await sync('c1')).google).toBe('synced');

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('calls Google regardless of the gate when force is true', async () => {
    const { sync } = await setup();
    await sync('c1');
    fetchMock.mockClear();

    vi.setSystemTime(NOW + 60_000);
    expect((await sync('c1', { force: true })).google).toBe('synced');

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('fail-closed: skips the automatic Google request when the reservation write throws', async () => {
    const { sync } = await setup();
    // The gate reservation is written BEFORE the request; a keystore write failure must skip the call,
    // not fall through to it — otherwise a broken keystore would let Google run on every foreground.
    mocks.throwOnSet.add('calendar.googleGateMs');

    const summary = await sync('c1');

    expect(summary.google).toBe('rate-limited');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('survives a relaunch — the gate is persisted, not a module variable', async () => {
    const first = await setup();
    await first.sync('c1');

    // A fresh module registry is what an app launch looks like. A module-level timestamp would be
    // gone here, and auto-sync (which runs at exactly this moment) would call Google again.
    const second = await setup();
    vi.setSystemTime(NOW + 60_000);
    expect((await second.sync('c1')).google).toBe('rate-limited');
  });

  it('survives clearSyncLimiter — a re-pair re-syncs via force, not by bypassing the hourly gate', async () => {
    const { sync, clearSyncLimiter } = await setup();
    await sync('c1'); // stamps the device-wide Google gate
    fetchMock.mockClear();

    clearSyncLimiter();
    await vi.advanceTimersByTimeAsync(0); // the deletes are fire-and-forget
    vi.setSystemTime(NOW + 60_000);

    // The gate is device-wide and MUST persist across sign-out/in and unpair (REBUILD-SPEC §5), so an
    // automatic sync within the hour is still rate-limited and makes no Google request.
    expect((await sync('c2')).google).toBe('rate-limited');
    expect(fetchMock).not.toHaveBeenCalled();

    // First-pair is a `force` caller, which is the intended way a re-paired couple repopulates.
    expect((await sync('c2', { force: true })).google).toBe('synced');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('clearSyncLimiter clears the freshness stamps and the legacy key but KEEPS the Google gate', async () => {
    const { sync, clearSyncLimiter } = await setup();
    mocks.deviceBusy.mockResolvedValue([]); // device read ok → a device success stamp is written too
    mocks.keychain.set('calendar.lastSyncMs', String(NOW)); // simulate a pre-split install's orphan key
    await sync('c1');
    expect(mocks.keychain.has('calendar.googleGateMs')).toBe(true);

    clearSyncLimiter();
    await vi.advanceTimersByTimeAsync(0);

    expect(mocks.keychain.has('calendar.googleGateMs')).toBe(true); // device-wide gate survives (§5)
    expect(mocks.keychain.has('calendar.googleSuccessMs')).toBe(false);
    expect(mocks.keychain.has('calendar.deviceSuccessMs')).toBe(false);
    expect(mocks.keychain.has('calendar.lastSyncMs')).toBe(false); // legacy orphan swept
  });

  it('mirrors the persisted Google freshness into the store even when rate-limited', async () => {
    const { sync } = await setup();
    await sync('c1');

    // A fresh registry, so the store starts at null exactly as it does on a real launch.
    const relaunched = await setup();
    const { useStore } = await import('../store');
    expect(useStore.getState().lastGoogleSyncMs).toBeNull();
    vi.setSystemTime(NOW + 60_000);
    await relaunched.sync('c1');

    // Settings shows a real "last synced" instead of "never" after a rate-limited launch.
    expect(useStore.getState().lastGoogleSyncMs).toBe(NOW);
  });

  it('does not wedge auto-sync off when the device clock jumped backwards', async () => {
    const { sync } = await setup();
    await sync('c1');
    fetchMock.mockClear();

    vi.setSystemTime(NOW - 5 * 24 * HOUR_MS); // stored gate is now in the "future"
    expect((await sync('c1')).google).toBe('synced');
  });
});

describe('the two sources are isolated', () => {
  it('still posts device blocks when the Google read throws', async () => {
    const { sync } = await setup();
    fetchMock.mockResolvedValue({ ok: false, status: 500 }); // fetchBusy throws — a transient failure
    mocks.deviceBusy.mockResolvedValue([{ start_utc: NOW, end_utc: NOW + HOUR_MS }]);

    const summary = await sync('c1', { force: true });
    expect(summary).toEqual({ device: 'synced', google: 'failed' });
    expect(mocks.putCalendarBlocks).toHaveBeenCalledWith(
      'c1',
      [{ start_utc: NOW, end_utc: NOW + HOUR_MS }],
      'device',
    );
    // Google produced nothing to write, so its source is left untouched — never posted empty.
    expect(mocks.putCalendarBlocks).not.toHaveBeenCalledWith('c1', expect.anything(), 'google');
  });

  it('reports a failed device write per-source without masking the Google reason', async () => {
    const { sync } = await setup();
    mocks.getCurrentUser.mockReturnValue({ scopes: ['email'] }); // no calendar scope
    mocks.deviceBusy.mockResolvedValue([]); // device read ok → device PUT attempted...
    mocks.putCalendarBlocks.mockRejectedValue(new Error('network')); // ...and fails

    // No throw: each source carries its own outcome in the summary.
    const summary = await sync('c1', { force: true });
    expect(summary).toEqual({ device: 'failed', google: 'scope-missing' });
  });

  it('reports an empty device read as device: empty and records its freshness', async () => {
    const { sync } = await setup();
    mocks.deviceBusy.mockResolvedValue([]); // read ok, nothing busy
    const { useStore } = await import('../store');

    const summary = await sync('c1');

    expect(summary).toEqual({ device: 'empty', google: 'synced' });
    expect(mocks.putCalendarBlocks).toHaveBeenCalledWith('c1', [], 'device');
    expect(useStore.getState().lastDeviceSyncMs).toBe(NOW);
  });

  it('reports a null device read as device: skipped and does not PUT the device source', async () => {
    const { sync } = await setup();
    mocks.deviceBusy.mockResolvedValue(null); // native read failure

    const summary = await sync('c1');

    expect(summary).toEqual({ device: 'skipped', google: 'synced' });
    expect(mocks.putCalendarBlocks).not.toHaveBeenCalledWith('c1', expect.anything(), 'device');
  });
});
