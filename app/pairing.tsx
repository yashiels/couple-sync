import { MaterialIcons } from '@expo/vector-icons';
import * as Clipboard from 'expo-clipboard';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  Share,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { ApiError, api } from '../src/api';
import { hydrateFromServer } from '../src/auth';
import { CODE_LENGTH, normalizeInviteCode, redeemErrorMessage } from '../src/invites';
import { useStore } from '../src/store';
import { fontSize, radius, spacing, touchTarget, useColors } from '../src/theme';
import { formatCountdown } from '../src/time';

/**
 * Pairing. Two tabs, and the two sides leave this screen by different routes:
 *
 * - the **inviter** never touches the Enter tab. `POST /invites/:code/redeem` sends them a WS
 *   `pairing` message, `src/ws.ts` hydrates on it, and the guard chain swaps the navigator. Which is
 *   why there is no polling loop here — the old build polled every 3 s to discover its own pairing.
 * - the **redeemer** gets only `{ couple_id }` over HTTP; no WS message goes to themselves. Their
 *   local row still has `couple_id: null` and the guard reads exactly that, so the redeem path calls
 *   `hydrateFromServer()`, whose `api.me()` refetch is the thing that actually flips the guard.
 *
 * Blocks are deliberately not fetched on either path: `listBlocks` needs a from/to range and none
 * exists until the Calendar tab sets `visibleRange`.
 */
