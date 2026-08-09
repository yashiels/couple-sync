import { useEffect, useState, type ReactNode } from 'react';
import { Alert, Modal, Pressable, ScrollView, Switch, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { ApiError, api } from '../../src/api';
import { signOut } from '../../src/auth';
import { hasCalendarScope, sync, type SyncResult } from '../../src/calendar';
import { CalendarAccessRow } from '../../src/components/CalendarAccessRow';
import {
  listDeviceCalendars,
  setCalendarEnabled,
  type DeviceCalendar,
} from '../../src/deviceCalendar';
import { ZoneList } from '../../src/components/ZoneList';
import { useStore } from '../../src/store';
import { fontSize, radius, spacing, touchTarget, useColors } from '../../src/theme';
import { formatDuration } from '../../src/time';

/**
 * Settings: Calendar, You, Notifications, Couple — nine plain labelled rows, no settings schema.
 *
 * The toggles are the point of this screen. Each one PATCHes the user row and then renders from what
 * the server returned, so a failed write leaves the control showing the server's actual value. The
 * previous build's toggles wrote local state and nothing else, which is the defect being fixed: the
 * notification switch here changes whether `backend/src/overlapService.ts` sends a push at all.
 */

/** `force` makes 'rate-limited' unreachable, but the map stays total so a new result cannot slip past. */
const SYNC_NOTES: Record<SyncResult, string> = {
  synced: 'Synced with Google Calendar.',
  'rate-limited': 'Already up to date.',
  'scope-missing': 'Calendar access is off — allow it above and we will sync straight away.',
  'no-session': 'Sign in with Google again to sync your calendar.',
};

function syncedAgo(lastSyncMs: number | null): string {
  if (lastSyncMs === null) return 'Not synced on this device yet';
  const minutes = Math.floor((Date.now() - lastSyncMs) / 60_000);
  return minutes < 1 ? 'Synced just now' : `Synced ${formatDuration(minutes)} ago`;
}

export default function SettingsScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const user = useStore((s) => s.user);
  const partner = useStore((s) => s.partner);
  const setUser = useStore((s) => s.setUser);
  const lastSyncMs = useStore((s) => s.lastCalendarSyncMs);

  const [scopeOk, setScopeOk] = useState<boolean | null>(null);
  const [zonesOpen, setZonesOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [syncNote, setSyncNote] = useState<string | null>(null);
  // null until the OS calendar list loads; [] means permission denied or no calendars.
  const [deviceCals, setDeviceCals] = useState<DeviceCalendar[] | null>(null);

  useEffect(() => {
    void listDeviceCalendars().then(setDeviceCals);
  }, []);

  // Re-checked whenever the last-sync mirror moves, because that is what CalendarAccessRow does on a
  // successful grant (it force-syncs). Without the dependency the row would grant the scope and then
  // sit there with "Sync now" still hidden until something else remounted this screen.
  useEffect(() => {
    void hasCalendarScope().then(setScopeOk);
  }, [lastSyncMs]);

  const coupleId = user?.couple_id ?? null;
  const partnerName = partner?.display_name ?? partner?.email ?? 'Your partner';
  const zone = user?.timezone ?? 'UTC';

  async function patch(fields: Parameters<typeof api.patchUser>[1]) {
    if (!user) return;
    setBusy(true);
    try {
      setUser(await api.patchUser(user.uid, fields));
    } catch (err) {
      Alert.alert(
        'Could not save that',
        err instanceof ApiError && err.code === 'invalid_timezone'
          ? 'That timezone is not one this app can use. Pick another.'
          : 'Check your connection and try again.',
      );
    } finally {
      setBusy(false);
    }
  }

  async function onSyncNow() {
    if (!coupleId) return;
    setSyncing(true);
    setSyncNote(null);
    try {
      // Permitted `force` caller — one of exactly three (this button, a successful ensureScope(), and
      // first pairing). A discrete button press, so it cannot loop.
      const result = await sync(coupleId, { force: true });
      if (result === 'scope-missing') setScopeOk(false);
      setSyncNote(SYNC_NOTES[result]);
    } catch {
      setSyncNote('Could not reach Google Calendar. Try again in a moment.');
    } finally {
      setSyncing(false);
    }
  }

  async function onToggleCalendar(id: string, enabled: boolean) {
    await setCalendarEnabled(id, enabled);
    setDeviceCals(await listDeviceCalendars());
    // Which device calendars count changes the busy times feeding overlap, so re-sync now. A discrete
    // toggle press — a permitted `force` caller, same as "Sync now", so it cannot loop.
    if (!coupleId) return;
    setSyncing(true);
    setSyncNote(null);
    try {
      setSyncNote(SYNC_NOTES[await sync(coupleId, { force: true })]);
    } catch {
      setSyncNote('Could not sync. Try again in a moment.');
    } finally {
      setSyncing(false);
    }
  }

  async function unpair(id: string) {
    setBusy(true);
    try {
      await api.unpair(id);
      // Locally and immediately, not on the WS `unpair` message: that message is addressed to the
      // partner as well and this device may have no live socket, so waiting on it can mean waiting
      // forever. resetCouple() nulls user.couple_id and the guard chain moves to /pairing by itself.
      useStore.getState().resetCouple();
    } catch {
      Alert.alert('Could not unpair', 'Check your connection and try again.');
    } finally {
      setBusy(false);
    }
  }

  function confirmUnpair() {
    if (!coupleId) return;
    Alert.alert(
      `Unpair from ${partnerName}?`,
      'This deletes every block either of you created and your shared free time, and unpairs you both. Your Google Calendar itself is untouched. Pairing again needs a new invite code.',
      [
        { text: 'Stay paired', style: 'cancel' },
        { text: 'Unpair', style: 'destructive', onPress: () => void unpair(coupleId) },
      ],
    );
  }

  async function onSignOut() {
    setBusy(true);
    try {
      // Deletes this device's FCM token server-side first, so the handset stops receiving pushes meant
      // for this account, then clears the whole store.
      await signOut();
    } catch {
      Alert.alert('Could not sign out', 'Check your connection and try again.');
      setBusy(false);
    }
  }

  const group = (title: string, children: ReactNode) => (
    <View style={{ gap: spacing.sm }}>
      <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>{title.toUpperCase()}</Text>
      <View
        style={{
          borderRadius: radius,
          backgroundColor: colors.surface,
          paddingHorizontal: spacing.md,
          paddingVertical: spacing.sm,
          gap: spacing.sm,
        }}
      >
        {children}
      </View>
    </View>
  );

  const toggle = (label: string, hint: string, value: boolean, onChange: (v: boolean) => void) => (
    <Pressable
      accessibilityRole="switch"
      accessibilityLabel={label}
      accessibilityState={{ checked: value, disabled: busy }}
      disabled={busy}
      onPress={() => onChange(!value)}
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        gap: spacing.md,
        minHeight: touchTarget,
        paddingVertical: spacing.xs,
      }}
    >
      <View style={{ flex: 1, gap: spacing.xs }}>
        <Text style={{ color: colors.text, fontSize: fontSize.body }}>{label}</Text>
        <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>{hint}</Text>
      </View>
      {/* The word carries the state; the switch only draws it. Colour alone is not a state, and the
          whole row is the control so the touch target is a full 44pt rather than the switch's own. */}
      <Text style={{ color: colors.text, fontSize: fontSize.label }}>{value ? 'On' : 'Off'}</Text>
      <View pointerEvents="none" importantForAccessibility="no-hide-descendants">
        <Switch
          value={value}
          disabled={busy}
          trackColor={{ true: colors.accent, false: colors.border }}
        />
      </View>
    </Pressable>
  );

  const button = (label: string, onPress: () => void, tone: 'plain' | 'danger' = 'plain') => (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled: busy }}
      disabled={busy}
      onPress={onPress}
      style={{
        minHeight: touchTarget,
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: radius,
        borderWidth: 1,
        borderColor: tone === 'danger' ? colors.danger : colors.border,
        opacity: busy ? 0.6 : 1,
      }}
    >
      <Text
        style={{
          color: tone === 'danger' ? colors.danger : colors.text,
          fontSize: fontSize.body,
        }}
      >
        {label}
      </Text>
    </Pressable>
  );

  return (
    <ScrollView
      style={{ backgroundColor: colors.background }}
      contentContainerStyle={{
        paddingTop: insets.top + spacing.md,
        paddingHorizontal: spacing.lg,
        paddingBottom: insets.bottom + spacing.xl,
        gap: spacing.lg,
      }}
    >
      <Text style={{ color: colors.text, fontSize: fontSize.title }}>Settings</Text>

      {group(
        'Calendar',
        <>
          <View style={{ gap: spacing.xs }}>
            <Text style={{ color: colors.text, fontSize: fontSize.body }}>
              {user?.email ?? 'Signed in with Google'}
            </Text>
            <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
              {syncedAgo(lastSyncMs)} · we read only busy and free times, never event titles.
            </Text>
          </View>

          {/*
            No connect and no disconnect (§0.6c): signing in with Google IS the calendar grant, so
            disconnecting would mean signing out. The only real gap is a declined or revoked scope, and
            that is the row below — which replaces "Sync now" rather than sitting above it, because a
            sync without the scope can only ever fail.
          */}
          {scopeOk === false ? (
            <CalendarAccessRow />
          ) : (
            <>
              {button(syncing ? 'Syncing…' : 'Sync now', () => void onSyncNow())}
              {syncNote ? (
                <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
                  {syncNote}
                </Text>
              ) : null}
            </>
          )}
        </>,
      )}

      {deviceCals && deviceCals.length > 0
        ? group(
            'Device calendars',
            <>
              <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
                Busy times are read from these. A work calendar appears here once it is synced to this
                phone — only start and end times are read, never event titles.
              </Text>
              {deviceCals.map((c) => (
                <View key={c.id}>
                  {toggle(
                    c.title,
                    c.source || 'Device calendar',
                    c.enabled,
                    (v) => void onToggleCalendar(c.id, v),
                  )}
                </View>
              ))}
            </>,
          )
        : null}

      {group(
        'You',
        <>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={`Timezone, currently ${zone.replace(/_/g, ' ')}. Opens a list.`}
            accessibilityState={{ disabled: busy }}
            disabled={busy}
            onPress={() => setZonesOpen(true)}
            style={{
              flexDirection: 'row',
              alignItems: 'center',
              gap: spacing.md,
              minHeight: touchTarget,
            }}
          >
            <Text style={{ color: colors.text, fontSize: fontSize.body, flex: 1 }}>Timezone</Text>
            <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
              {zone.replace(/_/g, ' ')}
            </Text>
            <Text style={{ color: colors.textMuted, fontSize: fontSize.body }}>›</Text>
          </Pressable>

          {toggle(
            'Late-night windows',
            'Show shared free time that falls late at night for one of you.',
            user?.show_late_night_windows ?? false,
            (show_late_night_windows) => void patch({ show_late_night_windows }),
          )}
        </>,
      )}

      {group(
        'Notifications',
        toggle(
          'Push notifications',
          'When your shared free time changes, we tell you. Off means the server sends nothing.',
          user?.notifications_enabled ?? true,
          (notifications_enabled) => void patch({ notifications_enabled }),
        ),
      )}

      {group(
        'Couple',
        <>
          <View
            style={{ minHeight: touchTarget, justifyContent: 'center', gap: spacing.xs }}
          >
            <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>Paired with</Text>
            <Text style={{ color: colors.text, fontSize: fontSize.body }}>{partnerName}</Text>
          </View>
          {button('Unpair', confirmUnpair, 'danger')}
          {button('Sign out', () => void onSignOut())}
        </>,
      )}

      <Modal
        visible={zonesOpen}
        animationType="slide"
        onRequestClose={() => setZonesOpen(false)}
        // Same searchable list as onboarding, current local time and all — a second copy would be the
        // one that drifts.
      >
        <View
          style={{
            flex: 1,
            paddingTop: insets.top + spacing.md,
            paddingHorizontal: spacing.lg,
            paddingBottom: insets.bottom + spacing.md,
            gap: spacing.sm,
            backgroundColor: colors.background,
          }}
        >
          <Text style={{ color: colors.text, fontSize: fontSize.heading }}>Your timezone</Text>
          <ZoneList
            selected={zone}
            onSelect={(picked) => {
              setZonesOpen(false);
              // The server recomputes the couple's windows on a timezone change, so the free-time list
              // updates over the WS without anything more from here.
              if (picked !== zone) void patch({ timezone: picked });
            }}
          />
          {button('Close', () => setZonesOpen(false))}
        </View>
      </Modal>
    </ScrollView>
  );
}
