import { Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CalendarAccessRow } from '../../src/components/CalendarAccessRow';
import { fontSize, spacing, useColors } from '../../src/theme';

// Task 14 builds this screen — the clocks, the countdown, and the filtered window list. Task 13 adds
// only the calendar-access row, which sits ABOVE the list rather than replacing it: manual blocks can
// still produce windows while the grant is missing.
export default function FreeTimeScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();

  return (
    <View
      style={{
        flex: 1,
        paddingTop: insets.top + spacing.md,
        paddingHorizontal: spacing.lg,
        gap: spacing.md,
        backgroundColor: colors.background,
      }}
    >
      <Text style={{ color: colors.text, fontSize: fontSize.title }}>Free time</Text>
      <CalendarAccessRow />
    </View>
  );
}