export default function PairingScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const pendingInviteCode = useStore((s) => s.pendingInviteCode);

  const [tab, setTab] = useState<'share' | 'enter'>('share');

  const [invite, setInvite] = useState<{ code: string; expires_at: number } | null>(null);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const [code, setCode] = useState('');
  const [redeeming, setRedeeming] = useState(false);
  const [redeemError, setRedeemError] = useState<string | null>(null);

  // A couplesync://invite/CODE link parked by app/_layout.tsx, either before sign-in or while this
  // screen is open. Cleared as soon as it is read: it has been consumed, and leaving it set would
  // overwrite whatever the user types next.
  useEffect(() => {
    if (!pendingInviteCode) return;
    // The deep link arrives from outside React (expo-linking, via the store), so syncing it into
    // local state is what an effect is for.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setCode(normalizeInviteCode(pendingInviteCode));
    setTab('enter');
    useStore.getState().setPendingInvite(null);
  }, [pendingInviteCode]);

  // Minted when the Share tab is first shown rather than on mount, so arriving on the Enter tab from
  // a deep link does not create a code nobody will ever read. Retried only by the button below.
  useEffect(() => {
    if (tab !== 'share' || invite || creating || createError) return;
    // Minting the code is a request, and the in-flight flag has to be set before it goes out or the
    // effect re-enters.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setCreating(true);
    api
      .createInvite()
      .then(setInvite)
      .catch((err: unknown) =>
        setCreateError(
          err instanceof ApiError && err.code === 'already_paired'
            ? 'You are already paired.'
            : 'Could not create a code. Check your connection and try again.',
        ),
      )
      .finally(() => setCreating(false));
  }, [tab, invite, creating, createError]);

  async function onShare() {
    if (!invite) return;
    try {
      // Ceiling: a custom-scheme URL is only tappable in apps that linkify unknown schemes, so the
      // code itself is in the message too. The upgrade path is the https App Link on the Firebase
      // Hosting domain, which needs assetlinks.json published.
      await Share.share({
        message: `Pair with me on Couple Sync. My code is ${invite.code} — couplesync://invite/${invite.code}`,
      });
    } catch {
      // Dismissing the sheet is not a failure and there is nothing to report.
    }
  }

  async function onRedeem() {
    setRedeeming(true);
    setRedeemError(null);
    try {
      await api.redeemInvite(code);
    } catch (err) {
      setRedeemError(
        err instanceof ApiError
          ? redeemErrorMessage(err.code, err.status)
          : 'Could not pair. Try again.',
      );
      setRedeeming(false);
      return;
    }
    try {
      // Refetches api.me() and is what flips the guard; this screen then leaves the navigator. It
      // also fires the first-pair handler app/_layout.tsx registered, which is what forces the new
      // couple's first calendar sync — so there is deliberately no sync(…, { force: true }) call
      // here, which would only make it a second forced sync for the same transition.
      await hydrateFromServer();
    } catch {
      // The pairing committed server-side, so retrying the redeem would only return invite_used.
      setRedeemError(
        'You are paired, but we could not load it. Check your connection and reopen the app.',
      );
      setRedeeming(false);
    }
  }

  const tabButton = (value: 'share' | 'enter', label: string) => {
    const active = tab === value;
    return (
      <Pressable
        accessibilityRole="tab"
        accessibilityState={{ selected: active }}
        onPress={() => setTab(value)}
        style={{
          flex: 1,
          minHeight: touchTarget,
          alignItems: 'center',
          justifyContent: 'center',
          // A weight change and an underline, not just a hue: the active tab must survive a
          // colour-blind or greyscale read.
          borderBottomWidth: active ? 2 : 1,
          borderBottomColor: active ? colors.accent : colors.border,
        }}
      >
        <Text
          style={{
            color: active ? colors.text : colors.textMuted,
            fontSize: fontSize.body,
            fontWeight: active ? '700' : '400',
          }}
        >
          {label}
        </Text>
      </Pressable>
    );
  };

  const primaryButton = {
    minHeight: touchTarget,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: spacing.lg,
    borderRadius: radius,
    backgroundColor: colors.accent,
  } as const;

  return (
    <KeyboardAvoidingView
      style={{ flex: 1 }}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={0}
    >
      <View
        style={{
          flex: 1,
          paddingTop: insets.top + spacing.md,
          paddingHorizontal: spacing.lg,
          paddingBottom: insets.bottom + spacing.md,
          gap: spacing.md,
          backgroundColor: colors.background,
        }}
      >
        <Text style={{ color: colors.text, fontSize: fontSize.title }}>Pair with your partner</Text>

        <View accessibilityRole="tablist" style={{ flexDirection: 'row' }}>
          {tabButton('share', 'Share a code')}
          {tabButton('enter', 'Enter a code')}
        </View>

        {tab === 'share' ? (
          <View style={{ gap: spacing.md }}>
            <Text style={{ color: colors.textMuted, fontSize: fontSize.body }}>
              Send this code to your partner. It works once.
            </Text>

            {creating ? <ActivityIndicator color={colors.accent} /> : null}

            {createError ? (
              <>
                <Text style={{ color: colors.danger, fontSize: fontSize.label }}>{createError}</Text>
                <Pressable
                  accessibilityRole="button"
                  onPress={() => setCreateError(null)}
                  style={primaryButton}
                >
                  <Text style={{ color: colors.accentText, fontSize: fontSize.body }}>Try again</Text>
                </Pressable>
              </>
            ) : null}

            {invite ? (
              <>
                <View
                  style={{
                    padding: spacing.md,
                    borderRadius: radius,
                    backgroundColor: colors.surface,
                    alignItems: 'center',
                    gap: spacing.xs,
                  }}
                >
                  <Text
                    accessibilityLabel={`Your code is ${invite.code.split('').join(' ')}`}
                    selectable
                    style={{ color: colors.text, fontSize: fontSize.title, letterSpacing: 4 }}
                  >
                    {invite.code}
                  </Text>
                  <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
                    Expires {formatCountdown(invite.expires_at)}
                  </Text>
                </View>

                <Pressable
                  accessibilityRole="button"
                  onPress={() => void onShare()}
                  style={primaryButton}
                >
                  <Text style={{ color: colors.accentText, fontSize: fontSize.body }}>Share code</Text>
                </Pressable>

                <Pressable
                  accessibilityRole="button"
                  onPress={() => {
                    void Clipboard.setStringAsync(invite.code);
                    setCopied(true);
                  }}
                  style={{
                    ...primaryButton,
                    backgroundColor: colors.surface,
                    borderWidth: 1,
                    borderColor: colors.border,
                  }}
                >
                  {copied ? (
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xs }}>
                      <MaterialIcons name="check" size={fontSize.body} color={colors.text} />
                      <Text style={{ color: colors.text, fontSize: fontSize.body }}>Copied</Text>
                    </View>
                  ) : (
                    <Text style={{ color: colors.text, fontSize: fontSize.body }}>Copy code</Text>
                  )}
                </Pressable>

                <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
                  Keep this screen open — you will go straight in when your partner enters the code.
                </Text>
              </>
            ) : null}
          </View>
        ) : (
          <View style={{ gap: spacing.md }}>
            <Text style={{ color: colors.textMuted, fontSize: fontSize.body }}>
              Type the code your partner sent you.
            </Text>

            <TextInput
              accessibilityLabel="Invite code"
              placeholder="ABC234"
              placeholderTextColor={colors.textMuted}
              value={code}
              // Upper-cased and filtered as it is typed, so the field always shows the same six
              // characters the partner was given.
              onChangeText={(text) => setCode(normalizeInviteCode(text))}
              autoCapitalize="characters"
              autoCorrect={false}
              maxLength={CODE_LENGTH}
              style={{
                minHeight: touchTarget,
                paddingHorizontal: spacing.md,
                borderRadius: radius,
                borderWidth: 1,
                borderColor: colors.border,
                color: colors.text,
                fontSize: fontSize.heading,
                letterSpacing: 4,
                textAlign: 'center',
              }}
            />
            <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
              6 characters. A code never contains O, 0, I or 1.
            </Text>

            {redeemError ? (
              <Text style={{ color: colors.danger, fontSize: fontSize.label }}>{redeemError}</Text>
            ) : null}

            <Pressable
              accessibilityRole="button"
              accessibilityState={{ disabled: redeeming || code.length < CODE_LENGTH }}
              disabled={redeeming || code.length < CODE_LENGTH}
              onPress={() => void onRedeem()}
              style={{
                ...primaryButton,
                opacity: redeeming || code.length < CODE_LENGTH ? 0.6 : 1,
              }}
            >
              {redeeming ? (
                <ActivityIndicator color={colors.accentText} />
              ) : (
                <Text style={{ color: colors.accentText, fontSize: fontSize.body }}>Pair</Text>
              )}
            </Pressable>
          </View>
        )}
      </View>
    </KeyboardAvoidingView>
  );
}
