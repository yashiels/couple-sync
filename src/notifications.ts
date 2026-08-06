import {
  getInitialNotification,
  getMessaging,
  getToken,
  onMessage,
  onNotificationOpenedApp,
  onTokenRefresh,
} from '@react-native-firebase/messaging';
import * as Notifications from 'expo-notifications';
import { router } from 'expo-router';

import { api } from './api';

/**
 * FCM: permission, token registration, foreground display, and tap routing (§6).
 *
 * Ceiling: expo-notifications and @react-native-firebase/messaging both register an Android
 * `FirebaseMessagingService`, and only one of them wins in the merged manifest. RNFirebase is the one
 * declared by its own plugin and the one this module listens on; if a device walk ever shows a
 * duplicated banner or a dead `onMessage`, the upgrade path is to drop expo-notifications and display
 * with notifee instead.
 */

// Expo's default is NOT to display an incoming notification, so a foreground push would be silently
// dropped without this handler. That is precisely the defect the previous build shipped.
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

/** Lifetime subscriptions, attached once: a retried hydration must not double-register the token. */
let lifetimeListenersAttached = false;

/**
 * Called once per launch from `app/_layout.tsx`, after hydration. Permission comes from
 * expo-notifications, not `messaging().requestPermission()`: the latter is deprecated and a no-op on
 * Android, so Android 13+'s POST_NOTIFICATIONS would never actually be requested.
 */
export async function requestPermissionAndRegister(): Promise<void> {
  const { granted } = await Notifications.requestPermissionsAsync();
  if (!granted) return;

  const messaging = getMessaging();
  await api.registerFcmToken(await getToken(messaging));

  if (lifetimeListenersAttached) return;
  lifetimeListenersAttached = true;

  // A rotated token is just a new registration: the server dedups, and the old one is pruned when it
  // starts failing (backend/src/push.ts).
  onTokenRefresh(messaging, (token) => {
    void api.registerFcmToken(token).catch(() => undefined);
  });

  onMessage(messaging, async (message) => {
    const { title, body } = message.notification ?? {};
    if (!title && !body) return;
    await Notifications.scheduleNotificationAsync({
      // The payload carries a routing hint and nothing else (backend/src/push.ts), so there is no
      // block title here to put on a lock screen.
      content: { title: title ?? 'Couple Sync', body: body ?? '', data: message.data ?? {} },
      trigger: null,
    });
  });
}

/**
 * Called on sign-out BEFORE the local auth is cleared — `api.deleteFcmToken` needs the Firebase ID
 * token that sign-out is about to invalidate. Without this, one handset stays attached to the previous
 * user's row: sign out, sign in as the partner, and that phone receives pushes meant for someone else.
 */
export async function unregisterFcmToken(): Promise<void> {
  try {
    await api.deleteFcmToken(await getToken(getMessaging()));
  } catch {
    // Best effort: an offline sign-out must still sign out. Ceiling — a failure here leaves the stale
    // token on the old row until a send hard-fails; pruning it server-side when the same token turns
    // up under a different uid is the upgrade path.
  }
}

/** Routes a tap to the Free time tab. NOT `/overlap` — that route no longer exists. */
export function attachTapHandler(): () => void {
  const messaging = getMessaging();

  // Tapped while backgrounded: the OS displayed it, so FCM reports the tap.
  const offOpened = onNotificationOpenedApp(messaging, () => openFreeTime());
  // Tapped while foregrounded: we displayed it ourselves above, so expo-notifications reports it.
  const responseSub = Notifications.addNotificationResponseReceivedListener(() => openFreeTime());
  // Launched from a tap while killed. Ceiling: this can fire before the guard chain has admitted
  // (tabs) and the navigation is then dropped — harmless, because (tabs) is where a paired user lands
  // anyway. Making it exact would mean parking the intent in the store like the invite deep link does.
  void getInitialNotification(messaging).then((message) => {
    if (message) openFreeTime();
  });

  return () => {
    offOpened();
    responseSub.remove();
  };
}

function openFreeTime(): void {
  // navigate, not push: a tap must not stack a second copy of the tab layout.
  router.navigate('/(tabs)');
}
