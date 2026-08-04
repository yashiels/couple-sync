import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { CoupleRow, UserRow } from '../../backend/src/wire';

const mocks = vi.hoisted(() => ({
  me: vi.fn<() => Promise<UserRow>>(),
  getCouple: vi.fn<() => Promise<CoupleRow>>(),
  getUser: vi.fn<() => Promise<Omit<UserRow, 'fcm_tokens'>>>(),
  latestOverlap: vi.fn<() => Promise<{ windows: []; computed_at: number }>>(),
  disconnect: vi.fn(),
  /** Mutable so the fail-fast test can empty it without unmocking (the real module needs RN). */
  extra: { googleWebClientId: 'web-client-id' } as Record<string, string>,
}));

// Every native dependency of src/auth.ts is stubbed; these tests are about hydrateFromServer, which
// is the part with rules in it.
vi.mock('expo-constants', () => ({
  default: {
    expoConfig: {
      get extra() {
        return mocks.extra;
      },
    },
  },
}));
vi.mock('@react-native-firebase/auth', () => ({
  getAuth: () => ({ currentUser: null }),
  GoogleAuthProvider: { credential: () => ({}) },
  onAuthStateChanged: () => () => undefined,
  signInWithCredential: async () => undefined,
  signOut: async () => undefined,
}));
vi.mock('@react-native-google-signin/google-signin', () => ({
  GoogleSignin: { configure: vi.fn(), signIn: vi.fn(), signOut: vi.fn(), getTokens: vi.fn() },
}));
vi.mock('../ws', () => ({ connect: vi.fn(), disconnect: mocks.disconnect }));
vi.mock('../api', () => ({
  api: {
    me: mocks.me,
    getCouple: mocks.getCouple,
    getUser: mocks.getUser,
    latestOverlap: mocks.latestOverlap,
  },
}));

function userRow(overrides: Partial<UserRow> = {}): UserRow {
  return {
    uid: 'u1',
    email: 'a@example.com',
    display_name: 'A',
    photo_url: null,
    timezone: 'Europe/Berlin',
    couple_id: null,
    show_late_night_windows: false,
    notifications_enabled: true,
    fcm_tokens: [],
    created_at: 0,
    ...overrides,
  };
}

const couple: CoupleRow = {
  id: 'c1',
  user_a_uid: 'u2', // the inviter is A, so the partner is the *a* side here
  user_b_uid: 'u1',
  status: 'active',
  paired_at: 0,
  created_at: 0,
};

/** Module state (the single-flight promise and the sentinel) has to be fresh per test. */
async function setup() {
  vi.resetModules();
  const auth = await import('../auth');
  const { useStore } = await import('../store');
  return { ...auth, useStore };
}

beforeEach(() => {
  mocks.me.mockReset().mockResolvedValue(userRow());
  mocks.getCouple.mockReset().mockResolvedValue(couple);
  mocks.getUser.mockReset().mockResolvedValue(userRow({ uid: 'u2' }));
  mocks.latestOverlap.mockReset().mockResolvedValue({ windows: [], computed_at: 5 });
});

describe('hydrateFromServer', () => {
  it('asks the server first, because the local couple_id can be stale', async () => {
    const { hydrateFromServer, useStore } = await setup();
    useStore.setState({ user: userRow({ couple_id: 'stale' }) });
    mocks.me.mockResolvedValue(userRow({ couple_id: 'c1' }));

    await expect(hydrateFromServer()).resolves.toBe('c1');
    expect(mocks.getCouple).toHaveBeenCalledWith('c1');
    expect(useStore.getState().couple).toEqual(couple);
    expect(useStore.getState().partner?.uid).toBe('u2');
    expect(useStore.getState().computedAt).toBe(5);
  });

  it('does not fetch blocks — only the Calendar tab knows a range', async () => {
    const { hydrateFromServer, useStore } = await setup();
    mocks.me.mockResolvedValue(userRow({ couple_id: 'c1' }));
    await hydrateFromServer();
    expect(useStore.getState().blocks).toEqual([]);
  });

  it('drops couple state when the server says the user is unpaired', async () => {
    const { hydrateFromServer, useStore } = await setup();
    useStore.setState({ user: userRow({ couple_id: 'c1' }), couple, partner: userRow({ uid: 'u2' }) });

    await expect(hydrateFromServer()).resolves.toBeNull();
    expect(useStore.getState().couple).toBeNull();
    expect(useStore.getState().partner).toBeNull();
    expect(useStore.getState().user?.couple_id).toBeNull();
    expect(mocks.getCouple).not.toHaveBeenCalled();
  });

  it('shares one in-flight hydration when called twice concurrently', async () => {
    const { hydrateFromServer } = await setup();
    mocks.me.mockResolvedValue(userRow({ couple_id: 'c1' }));

    const [a, b] = await Promise.all([hydrateFromServer(), hydrateFromServer()]);

    expect(a).toBe('c1');
    expect(b).toBe('c1');
    expect(mocks.me).toHaveBeenCalledTimes(1);
  });

  it('starts a fresh hydration once the previous one has settled', async () => {
    const { hydrateFromServer } = await setup();
    await hydrateFromServer();
    await hydrateFromServer();
    expect(mocks.me).toHaveBeenCalledTimes(2);
  });

  it('selects whichever side of the couple is not you', async () => {
    const { partnerUidOf } = await setup();
    expect(partnerUidOf(couple, 'u1')).toBe('u2');
    expect(partnerUidOf(couple, 'u2')).toBe('u1');
  });
});

