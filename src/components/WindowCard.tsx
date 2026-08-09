import { MaterialIcons } from '@expo/vector-icons';
import { Text, View } from 'react-native';

import type { OverlapWindow } from '../../backend/src/wire';
import { fontSize, radius, spacing, useColors } from '../theme';
import { formatDuration, formatWindowRange } from '../time';

/**
 * One overlap window, in both partners' zones — the whole point of the app is that 19:00 for one of
 * them is 13:00 for the other, so a single rendered range would be useless.
 *
 * Not tappable: Task 14 has no window detail to open. It is a plain View, so no touch-target rule
 * applies; the summary label is what a screen reader reads instead of five stray text nodes.
 */
export function WindowCard({
  window,
  yourZone,
  partnerName,
  partnerZone,
  best,
}: {
  window: OverlapWindow;
  yourZone: string;
  partnerName: string;
  partnerZone: string;
  /** Score-derived: true for the highest-scoring window still on screen. */
  best: boolean;
}) {
  const colors = useColors();
  const yours = formatWindowRange(window, yourZone);
  const theirs = formatWindowRange(window, partnerZone);
  const duration = formatDuration(window.durationMinutes);

  // `reasonableBoth` is couple-level, not per-window (§3): it is false when either partner turned
  // late-night windows on, which means the list may contain times outside 07:00–23:00. So the marker
  // says *may*, and it is a glyph plus words — a hue alone would vanish in greyscale.
  const lateNight = !window.reasonableBoth;

  return (
    <View
      accessible
      accessibilityLabel={[
        `${duration} free`,
        `you ${yours}`,
        `${partnerName} ${theirs}`,
        best ? 'best match' : null,
        lateNight ? 'may fall outside waking hours' : null,
      ]
        .filter(Boolean)
        .join(', ')}
      style={{
        padding: spacing.md,
        gap: spacing.xs,
        borderRadius: radius,
        backgroundColor: colors.surface,
        // Emphasis is a border weight as well as a colour, and the star row below says it in words.
        borderWidth: best ? 2 : 1,
        borderColor: best ? colors.accent : colors.border,
      }}
    >
      <Text
        style={{
          color: colors.text,
          fontSize: fontSize.body,
          fontWeight: best ? '700' : '600',
        }}
      >
        {yours}
      </Text>
      <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
        {partnerName}: {theirs}
      </Text>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.md }}>
        <Text style={{ color: colors.text, fontSize: fontSize.label }}>{duration}</Text>
        {best ? (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xs }}>
            <MaterialIcons name="star" size={fontSize.label} color={colors.accent} />
            <Text style={{ color: colors.accent, fontSize: fontSize.label }}>Best match</Text>
          </View>
        ) : null}
        {lateNight ? (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xs }}>
            <MaterialIcons name="bedtime" size={fontSize.label} color={colors.warning} />
            <Text style={{ color: colors.warning, fontSize: fontSize.label }}>May run late</Text>
          </View>
        ) : null}
      </View>
    </View>
  );
}
