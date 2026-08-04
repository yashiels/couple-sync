import { Tabs } from 'expo-router';
import { Text, type ColorValue } from 'react-native';

import { fontSize, touchTarget, useColors } from '../../src/theme';

// Three tabs, per REBUILD-SPEC §1. There is no Overlap tab and no Blocks tab: the Calendar tab *is*
// the block-management surface. No icon library is installed and three glyphs do not justify adding
// one; each tab keeps its visible label and an accessibilityLabel so the icon is never the only cue.
const tabIcon =
  (glyph: string) =>
  ({ color }: { color: ColorValue }) => (
    <Text style={{ color, fontSize: fontSize.heading }}>{glyph}</Text>
  );

export default function TabsLayout() {
  const colors = useColors();

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.accent,
        tabBarInactiveTintColor: colors.textMuted,
        tabBarStyle: { backgroundColor: colors.surface, borderTopColor: colors.border },
        tabBarItemStyle: { minHeight: touchTarget },
      }}
    >
      <Tabs.Screen
        name="index"
        options={{
          title: 'Free time',
          tabBarAccessibilityLabel: 'Free time',
          tabBarIcon: tabIcon('◆'),
        }}
      />
      <Tabs.Screen
        name="calendar"
        options={{
          title: 'Calendar',
          tabBarAccessibilityLabel: 'Calendar',
          tabBarIcon: tabIcon('▦'),
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: 'Settings',
          tabBarAccessibilityLabel: 'Settings',
          tabBarIcon: tabIcon('⚙'),
        }}
      />
    </Tabs>
  );
}
