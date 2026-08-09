import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { FlatList, Pressable, RefreshControl, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { api } from '../../src/api';
import { sync } from '../../src/calendar';
import { CalendarAccessRow } from '../../src/components/CalendarAccessRow';
import { WindowCard } from '../../src/components/WindowCard';
import { useStore } from '../../src/store';
import { fontSize, radius, spacing, touchTarget, useColors } from '../../src/theme';
import { earliestWindow, formatClock, formatCountdown, visibleWindows } from '../../src/time';

/**
 * Free time — the one screen that lists overlap windows. There is no separate Overlap tab: the two
 * differed only in list length and a filter, which is one screen with a filter.
 *
 * Everything here is display. The windows arrive computed and score-sorted from the server (§0.1), so
 * the only arithmetic below is "has this one finished yet" and "is it long enough to show".
 */

// Display-only per §0.7 — the engine's 30-minute minimum is hard-coded server-side and no filter here
// changes what it computes.
const FILTERS = [
  { label: 'Any', minutes: 0 },
  { label: '30m', minutes: 30 },
  { label: '1h', minutes: 60 },
  { label: '2h', minutes: 120 },
] as const;

// A pull is a deliberate user gesture, so it forces Google (bypassing the hourly gate). The cooldown
// stops a user who yanks the list repeatedly from spending a metered call on each tug — 30s is well
// under an hour but past the reflexive double-pull. Module-level so it survives this screen's unmount.
const PULL_COOLDOWN_MS = 30_000;
let lastForcedPullMs = 0;

/**
 * One tick a minute, aligned to the minute boundary. A per-second interval would wake the device 60×
 * more often to redraw an HH:mm clock nobody is watching a second hand on; aligning means the digits
 * flip when the minute does instead of up to 59 s late.
 */
function useMinuteClock(): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | undefined;
    const timeout = setTimeout(() => {
      setNow(Date.now());
      interval = setInterval(() => setNow(Date.now()), 60_000);
    }, 60_000 - (Date.now() % 60_000));
    return () => {
      clearTimeout(timeout);
      if (interval) clearInterval(interval);
    };
  }, []);
  return now;
}

