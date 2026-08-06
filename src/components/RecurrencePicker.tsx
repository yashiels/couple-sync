import { Pressable, Text, View } from 'react-native';

import {
  buildRrule,
  describeRrule,
  parseRrule,
  WEEKDAYS,
  weekdayCode,
  weekdayLabel,
  type Freq,
  type Weekday,
} from '../recurrence';
import { fontSize, radius, spacing, touchTarget, useColors } from '../theme';

/**
 * None / daily / weekly (with weekday selection) / monthly, emitting an RRULE string or null.
 *
 * It can only express rules `backend/src/routes/blocks.ts` accepts (§3.2) — everything it emits comes
 * from `buildRrule`, which is unit-tested against that validator's rules. A rule the server rejects
 * surfaces as a 400 the user has no way to fix, so the control simply cannot produce one.
 *
 * Stateless: the rule string in the form is the state. Mirroring it into local state is how a picker
 * and its field end up disagreeing.
 */

const MODES: { label: string; freq: Freq | null }[] = [
  { label: 'Does not repeat', freq: null },
  { label: 'Daily', freq: 'DAILY' },
  { label: 'Weekly', freq: 'WEEKLY' },
  { label: 'Monthly', freq: 'MONTHLY' },
];

export function RecurrencePicker({
  value,
  startUtc,
  zone,
  onChange,
}: {
  value: string | null;
  /** The block's start, so choosing "Weekly" defaults to the weekday it actually starts on. */
  startUtc: number;
  /** The block's zone, which is what the server anchors expansion to (§0.3). */
  zone: string;
  onChange(rule: string | null): void;
}) {
  const colors = useColors();
  const parsed = parseRrule(value);
  // A rule that exists but does not parse is a rule this picker cannot represent (an INTERVAL, say).
  // No mode is selected then, and the caption below shows what is actually stored — better than
  // silently rewriting the user's rule the moment the form opens.
  const activeFreq = parsed?.freq ?? null;
  const selectedDays = parsed?.byday.length ? parsed.byday : [weekdayCode(startUtc, zone)];

  function selectMode(freq: Freq | null) {
    if (freq === null) return onChange(null);
    if (freq === 'WEEKLY') return onChange(buildRrule({ freq, byday: selectedDays }));
    onChange(buildRrule({ freq, byday: [] }));
  }

  function toggleDay(day: Weekday) {
    const next = selectedDays.includes(day)
      ? selectedDays.filter((d) => d !== day)
      : [...WEEKDAYS].filter((d) => d === day || selectedDays.includes(d));
    // Never zero days: `BYDAY=` is not a rule the server accepts, and "weekly on no day" is not a
    // thing the user means.
    if (next.length === 0) return;
    onChange(buildRrule({ freq: 'WEEKLY', byday: next }));
  }

  const chip = (
    label: string,
    selected: boolean,
    onPress: () => void,
    accessibilityLabel?: string,
  ) => (
    <Pressable
      key={label}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ selected }}
      onPress={onPress}
      style={{
        minHeight: touchTarget,
        minWidth: touchTarget,
        flexGrow: 1,
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: spacing.xs,
        borderRadius: radius,
        // A tick and a heavier border as well as a fill, so selection survives greyscale.
        borderWidth: selected ? 2 : 1,
        borderColor: selected ? colors.accent : colors.border,
        backgroundColor: selected ? colors.surface : colors.background,
      }}
    >
      <Text
        style={{
          color: selected ? colors.text : colors.textMuted,
          fontSize: fontSize.label,
          fontWeight: selected ? '700' : '400',
        }}
      >
        {selected ? '✓ ' : ''}
        {label}
      </Text>
    </Pressable>
  );

  return (
    <View style={{ gap: spacing.sm }}>
      <Text style={{ color: colors.text, fontSize: fontSize.label }}>Repeat</Text>

      <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}>
        {MODES.map((mode) =>
          chip(
            mode.label,
            value === null ? mode.freq === null : mode.freq === activeFreq,
            () => selectMode(mode.freq),
          ),
        )}
      </View>

      {activeFreq === 'WEEKLY' ? (
        // Wraps rather than squeezing: seven 44pt targets do not fit one row on a narrow phone, and
        // the touch target is the constraint that wins.
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs }}>
          {WEEKDAYS.map((day) =>
            chip(
              weekdayLabel(day).slice(0, 2),
              selectedDays.includes(day),
              () => toggleDay(day),
              weekdayLabel(day),
            ),
          )}
        </View>
      ) : null}

      <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
        {describeRrule(value) ?? 'Happens once.'}
      </Text>
    </View>
  );
}
