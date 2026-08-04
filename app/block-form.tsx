import { DateTimePickerAndroid } from '@react-native-community/datetimepicker';
import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { BlockRow } from '../backend/src/wire';
import { ApiError, api, type NewBlock } from '../src/api';
import { RecurrencePicker } from '../src/components/RecurrencePicker';
import { useStore } from '../src/store';
import { fontSize, radius, spacing, touchTarget, useColors } from '../src/theme';
import { formatLocalDateTime, fromPickerDate, toPickerDate } from '../src/time';

/**
 * The block form, reached from the Calendar tab: the FAB with a `start` prefill, or a tap on your own
 * manual block with its `id`. A google-sourced block never routes here — it is read-only server-side
 * (403 `read_only_block`) and the Calendar shows it in a sheet with no edit affordance.
 *
 * Validation is local for the two things a user can fix instantly (a title, and an end after the
 * start) and server-driven for everything else: the 400 codes below are the same list
 * `backend/src/routes/blocks.ts` can return, translated once here.
 */

/** §2's category list. Values are what goes on the wire; `null` is "no category". */
const CATEGORIES = [
  'work',
  'study',
  'commute',
  'exercise',
  'social',
  'meals',
  'sleep',
  'personal',
  'other',
] as const;

const TYPES: { value: BlockRow['type']; label: string; hint: string }[] = [
  { value: 'busy', label: 'Busy', hint: 'Blocks out the time for both of you.' },
  { value: 'tentative', label: 'Tentative', hint: 'Might happen — still blocks out the time.' },
  { value: 'free', label: 'Free', hint: 'Ignored when we look for shared free time.' },
];

/** Only the codes a user can act on. Anything else shows its code, which is better than a lie. */
const MESSAGES: Record<string, string> = {
  invalid_title: 'Give the block a title.',
  invalid_interval: 'The end has to be after the start.',
  invalid_timezone: 'That timezone is not one we can use. Change it in Settings.',
  invalid_recurrence_rule: 'That repeat rule is not one we can store.',
  unsupported_recurrence_freq: 'That repeat frequency is not supported.',
  read_only_block: 'This block comes from Google Calendar. Change it there instead.',
  forbidden: 'That block is not yours to change.',
  no_session: 'You are signed out. Sign in and try again.',
};

