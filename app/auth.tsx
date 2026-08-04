import { useState } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';

import { signInWithGoogle } from '../src/auth';
import { fontSize, radius, spacing, touchTarget, useColors } from '../src/theme';

// Task 12 lays this screen out properly. What matters here is the wiring: one button, the privacy
// sentence next to it (this is where the consent actually happens), and a visible failure.
export default function AuthScreen() {
  const colors = useColors();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onPress() {
    setBusy(true);
    setError(null);
    try {
      // Resolves without signing in when the user cancels; the auth listener in _layout does the
      // rest when it does succeed.
      await signInWithGoogle();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'sign-in failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <View
      style={{
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        gap: spacing.md,
        padding: spacing.lg,
        backgroundColor: colors.background,
      }}
    >
      <Text style={{ color: colors.text, fontSize: fontSize.title }}>Couple Sync</Text>
      <Text style={{ color: colors.textMuted, fontSize: fontSize.body, textAlign: 'center' }}>
        Find the hours you are both free.
      </Text>

      <Pressable
        accessibilityRole="button"
        accessibilityState={{ disabled: busy }}
        disabled={busy}
        onPress={() => void onPress()}
        style={{
          minHeight: touchTarget,
          minWidth: 4 * touchTarget,
          alignItems: 'center',
          justifyContent: 'center',
          paddingHorizontal: spacing.lg,
          borderRadius: radius,
          backgroundColor: colors.accent,
          opacity: busy ? 0.6 : 1,
        }}
      >
        {busy ? (
          <ActivityIndicator color={colors.accentText} />
        ) : (
          <Text style={{ color: colors.accentText, fontSize: fontSize.body }}>
            Continue with Google
          </Text>
        )}
      </Pressable>

      {/* Stated where the consent happens, not buried in Settings. */}
      <Text style={{ color: colors.textMuted, fontSize: fontSize.caption, textAlign: 'center' }}>
        Signing in also connects your Google Calendar. We read only busy/free times, never event
        titles.
      </Text>

      {error ? (
        <Text style={{ color: colors.danger, fontSize: fontSize.label, textAlign: 'center' }}>
          {error}
        </Text>
      ) : null}
    </View>
  );
}
