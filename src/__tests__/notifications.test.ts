import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { RemoteMessage } from '@react-native-firebase/messaging';

import type { UserRow } from '../../backend/src/wire';

const mocks = vi.hoisted(() => ({
  /** Ordered log: the sign-out sequence is the point of one of these tests. */
  calls: [] as string[],
  requestPermissionsAsync: vi.fn(),
  scheduleNotificationAsync: vi.fn(),
  setNotificationHandler: vi.fn(),
  addNotificationResponseReceivedListener: vi.fn(),
  navigate: vi.fn(),
  getToken: vi.fn<() => Promise<string>>(),
  onTokenRefresh: vi.fn(),
  onMessage: vi.fn(),
  onNotificationOpenedApp: vi.fn(),
  getInitialNotification: vi.fn(),
  registerFcmToken: vi.fn<(token: string) => Promise<void>>(),
  responseRemove: vi.fn(),
  openedRemove: vi.fn(),
}));

vi.mock('@react-native-firebase/messaging', () => ({
  getMessaging: () => ({ app: 'test' }),
  getToken: mocks.getToken,
  onTokenRefresh: mocks.onTokenRefresh,
  onMessage: mocks.onMessage,
  onNotificationOpenedApp: mocks.onNotificationOpenedApp,
  getInitialNotification: mocks.getInitialNotification,
}));

vi.mock('expo-notifications', () => ({
  setNotificationHandler: mocks.setNotificationHandler,
  requestPermissionsAsync: mocks.requestPermissionsAsync,
  scheduleNotificationAsync: mocks.scheduleNotificationAsync,
  addNotificationResponseReceivedListener: mocks.addNotificationResponseReceivedListener,
}));

vi.mock('expo-router', () => ({ router: { navigate: mocks.navigate } }));

vi.mock('../api', () => ({
  api: {
    registerFcmToken: mocks.registerFcmToken,
    deleteFcmToken: async () => {
      mocks.calls.push('deleteFcmToken');
    },
  },
}));

// src/auth.ts is the real module — the sign-out ORDER is what is under test — so its own native
// dependencies are stubbed, each logging the step it represents.
vi.mock('expo-constants', () => ({
  default: { expoConfig: { extra: { googleWebClientId: 'web-client-id' } } },
}));
vi.mock('@react-native-firebase/auth', () => ({
  getAuth: () => ({ currentUser: null }),
  GoogleAuthProvider: { credential: () => ({}) },
  onAuthStateChanged: () => () => undefined,
  signInWithCredential: async () => undefined,
  signOut: async () => {
    mocks.calls.push('firebaseSignOut');
  },
}));
vi.mock('@react-native-google-signin/google-signin', () => ({
  GoogleSignin: {
    configure: vi.fn(),
    signIn: vi.fn(),
    getTokens: vi.fn(),
    signOut: async () => {
      mocks.calls.push('googleSignOut');
    },
  },
}));
vi.mock('../ws', () => ({ connect: vi.fn(), disconnect: vi.fn() }));

/** The module-level "listeners already attached" flag has to be fresh per test. */
async function setup() {
  vi.resetModules();
  return await import('../notifications');
}

function userRow(): UserRow {
  return {
    uid: 'u1',
    email: 'a@example.com',
    display_name: 'A',
    photo_url: null,
    timezone: 'Europe/Berlin',
    couple_id: 'c1',
    show_late_night_windows: false,
    notifications_enabled: true,
    fcm_tokens: ['device-token'],
    created_at: 0,
  };
}

beforeEach(() => {
  mocks.calls.length = 0;
  mocks.requestPermissionsAsync.mockReset().mockResolvedValue({ granted: true });
  mocks.scheduleNotificationAsync.mockReset().mockResolvedValue('local-id');
  mocks.setNotificationHandler.mockReset();
  mocks.addNotificationResponseReceivedListener
    .mockReset()
    .mockReturnValue({ remove: mocks.responseRemove });
  mocks.navigate.mockReset();
  mocks.getToken.mockReset().mockResolvedValue('device-token');
  mocks.onTokenRefresh.mockReset().mockReturnValue(() => undefined);
  mocks.onMessage.mockReset().mockReturnValue(() => undefined);
  mocks.onNotificationOpenedApp.mockReset().mockReturnValue(mocks.openedRemove);
  mocks.getInitialNotification.mockReset().mockResolvedValue(null);
  mocks.registerFcmToken.mockReset().mockResolvedValue(undefined);
  mocks.responseRemove.mockReset();
  mocks.openedRemove.mockReset();
});

