import * as Linking from 'expo-linking';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';

import { api } from '../src/api';
import {
  configureGoogleSignIn,
  hydrateFromServer,
  onAuthChange,
  setFirstPairHandler,
} from '../src/auth';
import { clearSyncLimiter, sync } from '../src/calendar';
import { attachTapHandler, requestPermissionAndRegister } from '../src/notifications';
import { setPersistedCalendarSyncCleaner, useStore } from '../src/store';
import { fontSize, radius, spacing, touchTarget, useColors } from '../src/theme';
import { connect, disconnect } from '../src/ws';

// At module load, before any sign-in can happen, and deliberately not inside a component: it must
// throw where a missing GOOGLE_WEB_CLIENT_ID is a startup error, not a sign-in that never resolves.
configureGoogleSignIn();

// The two seams src/auth.ts and src/store.ts left for the calendar module, filled at module load so
// no auth event, pairing, or unpair can arrive before them.
//
// A brand-new couple has zero google blocks, and waiting up to an hour to populate them makes the app
// look broken at the exact moment the user first sees it — so this is a permitted `force` caller. It
// fires on a real null -> couple_id transition only, which is why it covers the redeemer's HTTP
// result, the inviter's WS `pairing`, and a reconciling `hello` without firing again on a reconnect.
setFirstPairHandler((coupleId) => {
  void sync(coupleId, { force: true }).catch(() => undefined);
});
setPersistedCalendarSyncCleaner(clearSyncLimiter);

/**
 * Cold start for a signed-in uid. ws.connect() comes FIRST, before anything couple-related: an
 * unpaired inviter needs a live socket or they never receive the `pairing` message and sit on the
 * pairing screen forever. Hydration is wrapped so a failure renders a retry screen instead of an
 * eternal splash.
 */
async function bootstrap(): Promise<void> {
  const store = useStore.getState();
  store.setHydrationError(null);
  try {
    connect(); // inside the try: a misconfigured API_BASE_URL throws here, and that is a retry screen
    await api.verify(); // upserts the user row from the token claims
    const coupleId = await hydrateFromServer();

    // Both after hydration, and both fire-and-forget: a refused notification permission or an
    // unreachable Google must not turn a working launch into the retry screen below.
    void requestPermissionAndRegister().catch(() => undefined);
    // Never forced. Deliberately not gated on the store's lastCalendarSyncMs either — that is null on
    // every launch, which is exactly why the ≤1-automatic-call-per-hour limiter is persisted inside
    // sync() instead of held in memory.
    if (coupleId) void sync(coupleId).catch(() => undefined);
  } catch (err) {
    store.setHydrationError(err instanceof Error ? err.message : 'could not reach the server');
  } finally {
    store.setHydrated(true);
  }
}

/**
 * couplesync://invite/ABC123 — park the code and navigate nowhere; the guard chain owns the route, and
 * /pairing consumes the code on its Enter tab and clears it. Parking in the store is what makes the
 * code survive the sign-in round trip.
 */
function parkInvite(url: string | null) {
  const code = url?.match(/invite\/([^/?#]+)/)?.[1];
  if (code) useStore.getState().setPendingInvite(decodeURIComponent(code));
}

export default function RootLayout() {
  const colors = useColors();
  const hydrated = useStore((s) => s.hydrated);
  const user = useStore((s) => s.user);
  const hydrationError = useStore((s) => s.hydrationError);

  useEffect(() => {
    Linking.getInitialURL().then(parkInvite); // cold start
    const sub = Linking.addEventListener('url', ({ url }) => parkInvite(url)); // already running
    return () => sub.remove();
  }, []);

  // Returns its own cleanup. On mount rather than after hydration: a tap that launched the app is
  // reported once and early, and there is nothing to gain by being told about it later.
  useEffect(() => attachTapHandler(), []);

  // The single source of "is there a session". A signed-out launch resolves to reset(), which leaves
  // hydrated true — an empty state is known, not unknown, and the splash must not outlive it.
  useEffect(
    () =>
      onAuthChange((uid) => {
        if (!uid) {
          disconnect();
          useStore.getState().reset();
          return;
        }
        void bootstrap();
      }),
    [],
  );

  const centered = {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.md,
    padding: spacing.lg,
    backgroundColor: colors.background,
  } as const;

  // Splash while hydrating — never a screen. Deciding the route from a half-loaded user is what
  // caused the wrong-route flash in the old build's redirect chain.
  if (!hydrated) {
    return (
      <View style={centered}>
        <Text style={{ color: colors.text, fontSize: fontSize.title }}>Couple Sync</Text>
        <ActivityIndicator color={colors.accent} />
      </View>
    );
  }

  // A failed cold start renders this instead of a route: the guard chain would otherwise read a null
  // user as "signed out" and drop a signed-in user back onto /auth because the network blinked.
  if (hydrationError) {
    return (
      <View style={centered}>
        <Text style={{ color: colors.text, fontSize: fontSize.heading }}>Could not load</Text>
        <Text style={{ color: colors.textMuted, fontSize: fontSize.body, textAlign: 'center' }}>
          {hydrationError}
        </Text>
        <Pressable
          accessibilityRole="button"
          onPress={() => {
            useStore.getState().setHydrated(false);
            void bootstrap();
          }}
          style={{
            minHeight: touchTarget,
            minWidth: 2 * touchTarget,
            alignItems: 'center',
            justifyContent: 'center',
            paddingHorizontal: spacing.lg,
            borderRadius: radius,
            backgroundColor: colors.accent,
          }}
        >
          <Text style={{ color: colors.accentText, fontSize: fontSize.body }}>Try again</Text>
        </Pressable>
      </View>
    );
  }

  // The guard chain, per REBUILD-SPEC §1. Exactly one branch is ever unguarded, and a screen behind a
  // false guard is not in the navigator at all — so there is nothing to flash and nothing to redirect
  // away from. Note couple_id, snake_case: the wire shape is the row shape. There is deliberately no
  // calendar guard; a missing calendar scope is one row on the Free time screen.
  const needsAuth = !user;
  const needsTimezone = !!user && !user.timezone;
  const needsPairing = !!user && !!user.timezone && !user.couple_id;
  const inApp = !!user && !!user.timezone && !!user.couple_id;

  return (
    <>
      <StatusBar style="auto" />
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Protected guard={needsAuth}>
          <Stack.Screen name="auth" />
        </Stack.Protected>
        <Stack.Protected guard={needsTimezone}>
          <Stack.Screen name="timezone-setup" />
        </Stack.Protected>
        <Stack.Protected guard={needsPairing}>
          <Stack.Screen name="pairing" />
        </Stack.Protected>
        <Stack.Protected guard={inApp}>
          <Stack.Screen name="(tabs)" />
          <Stack.Screen name="block-form" options={{ presentation: 'modal' }} />
        </Stack.Protected>
        {/*
          +not-found is auto-injected by expo-router and is otherwise always navigable, which would
          strand a couplesync://invite/CODE cold start on "Unmatched Route" — the URL parks its code
          above but matches no route. Guarding it off removes it from the navigator, so any unmatched
          path falls through to the one screen the guard chain allows (StackRouter drops routes it has
          no screen for and lands on the first available one).
        */}
        <Stack.Protected guard={false}>
          <Stack.Screen name="+not-found" />
        </Stack.Protected>
      </Stack>
    </>
  );
}
