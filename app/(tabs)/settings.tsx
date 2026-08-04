import { Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CalendarAccessRow } from '../../src/components/CalendarAccessRow';
import { fontSize, spacing, useColors } from '../../src/theme';

// Task 16 builds this screen — the Calendar / You / Notifications / Couple groups, including "Sync
// now" (the third and last permitted `force` caller). Task 13 adds only the calendar-access row, which
// stands in for the Calendar group's "Allow calendar access" state.
export default function SettingsScreen() {
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
      <Text style={{ color: colors.text, fontSize: fontSize.title }}>Settings</Text>
      <CalendarAccessRow />
    </View>
  );
}