describe('first-pair transition', () => {
  it('does not fire on a cold start for an already-paired couple', async () => {
    const { hydrateFromServer, setFirstPairHandler } = await setup();
    const onFirstPair = vi.fn();
    setFirstPairHandler(onFirstPair);
    mocks.me.mockResolvedValue(userRow({ couple_id: 'c1' }));

    await hydrateFromServer(); // local state is null either way — this must not read as a pairing

    expect(onFirstPair).not.toHaveBeenCalled();
  });

  it('fires on the first genuine null -> set transition', async () => {
    const { hydrateFromServer, setFirstPairHandler } = await setup();
    const onFirstPair = vi.fn();
    setFirstPairHandler(onFirstPair);

    await hydrateFromServer(); // cold start, unpaired
    mocks.me.mockResolvedValue(userRow({ couple_id: 'c1' }));
    await hydrateFromServer(); // the invite was redeemed

    expect(onFirstPair).toHaveBeenCalledExactlyOnceWith('c1');
  });

  it('fires exactly ONCE when pairing and hello arrive concurrently', async () => {
    const { hydrateFromServer, setFirstPairHandler } = await setup();
    const onFirstPair = vi.fn();
    setFirstPairHandler(onFirstPair);

    await hydrateFromServer(); // cold start, unpaired
    mocks.me.mockResolvedValue(userRow({ couple_id: 'c1' }));
    await Promise.all([hydrateFromServer(), hydrateFromServer()]);

    expect(onFirstPair).toHaveBeenCalledTimes(1);
  });

  it('does not fire on a reconnect reporting the same couple_id', async () => {
    const { hydrateFromServer, setFirstPairHandler } = await setup();
    const onFirstPair = vi.fn();
    setFirstPairHandler(onFirstPair);
    mocks.me.mockResolvedValue(userRow({ couple_id: 'c1' }));

    await hydrateFromServer(); // cold start, paired
    await hydrateFromServer(); // reconnect
    await hydrateFromServer();

    expect(onFirstPair).not.toHaveBeenCalled();
  });

  it('fires after an unpair and re-pair, because that is a real transition', async () => {
    const { hydrateFromServer, setFirstPairHandler } = await setup();
    const onFirstPair = vi.fn();
    setFirstPairHandler(onFirstPair);
    mocks.me.mockResolvedValue(userRow({ couple_id: 'c1' }));
    await hydrateFromServer();

    mocks.me.mockResolvedValue(userRow({ couple_id: null }));
    await hydrateFromServer(); // unpaired

    mocks.me.mockResolvedValue(userRow({ couple_id: 'c2' }));
    await hydrateFromServer(); // paired again

    expect(onFirstPair).toHaveBeenCalledExactlyOnceWith('c2');
  });
});

describe('configureGoogleSignIn', () => {
  it('requests the calendar scope in the sign-in consent itself', async () => {
    const { configureGoogleSignIn, CALENDAR_SCOPE } = await setup();
    const { GoogleSignin } = await import('@react-native-google-signin/google-signin');

    configureGoogleSignIn();

    expect(GoogleSignin.configure).toHaveBeenCalledWith({
      webClientId: 'web-client-id',
      scopes: [CALENDAR_SCOPE],
    });
  });

  it('fails fast when the web client id is not configured', async () => {
    const { configureGoogleSignIn } = await setup();
    mocks.extra = {};
    try {
      expect(() => configureGoogleSignIn()).toThrow(/GOOGLE_WEB_CLIENT_ID/);
    } finally {
      mocks.extra = { googleWebClientId: 'web-client-id' };
    }
  });
});

describe('signOut', () => {
  it('closes the socket and clears the store', async () => {
    const { signOut, useStore } = await setup();
    useStore.setState({ user: userRow({ couple_id: 'c1' }), couple });

    await signOut();

    expect(mocks.disconnect).toHaveBeenCalled();
    expect(useStore.getState().user).toBeNull();
    expect(useStore.getState().couple).toBeNull();
    // A known-empty state, not an unknown one: the splash must not come back.
    expect(useStore.getState().hydrated).toBe(true);
  });
});
