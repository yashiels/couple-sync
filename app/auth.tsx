import { useState } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';

import { signInWithGoogle } from '../src/auth';
import { fontSize, radius, spacing, touchTarget, useColors } from '../src/theme';

/**
 * One button is the whole screen. Google is the only sign-in method (§1) and signing in *is* how the
 * calendar gets connected, so there is no provider list, no second button, and no later "connect your
 * calendar" step — which is why the privacy sentence sits next to this button: the consent happens
 * here.
 */
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
      // The native cause is kept verbatim underneath the sentence on purpose: the two failures that
      // actually happen here are a missing SHA-1 fingerprint and a Play-services-less device, and
      // both are diagnosable only from Google's own code (`DEVELOPER_ERROR`).
      setError(err instanceof Error && err.message ? err.message : 'unknown error');
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
        <View style={{ gap: spacing.xs }}>
          <Text style={{ color: colors.danger, fontSize: fontSize.label, textAlign: 'center' }}>
            Sign-in failed. Check your connection and try again.
          </Text>
          <Text style={{ color: colors.textMuted, fontSize: fontSize.caption, textAlign: 'center' }}>
            {error}
          </Text>
        </View>
      ) : null}
    </View>
  );
}
