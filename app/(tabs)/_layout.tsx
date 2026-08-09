import { MaterialIcons } from '@expo/vector-icons';
import { Tabs } from 'expo-router';
import type { ColorValue } from 'react-native';

import { touchTarget, useColors } from '../../src/theme';

// Three tabs, per REBUILD-SPEC §1. There is no Overlap tab and no Blocks tab: the Calendar tab *is*
// the block-management surface. Icons are Google Material Icons (@expo/vector-icons); each tab keeps
// its visible label and an accessibilityLabel so the icon is never the only cue.
const tabIcon = (name: keyof typeof MaterialIcons.glyphMap) =>
  function TabIcon({ color, size }: { color: ColorValue; size: number }) {
    return <MaterialIcons name={name} color={color} size={size} />;
  };

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
          tabBarIcon: tabIcon('schedule'),
        }}
      />
      <Tabs.Screen
        name="calendar"
        options={{
          title: 'Calendar',
          tabBarAccessibilityLabel: 'Calendar',
          tabBarIcon: tabIcon('calendar-month'),
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: 'Settings',
          tabBarAccessibilityLabel: 'Settings',
          tabBarIcon: tabIcon('settings'),
        }}
      />
    </Tabs>
  );
}
