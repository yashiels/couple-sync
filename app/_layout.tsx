import * as Linking from 'expo-linking';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { ActivityIndicator, Text, View } from 'react-native';

import { useStore } from '../src/store';
import { fontSize, spacing, useColors } from '../src/theme';

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
  const setHydrated = useStore((s) => s.setHydrated);

  useEffect(() => {
    Linking.getInitialURL().then(parkInvite); // cold start
    const sub = Linking.addEventListener('url', ({ url }) => parkInvite(url)); // already running
    return () => sub.remove();
  }, []);

  // Task 11 replaces this with real hydration: Firebase auth state + GET /users/me, setting
  // hydrationError on failure. Until then there is nothing to load.
  useEffect(() => setHydrated(true), [setHydrated]);

  // Splash while hydrating — never a screen. Deciding the route from a half-loaded user is what
  // caused the wrong-route flash in the old build's redirect chain.
  if (!hydrated) {
    return (
      <View
        style={{
          flex: 1,
          alignItems: 'center',
          justifyContent: 'center',
          gap: spacing.md,
          backgroundColor: colors.background,
        }}
      >
        <Text style={{ color: colors.text, fontSize: fontSize.title }}>Couple Sync</Text>
        <ActivityIndicator color={colors.accent} />
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