export default function BlockFormScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ id?: string; start?: string }>();
  const user = useStore((s) => s.user);
  // The Calendar tab is the only way in, and it has already loaded the week — so the block is in the
  // store, and there is no fetch-by-id path to keep in sync with it.
  const block = useStore((s) => s.blocks.find((b) => b.id === params.id)) ?? null;

  const coupleId = user?.couple_id ?? null;
  // A block is authored in the author's zone, and an existing one keeps its own: that zone is what the
  // server anchors recurrence to (§0.3), so re-saving in a different one would move every occurrence.
  const zone = block?.timezone ?? user?.timezone ?? 'UTC';
  const start = Number(params.start) || Date.now();

  const [title, setTitle] = useState(block?.title ?? '');
  const [type, setType] = useState<BlockRow['type']>(block?.type ?? 'busy');
  const [category, setCategory] = useState<string | null>(block?.category ?? null);
  const [startUtc, setStartUtc] = useState(block?.start_utc ?? start);
  const [endUtc, setEndUtc] = useState(block?.end_utc ?? start + 3_600_000);
  const [rule, setRule] = useState<string | null>(block?.recurrence_rule ?? null);
  const [visibility, setVisibility] = useState<BlockRow['visibility']>(
    block?.visibility ?? 'bothPartners',
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * Android shows the date and the time as two separate dialogs, so they are chained: the date dialog
   * hands back the chosen day carrying the seed's hour and minute, and that Date seeds the time dialog.
   * Both dialogs speak *device* wall clock, so the block's own zone is applied once, at the end — see
   * toPickerDate/fromPickerDate. Dismissing either dialog changes nothing, which is what cancel means.
   */
  function pickDateTime(current: number, apply: (at: number) => void) {
    DateTimePickerAndroid.open({
      value: toPickerDate(current, zone),
      mode: 'date',
      onValueChange: (_event, day) =>
        DateTimePickerAndroid.open({
          value: day,
          mode: 'time',
          is24Hour: true, // every time in this app is rendered HH:mm; the dial should match

          onValueChange: (_timeEvent, at) => apply(fromPickerDate(at, zone)),
        }),
    });
  }

  // Moving the start past the end keeps the block's length rather than leaving an interval the save
  // button will only reject.
  function applyStart(at: number) {
    const length = Math.max(endUtc - startUtc, 60_000);
    setStartUtc(at);
    if (at >= endUtc) setEndUtc(at + length);
  }

  function localProblem(): string | null {
    if (!title.trim()) return 'Give the block a title.';
    if (endUtc <= startUtc) return 'The end has to be after the start.';
    return null;
  }

  function report(err: unknown) {
    const code = err instanceof ApiError ? err.code : 'unknown';
    setError(MESSAGES[code] ?? `Could not save that (${code}).`);
  }

  async function onSave() {
    const problem = localProblem();
    if (problem !== null) return setError(problem);
    if (!coupleId) return setError('You are not paired yet.');

    const body: NewBlock = {
      title: title.trim(),
      type,
      category,
      start_utc: startUtc,
      end_utc: endUtc,
      timezone: zone,
      recurrence_rule: rule,
      visibility,
    };

    setBusy(true);
    setError(null);
    try {
      if (block) await api.updateBlock(coupleId, block.id, body);
      else await api.createBlock(coupleId, body);
      // Refetched here as well as on the WS `block:set`, because the socket may be down and a write
      // that does not appear on the grid reads as a write that failed. A failure is not fatal: the
      // write already succeeded, and the Calendar refetches on its next week change.
      const { visibleRange, setBlocks } = useStore.getState();
      if (visibleRange) {
        await api
          .listBlocks(coupleId, visibleRange.from, visibleRange.to)
          .then(setBlocks)
          .catch(() => undefined);
      }
      router.back();
    } catch (err) {
      report(err);
    } finally {
      setBusy(false);
    }
  }

  function onDelete() {
    if (!block || !coupleId) return;
    Alert.alert(
      'Delete this block?',
      `"${block.title ?? 'Busy'}" and every repeat of it will be removed, for both of you.`,
      [
        { text: 'Keep it', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            setBusy(true);
            api
              .deleteBlock(coupleId, block.id)
              .then(() => {
                useStore.getState().removeBlock(block.id);
                router.back();
              })
              .catch(report)
              .finally(() => setBusy(false));
          },
        },
      ],
    );
  }

  const chip = (label: string, selected: boolean, onPress: () => void) => (
    <Pressable
      key={label}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={{
        minHeight: touchTarget,
        minWidth: touchTarget,
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: spacing.md,
        borderRadius: radius,
        // Tick plus border weight plus fill: selection must survive greyscale.
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

  const when = (label: string, at: number, apply: (v: number) => void, problem?: string) => (
    <View style={{ gap: spacing.xs }}>
      <Text style={{ color: colors.text, fontSize: fontSize.label }}>{label}</Text>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`${label} ${formatLocalDateTime(at, zone)}. Opens a date and time picker.`}
        onPress={() => pickDateTime(at, apply)}
        style={{
          minHeight: touchTarget,
          justifyContent: 'center',
          paddingHorizontal: spacing.md,
          borderRadius: radius,
          borderWidth: 1,
          // Words under the row, not just a red edge: the problem has to survive greyscale.
          borderColor: problem === undefined ? colors.border : colors.danger,
        }}
      >
        <Text style={{ color: colors.text, fontSize: fontSize.body }}>
          {formatLocalDateTime(at, zone)}
        </Text>
      </Pressable>
      {problem === undefined ? null : (
        <Text style={{ color: colors.danger, fontSize: fontSize.caption }}>{problem}</Text>
      )}
    </View>
  );

  return (
    <ScrollView
      style={{ backgroundColor: colors.background }}
      contentContainerStyle={{
        paddingTop: insets.top + spacing.md,
        paddingHorizontal: spacing.lg,
        paddingBottom: insets.bottom + spacing.xl,
        gap: spacing.md,
      }}
      keyboardShouldPersistTaps="handled"
    >
      <Text style={{ color: colors.text, fontSize: fontSize.title }}>
        {block ? 'Edit block' : 'New block'}
      </Text>
      <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
        Times are in {zone.replace(/_/g, ' ')}.
      </Text>

      <View style={{ gap: spacing.xs }}>
        <Text style={{ color: colors.text, fontSize: fontSize.label }}>Title</Text>
        <TextInput
          accessibilityLabel="Block title"
          value={title}
          onChangeText={setTitle}
          placeholder="Gym, standup, dinner…"
          placeholderTextColor={colors.textMuted}
          style={{
            minHeight: touchTarget,
            paddingHorizontal: spacing.md,
            borderRadius: radius,
            borderWidth: 1,
            borderColor: colors.border,
            color: colors.text,
            fontSize: fontSize.body,
          }}
        />
      </View>

      <View style={{ gap: spacing.sm }}>
        <Text style={{ color: colors.text, fontSize: fontSize.label }}>Type</Text>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}>
          {TYPES.map((t) => chip(t.label, t.value === type, () => setType(t.value)))}
        </View>
        <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
          {TYPES.find((t) => t.value === type)?.hint}
        </Text>
      </View>

      {when('Starts', startUtc, applyStart)}
      {when(
        'Ends',
        endUtc,
        setEndUtc,
        endUtc <= startUtc ? 'The end has to be after the start.' : undefined,
      )}

      <RecurrencePicker value={rule} startUtc={startUtc} zone={zone} onChange={setRule} />

      <View style={{ gap: spacing.sm }}>
        <Text style={{ color: colors.text, fontSize: fontSize.label }}>Category</Text>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}>
          {chip('None', category === null, () => setCategory(null))}
          {CATEGORIES.map((c) => chip(c, c === category, () => setCategory(c)))}
        </View>
      </View>

      <View style={{ gap: spacing.sm }}>
        <Text style={{ color: colors.text, fontSize: fontSize.label }}>Who sees the details</Text>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}>
          {chip('Both of us', visibility === 'bothPartners', () => setVisibility('bothPartners'))}
          {chip('Only me', visibility === 'onlyMe', () => setVisibility('onlyMe'))}
        </View>
        {/* Said plainly, because this control was a no-op in the previous build and its name suggests
            the block is hidden. It is not: only the title and category are. */}
        <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
          {visibility === 'onlyMe'
            ? 'Only me: your partner sees this time as “Busy” with no title or category. The time is still blocked out, so it still shapes your shared free time.'
            : 'Both of us: your partner sees the title and category of this block.'}
        </Text>
      </View>

      {error ? (
        <Text style={{ color: colors.danger, fontSize: fontSize.label }}>{error}</Text>
      ) : null}

      <Pressable
        accessibilityRole="button"
        accessibilityState={{ disabled: busy }}
        disabled={busy}
        onPress={() => void onSave()}
        style={{
          minHeight: touchTarget,
          alignItems: 'center',
          justifyContent: 'center',
          borderRadius: radius,
          backgroundColor: colors.accent,
          opacity: busy ? 0.6 : 1,
        }}
      >
        {busy ? (
          <ActivityIndicator color={colors.accentText} />
        ) : (
          <Text style={{ color: colors.accentText, fontSize: fontSize.body }}>
            {block ? 'Save changes' : 'Add block'}
          </Text>
        )}
      </Pressable>

      <Pressable
        accessibilityRole="button"
        onPress={() => router.back()}
        style={{
          minHeight: touchTarget,
          alignItems: 'center',
          justifyContent: 'center',
          borderRadius: radius,
          backgroundColor: colors.surface,
        }}
      >
        <Text style={{ color: colors.text, fontSize: fontSize.body }}>Cancel</Text>
      </Pressable>

      {block ? (
        <Pressable
          accessibilityRole="button"
          accessibilityState={{ disabled: busy }}
          disabled={busy}
          onPress={onDelete}
          style={{
            minHeight: touchTarget,
            alignItems: 'center',
            justifyContent: 'center',
            borderRadius: radius,
            borderWidth: 1,
            borderColor: colors.danger,
          }}
        >
          <Text style={{ color: colors.danger, fontSize: fontSize.body }}>Delete block</Text>
        </Pressable>
      ) : null}
    </ScrollView>
  );
}
