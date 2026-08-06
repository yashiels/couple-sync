import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';

import { ensureScope, hasCalendarScope, sync } from '../calendar';
import { useStore } from '../store';
import { fontSize, radius, spacing, touchTarget, useColors } from '../theme';

/**
 * One inline row — never a screen and never a router guard (§5). A user can complete Google sign-in
 * while declining the calendar consent, or revoke it later, and the app has to stay usable on manual
 * blocks alone. Renders nothing at all while the grant is intact.
 *
 * Rendered on both the Free time and Settings screens, which is why the ensureScope-then-force-sync
 * pair lives here once rather than being copied into each.
 */
export function CalendarAccessRow() {
  const colors = useColors();
  const coupleId = useStore((s) => s.user?.couple_id ?? null);
  const [missing, setMissing] = useState(false);
  const [working, setWorking] = useState(false);

  // hasCalendarScope(), not a sync() result: app/_layout.tsx already synced on launch, so a second
  // sync from here would come back 'rate-limited' and could never report 'scope-missing'.
  useEffect(() => {
    void hasCalendarScope().then((ok) => setMissing(!ok));
  }, []);

  if (!missing) return null;

  async function onAllow() {
    setWorking(true);
    try {
      if (!(await ensureScope())) return; // cancelled — leave the row up, say nothing
      setMissing(false);
      // Permitted `force` caller: a discrete user action that just granted the scope, so the hourly
      // limiter must not sit on the first sync that can finally succeed.
      if (coupleId) await sync(coupleId, { force: true });
    } finally {
      setWorking(false);
    }
  }

  return (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        gap: spacing.md,
        padding: spacing.md,
        borderRadius: radius,
        borderWidth: 1,
        borderColor: colors.warning,
        backgroundColor: colors.surface,
      }}
    >
      {/* A glyph and words, not a colour: the warning has to survive a greyscale read. */}
      <Text style={{ color: colors.text, fontSize: fontSize.label, flex: 1 }}>
        ⚠ Calendar access is off, so only your manual blocks count.
      </Text>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Allow calendar access"
        accessibilityState={{ disabled: working }}
        disabled={working}
        onPress={() => void onAllow()}
        style={{
          minHeight: touchTarget,
          minWidth: touchTarget,
          alignItems: 'center',
          justifyContent: 'center',
          paddingHorizontal: spacing.md,
          borderRadius: radius,
          backgroundColor: colors.accent,
        }}
      >
        {working ? (
          <ActivityIndicator color={colors.accentText} />
        ) : (
          <Text style={{ color: colors.accentText, fontSize: fontSize.label }}>Allow</Text>
        )}
      </Pressable>
    </View>
  );
}
