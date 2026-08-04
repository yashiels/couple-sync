import * as Localization from 'expo-localization';
import { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { ApiError, api } from '../src/api';
import { useStore } from '../src/store';
import { fontSize, radius, spacing, touchTarget, useColors } from '../src/theme';
import { formatClock } from '../src/time';
import { searchZones } from '../src/timezones';

// An emulator commonly reports UTC, and the type allows null, so the fallback is required rather than
// defensive. UTC is a valid IANA id and the server accepts it.
const detectedZone = Localization.getCalendars()[0]?.timeZone ?? 'UTC';

export default function TimezoneSetupScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const user = useStore((s) => s.user);
  const setUser = useStore((s) => s.setUser);

  const [selected, setSelected] = useState(detectedZone);
  const [query, setQuery] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // The local time beside every candidate is the whole point of the list — a wrong pick is obvious
  // when the clock next to it is not your clock. Ticked once a minute, never once a second.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 60_000);
    return () => clearInterval(timer);
  }, []);

  const zones = useMemo(() => searchZones(query), [query]);

  async function onConfirm() {
    if (!user) return;
    setSaving(true);
    setError(null);
    try {
      // No navigation: the guard chain moves on the moment user.timezone is non-null, and a manual
      // push would race it.
      setUser(await api.patchUser(user.uid, { timezone: selected }));
    } catch (err) {
      setError(
        err instanceof ApiError && err.code === 'invalid_timezone'
          ? `${selected} is not a timezone this app can use. Pick another.`
          : 'Could not save your timezone. Check your connection and try again.',
      );
    } finally {
      setSaving(false);
    }
  }

  return (
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
      <Text style={{ color: colors.text, fontSize: fontSize.title }}>Your timezone</Text>
      <Text style={{ color: colors.textMuted, fontSize: fontSize.body }}>
        We use it to show your free time in your hours, and your partner&apos;s in theirs.
      </Text>

      <View
        style={{
          padding: spacing.md,
          borderRadius: radius,
          backgroundColor: colors.surface,
          gap: spacing.xs,
        }}
      >
        <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
          {selected === detectedZone ? 'Detected on this device' : 'Selected'}
        </Text>
        <Text style={{ color: colors.text, fontSize: fontSize.heading }}>
          {selected.replace(/_/g, ' ')}
        </Text>
        <Text style={{ color: colors.text, fontSize: fontSize.body }}>
          {formatClock(selected, now)} right now
        </Text>
      </View>

      <TextInput
        accessibilityLabel="Search timezones"
        placeholder="Search for a city or region"
        placeholderTextColor={colors.textMuted}
        value={query}
        onChangeText={setQuery}
        autoCorrect={false}
        style={{
          minHeight: touchTarget,
          paddingHorizontal: spacing.md,
          borderRadius: radius,
          borderWidth: 1,
          borderColor: colors.border,
          color: colors.text,
          fontSize: fontSize.body,
        }}
      />

      <FlatList
        style={{ flex: 1 }}
        data={zones}
        keyExtractor={(zone) => zone}
        keyboardShouldPersistTaps="handled"
        ListEmptyComponent={
          <Text
            style={{ color: colors.textMuted, fontSize: fontSize.body, paddingVertical: spacing.md }}
          >
            No timezone matches that. Try a city name, such as Johannesburg.
          </Text>
        }
        renderItem={({ item }) => {
          const isSelected = item === selected;
          return (
            <Pressable
              accessibilityRole="button"
              accessibilityState={{ selected: isSelected }}
              onPress={() => setSelected(item)}
              style={{
                minHeight: touchTarget,
                flexDirection: 'row',
                alignItems: 'center',
                justifyContent: 'space-between',
                gap: spacing.sm,
                paddingHorizontal: spacing.sm,
                borderBottomWidth: 1,
                borderBottomColor: colors.border,
              }}
            >
              {/* The tick, not the tint, is what says "selected" — colour alone is not a state. */}
              <Text style={{ color: colors.text, fontSize: fontSize.body, flexShrink: 1 }}>
                {isSelected ? '✓ ' : ''}
                {item.replace(/_/g, ' ')}
              </Text>
              <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
                {formatClock(item, now)}
              </Text>
            </Pressable>
          );
        }}
      />

      {error ? <Text style={{ color: colors.danger, fontSize: fontSize.label }}>{error}</Text> : null}

      <Pressable
        accessibilityRole="button"
        accessibilityState={{ disabled: saving }}
        disabled={saving}
        onPress={() => void onConfirm()}
        style={{
          minHeight: touchTarget,
          alignItems: 'center',
          justifyContent: 'center',
          borderRadius: radius,
          backgroundColor: colors.accent,
          opacity: saving ? 0.6 : 1,
        }}
      >
        {saving ? (
          <ActivityIndicator color={colors.accentText} />
        ) : (
          <Text style={{ color: colors.accentText, fontSize: fontSize.body }}>
            Use {selected.replace(/_/g, ' ')}
          </Text>
        )}
      </Pressable>
    </View>
  );
}
