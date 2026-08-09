import { MaterialIcons } from '@expo/vector-icons';
import { useEffect, useMemo, useState } from 'react';
import { FlatList, Pressable, Text, TextInput, View } from 'react-native';

import { fontSize, radius, spacing, touchTarget, useColors } from '../theme';
import { formatClock } from '../time';
import { searchZones } from '../timezones';

/**
 * The searchable zone list, with each candidate's current local time beside it (§1). The clock is the
 * point of the list, not decoration: a wrong pick is obvious when the time next to it is not the time
 * where you are.
 *
 * Extracted because it has two call sites — onboarding and Settings — and a second copy would be the
 * one that drifts. Each caller owns its own framing and what happens on a pick, which is why this
 * component neither saves nor navigates.
 */
export function ZoneList({
  selected,
  onSelect,
}: {
  selected: string;
  onSelect: (zone: string) => void;
}) {
  const colors = useColors();
  const [query, setQuery] = useState('');

  // Once a minute, never once a second: this redraws HH:mm labels nobody watches a second hand on.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 60_000);
    return () => clearInterval(timer);
  }, []);

  const zones = useMemo(() => searchZones(query), [query]);

  return (
    <>
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
              onPress={() => onSelect(item)}
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
              <View
                style={{
                  flexDirection: 'row',
                  alignItems: 'center',
                  gap: spacing.xs,
                  flexShrink: 1,
                }}
              >
                {isSelected ? (
                  <MaterialIcons name="check" size={fontSize.body} color={colors.accent} />
                ) : null}
                <Text style={{ color: colors.text, fontSize: fontSize.body, flexShrink: 1 }}>
                  {item.replace(/_/g, ' ')}
                </Text>
              </View>
              <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
                {formatClock(item, now)}
              </Text>
            </Pressable>
          );
        }}
      />
    </>
  );
}
