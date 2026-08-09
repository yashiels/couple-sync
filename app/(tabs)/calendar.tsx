import { MaterialIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { DateTime } from 'luxon';
import { useEffect, useMemo, useState, type ComponentProps } from 'react';
import { Modal, Pressable, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { BlockWithOccurrences, OverlapWindow } from '../../backend/src/wire';
import { api } from '../../src/api';
import { WeekGrid } from '../../src/components/WeekGrid';
import { WindowCard } from '../../src/components/WindowCard';
import { describeRrule } from '../../src/recurrence';
import { useStore } from '../../src/store';
import { fontSize, radius, spacing, touchTarget, useColors } from '../../src/theme';
import { formatDuration, formatWindowRange, weekIndex, weekRange } from '../../src/time';

/**
 * Calendar — and the block-management surface, because there is no Blocks tab (§1). Tapping your own
 * block opens the form on it; the FAB opens an empty one.
 *
 * Three tap behaviours, and the differences are deliberate:
 *  - your own manual block → the form, prefilled.
 *  - a google-sourced block → a read-only sheet with **no** edit affordance. `PATCH /blocks/:id`
 *    answers 403 `read_only_block` for those, so an edit path would be a dead end.
 *  - your partner's block → a read-only sheet. A null title means the server already nulled it for an
 *    `onlyMe` block, so it reads "Busy". There is no second, client-side scrub: adding one would mask
 *    a server-side regression instead of exposing it.
 */

type Sheet =
  /** The tapped occurrence travels with the block: a recurring block's row carries the *series*
   *  start, and showing that for a Wednesday instance would name the wrong date. */
  | { kind: 'block'; block: BlockWithOccurrences; occurrence: Occurrence }
  | { kind: 'window'; window: OverlapWindow }
  | null;

type Occurrence = { start_utc: number; end_utc: number };

export default function CalendarScreen() {
  const colors = useColors();
  const insets = useSafeAreaInsets();
  const user = useStore((s) => s.user);
  const partner = useStore((s) => s.partner);
  const blocks = useStore((s) => s.blocks);
  const windows = useStore((s) => s.windows);

  // The guard chain only mounts the tabs for a user with a timezone and a couple_id, so these
  // fallbacks are unreachable — they exist so this screen needs no non-null assertion.
  const coupleId = user?.couple_id ?? null;
  const zone = user?.timezone ?? 'UTC';
  const viewerUid = user?.uid ?? '';
  const partnerName = partner?.display_name ?? 'Your partner';
  const partnerZone = partner?.timezone ?? zone;

  // Page indices are absolute, anchored on a fixed epoch Monday (src/time.ts), so paging is
  // deterministic instead of relative to whenever the tab happened to open. The clock is read once
  // on mount rather than during render — this screen has no ticking clock, so a stable read is both
  // correct and pure (react-hooks/purity).
  const [mountedAt] = useState(() => Date.now());
  const todayIndex = useMemo(() => weekIndex(mountedAt, zone), [mountedAt, zone]);
  const [index, setIndex] = useState(todayIndex);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sheet, setSheet] = useState<Sheet>(null);

  const { from, to } = useMemo(() => weekRange(index, zone), [index, zone]);

  useEffect(() => {
    if (!coupleId) return;
    // visibleRange is set BEFORE the fetch and on every week change: src/ws.ts reads it to decide
    // which range to refetch on a `block:set` / `blocks:changed`, so a stale or unset range silently
    // kills live updates from the partner.
    useStore.getState().setVisibleRange(from, to);

    let cancelled = false;
    // A fetch on mount/week-change is what an effect is for, and the spinner has to flip before the
    // request goes out.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setLoading(true);
    setError(null);
    api
      .listBlocks(coupleId, from, to)
      .then((fetched) => {
        if (!cancelled) useStore.getState().setBlocks(fetched);
      })
      .catch(() => {
        if (!cancelled) setError('Could not load this week. Check your connection.');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [coupleId, from, to]);

  const monday = DateTime.fromMillis(from, { zone });
  const sunday = monday.plus({ days: 6 });
  const weekLabel = `${monday.toFormat('d MMM')} – ${sunday.toFormat('d MMM yyyy')}`;
  const topScore = windows.reduce((max, w) => Math.max(max, w.score), -Infinity);

  /** The form's default start: the next whole hour, or 09:00 Monday on a week you are only browsing. */
  const defaultStart =
    index === todayIndex
      ? DateTime.now().setZone(zone).plus({ hours: 1 }).startOf('hour').toMillis()
      : monday.set({ hour: 9 }).toMillis();

  function openBlock(block: BlockWithOccurrences, occurrence: Occurrence) {
    // Own manual block only. A google block is read-only server-side and a partner's block is not
    // yours to edit, so both get the sheet.
    if (block.user_id === viewerUid && block.source === 'manual') {
      router.push({ pathname: '/block-form', params: { id: block.id } });
      return;
    }
    setSheet({ kind: 'block', block, occurrence });
  }

  const iconButton = (
    label: string,
    icon: ComponentProps<typeof MaterialIcons>['name'],
    onPress: () => void,
  ) => (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      style={{
        minHeight: touchTarget,
        minWidth: touchTarget,
        alignItems: 'center',
        justifyContent: 'center',
        borderRadius: radius,
        borderWidth: 1,
        borderColor: colors.border,
      }}
    >
      <MaterialIcons name={icon} size={fontSize.heading} color={colors.text} />
    </Pressable>
  );

  const sheetBody = (() => {
    if (sheet === null) return null;
    if (sheet.kind === 'window') {
      const { window } = sheet;
      return (
        <>
          <Text style={{ color: colors.text, fontSize: fontSize.heading }}>Free together</Text>
          {/* WindowCard, not a re-implementation: it already formats both zones, the duration, the
              best-match marker and the late-night marker. */}
          <WindowCard
            window={window}
            yourZone={zone}
            partnerName={partnerName}
            partnerZone={partnerZone}
            best={window.score === topScore}
          />
          <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
            Your zone {zone.replace(/_/g, ' ')} · {partnerName} {partnerZone.replace(/_/g, ' ')}
          </Text>
          <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
            {formatDuration(window.durationMinutes)} long · score {window.score.toFixed(1)}
            {window.reasonableBoth ? '' : ' · may run outside waking hours'}
          </Text>
        </>
      );
    }

    const { block, occurrence } = sheet;
    const mine = block.user_id === viewerUid;
    const repeat = describeRrule(block.recurrence_rule);
    return (
      <>
        <Text style={{ color: colors.text, fontSize: fontSize.heading }}>
          {block.title ?? 'Busy'}
        </Text>
        <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
          {formatWindowRange({ startUtc: occurrence.start_utc, endUtc: occurrence.end_utc }, zone)}
        </Text>
        <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
          {mine ? 'Yours' : `${partnerName}'s`} · {block.type}
          {block.category ? ` · ${block.category}` : ''}
        </Text>
        {repeat ? (
          <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>{repeat}</Text>
        ) : null}
        {block.source === 'google' ? (
          <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: spacing.xs }}>
            <MaterialIcons name="lock" size={fontSize.label} color={colors.textMuted} />
            <Text style={{ color: colors.text, fontSize: fontSize.label, flex: 1 }}>
              From Google Calendar. We only ever read busy and free times, never event titles. Change
              it in Google Calendar and it updates here on the next sync.
            </Text>
          </View>
        ) : block.title === null ? (
          <Text style={{ color: colors.text, fontSize: fontSize.label }}>
            {partnerName} kept the details of this one private. The time is still blocked out.
          </Text>
        ) : (
          <Text style={{ color: colors.textMuted, fontSize: fontSize.label }}>
            Only {mine ? 'you' : partnerName} can change this.
          </Text>
        )}
      </>
    );
  })();

  return (
    <View
      style={{
        flex: 1,
        paddingTop: insets.top + spacing.md,
        paddingHorizontal: spacing.md,
        paddingBottom: insets.bottom,
        gap: spacing.sm,
        backgroundColor: colors.background,
      }}
    >
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.sm }}>
        {iconButton('Previous week', 'chevron-left', () => setIndex((i) => i - 1))}
        <View style={{ flex: 1 }}>
          <Text numberOfLines={1} style={{ color: colors.text, fontSize: fontSize.heading }}>
            {weekLabel}
          </Text>
          <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
            {loading ? 'Loading…' : `Times in ${zone.replace(/_/g, ' ')}`}
          </Text>
        </View>
        {index === todayIndex ? null : (
          <Pressable
            accessibilityRole="button"
            onPress={() => setIndex(todayIndex)}
            style={{
              minHeight: touchTarget,
              minWidth: touchTarget,
              alignItems: 'center',
              justifyContent: 'center',
              paddingHorizontal: spacing.sm,
              borderRadius: radius,
              borderWidth: 1,
              borderColor: colors.accent,
            }}
          >
            <Text style={{ color: colors.accent, fontSize: fontSize.label }}>Today</Text>
          </Pressable>
        )}
        {iconButton('Next week', 'chevron-right', () => setIndex((i) => i + 1))}
      </View>

      {error ? (
        <Text style={{ color: colors.danger, fontSize: fontSize.label }}>{error}</Text>
      ) : null}

      <WeekGrid
        weekStartUtc={from}
        zone={zone}
        blocks={blocks}
        windows={windows}
        viewerUid={viewerUid}
        partnerName={partnerName}
        today={mountedAt}
        onPressBlock={openBlock}
        onPressWindow={(window) => setSheet({ kind: 'window', window })}
      />

      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Add a block"
        onPress={() =>
          router.push({ pathname: '/block-form', params: { start: String(defaultStart) } })
        }
        style={{
          position: 'absolute',
          right: spacing.lg,
          bottom: insets.bottom + spacing.lg,
          width: 56,
          height: 56,
          alignItems: 'center',
          justifyContent: 'center',
          borderRadius: 28,
          backgroundColor: colors.accent,
        }}
      >
        <MaterialIcons name="add" size={fontSize.title} color={colors.accentText} />
      </Pressable>

      <Modal
        visible={sheet !== null}
        transparent
        animationType="slide"
        onRequestClose={() => setSheet(null)}
      >
        {/* accessible={false} on the backdrop: labelling a full-screen Pressable as a button would
            swallow the sheet's own content for a screen reader. Dismissal is the Close button below,
            or the Android back button via onRequestClose. */}
        <Pressable
          accessible={false}
          onPress={() => setSheet(null)}
          style={{ flex: 1, backgroundColor: '#00000088', justifyContent: 'flex-end' }}
        >
          {/* Stops a tap inside the sheet from closing it; the backdrop above is the dismissal. */}
          <Pressable
            onPress={() => undefined}
            style={{
              gap: spacing.sm,
              padding: spacing.lg,
              paddingBottom: insets.bottom + spacing.lg,
              borderTopLeftRadius: radius * 2,
              borderTopRightRadius: radius * 2,
              backgroundColor: colors.background,
            }}
          >
            {sheetBody}
            <Pressable
              accessibilityRole="button"
              onPress={() => setSheet(null)}
              style={{
                minHeight: touchTarget,
                alignItems: 'center',
                justifyContent: 'center',
                borderRadius: radius,
                backgroundColor: colors.surface,
              }}
            >
              <Text style={{ color: colors.text, fontSize: fontSize.body }}>Close</Text>
            </Pressable>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}