describe('requestPermissionAndRegister', () => {
  it('registers the token after permission is granted', async () => {
    const { requestPermissionAndRegister } = await setup();

    await requestPermissionAndRegister();

    expect(mocks.registerFcmToken).toHaveBeenCalledExactlyOnceWith('device-token');
  });

  it('registers nothing when permission is refused', async () => {
    const { requestPermissionAndRegister } = await setup();
    mocks.requestPermissionsAsync.mockResolvedValue({ granted: false });

    await requestPermissionAndRegister();

    expect(mocks.registerFcmToken).not.toHaveBeenCalled();
    expect(mocks.getToken).not.toHaveBeenCalled();
  });

  it('re-registers on onTokenRefresh', async () => {
    const { requestPermissionAndRegister } = await setup();
    let refreshed: ((token: string) => void) | undefined;
    mocks.onTokenRefresh.mockImplementation((_messaging: unknown, cb: (t: string) => void) => {
      refreshed = cb;
      return () => undefined;
    });

    await requestPermissionAndRegister();
    refreshed?.('rotated-token');

    expect(mocks.registerFcmToken).toHaveBeenCalledWith('rotated-token');
    expect(mocks.registerFcmToken).toHaveBeenCalledTimes(2);
  });

  it('actually invokes the display API for a foreground message', async () => {
    const { requestPermissionAndRegister } = await setup();
    let received: ((m: RemoteMessage) => Promise<void>) | undefined;
    mocks.onMessage.mockImplementation(
      (_messaging: unknown, cb: (m: RemoteMessage) => Promise<void>) => {
        received = cb;
        return () => undefined;
      },
    );

    await requestPermissionAndRegister();
    await received?.({
      notification: { title: 'New free time together', body: '3 windows — next Tue 5 Aug, 19:00' },
      data: { type: 'overlap' },
      fcmOptions: {},
    });

    // The display call itself, not "a function was called": a foreground FCM message is never shown
    // by the OS, so without this the push is silently dead.
    expect(mocks.scheduleNotificationAsync).toHaveBeenCalledExactlyOnceWith({
      content: {
        title: 'New free time together',
        body: '3 windows — next Tue 5 Aug, 19:00',
        data: { type: 'overlap' },
      },
      trigger: null,
    });
    // And the handler that permits the display at all — Expo's default is to drop it.
    expect(mocks.setNotificationHandler).toHaveBeenCalledOnce();
    const behaviour = await mocks.setNotificationHandler.mock.calls[0]?.[0].handleNotification();
    expect(behaviour.shouldShowBanner).toBe(true);
  });

  it('attaches its lifetime listeners once, however often it is called', async () => {
    const { requestPermissionAndRegister } = await setup();

    await requestPermissionAndRegister();
    await requestPermissionAndRegister();

    expect(mocks.onTokenRefresh).toHaveBeenCalledOnce();
    expect(mocks.onMessage).toHaveBeenCalledOnce();
  });
});

describe('sign-out', () => {
  it('deletes the token server-side on sign-out, before clearing auth', async () => {
    await setup();
    const { signOut } = await import('../auth');
    const { useStore } = await import('../store');
    useStore.setState({ user: userRow() });

    await signOut();

    // DELETE /auth/fcm-token needs the Firebase ID token that sign-out is about to invalidate, so the
    // order is the requirement: a shared handset must not keep the previous user's pushes.
    expect(mocks.calls).toEqual(['deleteFcmToken', 'googleSignOut', 'firebaseSignOut']);
    expect(useStore.getState().user).toBeNull();
  });

  it('still signs out when the token deletion fails', async () => {
    await setup();
    const { signOut } = await import('../auth');
    const { useStore } = await import('../store');
    useStore.setState({ user: userRow() });
    mocks.getToken.mockRejectedValue(new Error('no token'));

    await expect(signOut()).resolves.toBeUndefined();

    expect(useStore.getState().user).toBeNull();
  });
});

describe('attachTapHandler', () => {
  it('routes a notification tap to the Free time tab, not a nonexistent /overlap route', async () => {
    const { attachTapHandler } = await setup();
    let opened: ((m: RemoteMessage) => void) | undefined;
    mocks.onNotificationOpenedApp.mockImplementation(
      (_messaging: unknown, cb: (m: RemoteMessage) => void) => {
        opened = cb;
        return mocks.openedRemove;
      },
    );

    attachTapHandler();
    opened?.({ data: { type: 'overlap' }, fcmOptions: {} });

    expect(mocks.navigate).toHaveBeenCalledWith('/(tabs)');
    expect(mocks.navigate).not.toHaveBeenCalledWith(expect.stringContaining('overlap'));
  });

  it('routes a tap on a notification we displayed ourselves', async () => {
    const { attachTapHandler } = await setup();
    let responded: (() => void) | undefined;
    mocks.addNotificationResponseReceivedListener.mockImplementation((cb: () => void) => {
      responded = cb;
      return { remove: mocks.responseRemove };
    });

    attachTapHandler();
    responded?.();

    // The foreground tap goes to expo-notifications, not to FCM, so both listeners are needed.
    expect(mocks.navigate).toHaveBeenCalledWith('/(tabs)');
  });

  it('routes a cold start launched from a tap', async () => {
    const { attachTapHandler } = await setup();
    mocks.getInitialNotification.mockResolvedValue({ data: { type: 'overlap' } });

    attachTapHandler();
    await vi.waitFor(() => expect(mocks.navigate).toHaveBeenCalledWith('/(tabs)'));
  });

  it('removes both listeners on cleanup', async () => {
    const { attachTapHandler } = await setup();

    attachTapHandler()();

    expect(mocks.openedRemove).toHaveBeenCalledOnce();
    expect(mocks.responseRemove).toHaveBeenCalledOnce();
  });
});