export default function FreeTimeScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const user = useStore((s) => s.user);
  const partner = useStore((s) => s.partner);
  const windows = useStore((s) => s.windows);
  const computedAt = useStore((s) => s.computedAt);

  const [minMinutes, setMinMinutes] = useState<number>(0);
  const [refreshing, setRefreshing] = useState(false);
  const [refreshError, setRefreshError] = useState<string | null>(null);
  // Bumped after a refresh so the access row re-checks the grant: a scope revoked from the user's
  // Google account mid-session is otherwise invisible until the next launch.
  const [scopeCheck, setScopeCheck] = useState(0);
  const now = useMinuteClock();

  // The guard chain only mounts the tabs for a user with a timezone and a couple_id, so these
  // fallbacks are unreachable — they exist so this screen needs no non-null assertion.
  const coupleId = user?.couple_id ?? null;
  const yourZone = user?.timezone ?? 'UTC';
  const partnerZone = partner?.timezone ?? yourZone;
  const partnerName = partner?.display_name ?? 'Your partner';

  // Refetch the server-computed windows every time this tab gains focus. hydrateFromServer() loads
  // them once and the WS `overlap` push keeps them live — but a push missed during a socket drop (or
  // a block added on another device) leaves this screen showing a window computed earlier in the day
  // (e.g. a stale "13:00–23:00" from before a block was added). Refetching on focus self-heals that
  // without waiting for a pull-to-refresh. Fire-and-forget: a failure just leaves the current windows.
  useFocusEffect(
    useCallback(() => {
      if (!coupleId) return;
      api
        .latestOverlap(coupleId)
        .then((o) => useStore.getState().setWindows(o.windows, o.computed_at))
        .catch(() => undefined);
    }, [coupleId]),
  );

  const live = visibleWindows(windows, now, 0);
  const visible = visibleWindows(live, now, minMinutes);
  const next = earliestWindow(visible);
  const topScore = visible.reduce((max, w) => Math.max(max, w.score), -Infinity);
  // The server sorts by score, which surfaces a long window days out ahead of tonight's gap. People
  // read this list as "when can we next meet", so show it chronologically — the soonest gap first —
  // and let the score drive only the "best match" star, not the position.
  const ordered = [...visible].sort((a, b) => a.startUtc - b.startUtc);
  const loading = computedAt === null;

  async function onRefresh() {
    if (!coupleId) return;
    setRefreshing(true);
    setRefreshError(null);
    try {
      // The calendar FIRST, then the windows. Refetching windows without re-pulling free/busy is the
      // bug a user reports as "it's out of date". A pull is a deliberate gesture, so it forces Google
      // past the hourly gate — but only once per cooldown, so repeated tugs don't each spend a call.
      const now = Date.now();
      const force = now - lastForcedPullMs >= PULL_COOLDOWN_MS;
      if (force) lastForcedPullMs = now;
      await sync(coupleId, { force });
      const overlap = await api.latestOverlap(coupleId);
      useStore.getState().setWindows(overlap.windows, overlap.computed_at);
    } catch {
      setRefreshError('Could not refresh. Check your connection and pull down again.');
    } finally {
      setScopeCheck((n) => n + 1);
      setRefreshing(false);
    }
  }

  const clock = (label: string, zone: string) => (
    <View style={{ flex: 1, gap: spacing.xs }}>
      <Text numberOfLines={1} style={{ color: colors.textMuted, fontSize: fontSize.label }}>
        {label}
      </Text>
      <Text style={{ color: colors.text, fontSize: fontSize.title }}>{formatClock(zone, now)}</Text>
      <Text numberOfLines={1} style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
        {zone}
      </Text>
    </View>
  );

  const header = (
    <View style={{ gap: spacing.md, paddingBottom: spacing.md }}>
      <Text style={{ color: colors.text, fontSize: fontSize.title }}>Free time</Text>

      <View style={{ flexDirection: 'row', gap: spacing.md }}>
        {clock('You', yourZone)}
        {clock(partnerName, partnerZone)}
      </View>

      {/* Above the list, never instead of it: manual blocks still produce windows without the grant. */}
      <CalendarAccessRow key={scopeCheck} />

      {/* The earliest window, which is NOT visible[0] — the list is score-sorted, so index 0 is the
          best window and can be days away. This exact trap already broke the FCM notification body. */}
      {next ? (
        <View style={{ gap: spacing.xs }}>
          <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>Next window</Text>
          <Text style={{ color: colors.accent, fontSize: fontSize.heading }}>
            {formatCountdown(next.startUtc, now)}
          </Text>
        </View>
      ) : null}

      <View accessibilityRole="tablist" style={{ flexDirection: 'row', gap: spacing.sm }}>
        {FILTERS.map((f) => {
          const active = f.minutes === minMinutes;
          return (
            <Pressable
              key={f.label}
              accessibilityRole="tab"
              accessibilityLabel={f.minutes === 0 ? 'Any length' : `At least ${f.label}`}
              accessibilityState={{ selected: active }}
              onPress={() => setMinMinutes(f.minutes)}
              style={{
                minHeight: touchTarget,
                minWidth: touchTarget,
                alignItems: 'center',
                justifyContent: 'center',
                paddingHorizontal: spacing.md,
                borderRadius: radius,
                // A border and a bold label as well as a fill: the selection must survive greyscale.
                borderWidth: active ? 2 : 1,
                borderColor: active ? colors.accent : colors.border,
                backgroundColor: active ? colors.surface : colors.background,
              }}
            >
              <Text
                style={{
                  color: active ? colors.text : colors.textMuted,
                  fontSize: fontSize.label,
                  fontWeight: active ? '700' : '400',
                }}
              >
                {f.label}
              </Text>
            </Pressable>
          );
        })}
      </View>

      {refreshError ? (
        <Text style={{ color: colors.danger, fontSize: fontSize.label }}>{refreshError}</Text>
      ) : null}
    </View>
  );

  // A skeleton, not a spinner over an empty list: three grey bars say "windows are coming" where a
  // spinner over nothing says "possibly broken".
  const skeleton = (
    <View style={{ gap: spacing.md }}>
      {[0, 1, 2].map((i) => (
        <View
          key={i}
          accessibilityLabel={i === 0 ? 'Loading your free time' : undefined}
          style={{ height: 96, borderRadius: radius, backgroundColor: colors.surface }}
        />
      ))}
    </View>
  );

  const empty = loading ? (
    skeleton
  ) : live.length === 0 ? (
    <View style={{ gap: spacing.md }}>
      <Text style={{ color: colors.text, fontSize: fontSize.body }}>
        You two have no shared free time in the next 14 days.
      </Text>
      <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
        Check your blocks — a busy block that should not be there is the usual reason.
      </Text>
      <Pressable
        accessibilityRole="button"
        onPress={() => router.navigate('/(tabs)/calendar')}
        style={{
          minHeight: touchTarget,
          alignSelf: 'flex-start',
          alignItems: 'center',
          justifyContent: 'center',
          paddingHorizontal: spacing.lg,
          borderRadius: radius,
          backgroundColor: colors.accent,
        }}
      >
        <Text style={{ color: colors.accentText, fontSize: fontSize.body }}>Review your blocks</Text>
      </Pressable>
    </View>
  ) : (
    <Text style={{ color: colors.textMuted, fontSize: fontSize.body }}>
      Nothing that long in the next 14 days. Try a shorter length.
    </Text>
  );

  return (
    <FlatList
      style={{ backgroundColor: colors.background }}
      contentContainerStyle={{
        paddingTop: insets.top + spacing.md,
        paddingHorizontal: spacing.lg,
        paddingBottom: insets.bottom + spacing.lg,
        gap: spacing.md,
      }}
      data={ordered}
      keyExtractor={(w) => `${w.startUtc}-${w.endUtc}`}
      ListHeaderComponent={header}
      ListEmptyComponent={empty}
      renderItem={({ item }) => (
        <WindowCard
          window={item}
          yourZone={yourZone}
          partnerName={partnerName}
          partnerZone={partnerZone}
          best={item.score === topScore}
        />
      )}
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          onRefresh={() => void onRefresh()}
          tintColor={colors.accent}
        />
      }
    />
  );
}
