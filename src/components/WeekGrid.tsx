import { MaterialIcons } from '@expo/vector-icons';
import { DateTime } from 'luxon';
import { useRef } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';

import type { BlockWithOccurrences, OverlapWindow } from '../../backend/src/wire';
import { fontSize, radius, spacing, touchTarget, useColors } from '../theme';
import { formatDuration, gridPosition } from '../time';

/**
 * Seven day columns × 24 hour rows in the *viewer's* zone, with the couple's overlap windows drawn
 * underneath the blocks.
 *
 * Every rectangle comes from a block's server-supplied `occurrences` array (§0.6b). `recurrence_rule`
 * is never read here: the app has no `rrule` dependency, so a weekly block shows up on three days
 * because the server said it does, not because this file expanded anything. The only arithmetic is
 * `gridPosition`, which turns an already-expanded interval into a rectangle.
 */

const HOUR_HEIGHT = 48;
const PX_PER_MINUTE = HOUR_HEIGHT / 60;
/** Wide enough for a two-digit hour at caption size, narrow enough to leave 7 usable columns. */
const GUTTER = 34;
const DAYS = 7;
const DAY_INDEXES = Array.from({ length: DAYS }, (_, day) => day);
const HOURS = Array.from({ length: 24 }, (_, hour) => hour);

interface Placed {
  dayIndex: number;
  top: number;
  height: number;
}

function place(
  interval: { start_utc: number; end_utc: number },
  zone: string,
  weekStartUtc: number,
): Placed {
  const { dayIndex, topMinutes, heightMinutes } = gridPosition(interval, zone, weekStartUtc);
  return {
    dayIndex,
    top: topMinutes * PX_PER_MINUTE,
    // Never shorter than a touch target: a 30-minute block is 24px of drawn height, and every
    // rectangle here is tappable.
    height: Math.max(heightMinutes * PX_PER_MINUTE, touchTarget),
  };
}

const onGrid = (placed: Placed) => placed.dayIndex >= 0 && placed.dayIndex < DAYS;

export function WeekGrid({
  weekStartUtc,
  zone,
  blocks,
  windows,
  viewerUid,
  partnerName,
  today,
  onPressBlock,
  onPressWindow,
}: {
  /** Local Monday 00:00 of the visible week, from `weekStart()`. */
  weekStartUtc: number;
  /** The viewer's zone. A block authored in another zone renders at the viewer's wall clock. */
  zone: string;
  blocks: BlockWithOccurrences[];
  windows: OverlapWindow[];
  viewerUid: string;
  partnerName: string;
  /** Epoch ms used only to mark today's column. */
  today: number;
  onPressBlock(block: BlockWithOccurrences, occurrence: { start_utc: number; end_utc: number }): void;
  onPressWindow(window: OverlapWindow): void;
}) {
  const colors = useColors();
  const scroll = useRef<ScrollView>(null);
  // One shot, so paging to another week keeps wherever the user scrolled to.
  const scrolledOnce = useRef(false);
  const monday = DateTime.fromMillis(weekStartUtc, { zone });
  const todayIso = DateTime.fromMillis(today, { zone }).toISODate();

  const placedWindows = windows
    .map((window) => ({
      window,
      ...place({ start_utc: window.startUtc, end_utc: window.endUtc }, zone, weekStartUtc),
    }))
    .filter(onGrid);

  // One rectangle per occurrence, so a weekly block yields several with the same block behind them.
  //
  // Ceiling: two blocks at the same hour are drawn on top of each other rather than side by side, so
  // the later one wins the taps. Splitting a column into lanes is the upgrade path; at a couple's
  // handful of blocks a day it has not been worth the layout pass.
  const placedBlocks = blocks
    .flatMap((block) =>
      block.occurrences.map((occurrence, i) => ({
        block,
        occurrence,
        key: `${block.id}-${i}`,
        ...place(occurrence, zone, weekStartUtc),
      })),
    )
    .filter(onGrid);

  const legendItem = (key: string, label: string, icon?: 'lock') => (
    <View key={key} style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xs }}>
      {icon === 'lock' ? (
        <MaterialIcons name="lock" size={fontSize.caption} color={colors.textMuted} />
      ) : null}
      <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>{label}</Text>
    </View>
  );

  const legend = (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.md }}>
      {legendItem('yours', 'Solid: yours')}
      {legendItem('partner', `Dashed: ${partnerName}`)}
      {legendItem('google', 'From Google', 'lock')}
      {legendItem('tentative', '? Tentative')}
      {legendItem('free', 'Shaded: free together')}
    </View>
  );

  const dayHeader = (
    <View style={{ flexDirection: 'row' }}>
      <View style={{ width: GUTTER }} />
      {DAY_INDEXES.map((day) => {
        const date = monday.plus({ days: day });
        const isToday = date.toISODate() === todayIso;
        return (
          <View
            key={day}
            style={{
              flex: 1,
              alignItems: 'center',
              paddingVertical: spacing.xs,
              // A label as well as a tint: the current day must survive greyscale.
              backgroundColor: isToday ? colors.surface : 'transparent',
            }}
          >
            <Text
              style={{
                color: colors.text,
                fontSize: fontSize.caption,
                fontWeight: isToday ? '700' : '400',
              }}
            >
              {date.toFormat('EEE')}
            </Text>
            <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
              {date.toFormat('d')}
            </Text>
            {isToday ? (
              <Text style={{ color: colors.accent, fontSize: fontSize.caption }}>now</Text>
            ) : null}
          </View>
        );
      })}
    </View>
  );

  return (
    <View style={{ flex: 1, gap: spacing.xs }}>
      {legend}
      {dayHeader}
      <ScrollView
        ref={scroll}
        style={{ flex: 1 }}
        // Opens at 07:00 rather than midnight, which is where a day's blocks actually start. Done from
        // onContentSizeChange rather than the `contentOffset` prop: that prop is iOS-only, and Android
        // is the only build target, so it would have been dead code that looked like a feature.
        onContentSizeChange={() => {
          if (scrolledOnce.current) return;
          scrolledOnce.current = true;
          scroll.current?.scrollTo({ y: 7 * HOUR_HEIGHT, animated: false });
        }}
      >
        <View style={{ flexDirection: 'row' }}>
          <View style={{ width: GUTTER }}>
            {HOURS.map((hour) => (
              <View key={hour} style={{ height: HOUR_HEIGHT, alignItems: 'flex-end' }}>
                <Text style={{ color: colors.textMuted, fontSize: fontSize.caption }}>
                  {String(hour).padStart(2, '0')}
                </Text>
              </View>
            ))}
          </View>

          {DAY_INDEXES.map((day) => (
            <View
              key={day}
              style={{ flex: 1, borderLeftWidth: 1, borderLeftColor: colors.border }}
            >
              {/* The hour bands are flow content, so they give the column its height; everything
                  interesting is absolutely positioned over them. */}
              {HOURS.map((hour) => (
                <View
                  key={hour}
                  style={{
                    height: HOUR_HEIGHT,
                    borderTopWidth: 1,
                    borderTopColor: hour === 0 ? 'transparent' : colors.border,
                  }}
                />
              ))}

              {/* Windows first: they are the background layer, and a block drawn over one is exactly
                  the message — that hour is not actually free. */}
              {placedWindows
                .filter((placed) => placed.dayIndex === day)
                .map((placed) => (
                  <Pressable
                    key={`${placed.window.startUtc}-${placed.window.endUtc}`}
                    accessibilityRole="button"
                    accessibilityLabel={`Free together, ${formatDuration(
                      placed.window.durationMinutes,
                    )}. Open details.`}
                    onPress={() => onPressWindow(placed.window)}
                    style={{
                      position: 'absolute',
                      left: 1,
                      right: 1,
                      top: placed.top,
                      height: placed.height,
                      borderRadius: radius / 2,
                      backgroundColor: colors.success,
                      opacity: 0.22,
                    }}
                  />
                ))}

              {placedBlocks
                .filter((placed) => placed.dayIndex === day)
                .map(({ block, occurrence, key, top, height }) => {
                  const mine = block.user_id === viewerUid;
                  const google = block.source === 'google';
                  // A null title means the server nulled it for an onlyMe block, or it is a google
                  // block. Either way "Busy" is all there is — there is deliberately no second,
                  // client-side scrub here, which would mask a server-side regression.
                  const label = block.title ?? 'Busy';
                  // '?' for tentative stays inline text (ASCII); the google lock is a real icon
                  // rendered beside the label, since a MaterialIcons cannot live inside a <Text>.
                  const marker = block.type === 'tentative' ? '? ' : '';
                  return (
                    <Pressable
                      key={key}
                      accessibilityRole="button"
                      accessibilityLabel={[
                        mine ? 'Your block' : `${partnerName}'s block`,
                        label,
                        block.type,
                        google ? 'from Google, read only' : null,
                      ]
                        .filter(Boolean)
                        .join(', ')}
                      onPress={() => onPressBlock(block, occurrence)}
                      style={{
                        position: 'absolute',
                        left: 1,
                        right: 1,
                        top,
                        height,
                        padding: 2,
                        overflow: 'hidden',
                        borderRadius: radius / 2,
                        // Owner is a border style, not a hue: solid is yours, dashed is theirs, and
                        // the legend above says so in words.
                        borderWidth: 1,
                        borderStyle: mine ? 'solid' : 'dashed',
                        borderColor: mine ? colors.accent : colors.textMuted,
                        backgroundColor: mine ? colors.accent : colors.surface,
                        opacity: block.type === 'tentative' ? 0.75 : 1,
                      }}
                    >
                      <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 2 }}>
                        {google ? (
                          <MaterialIcons
                            name="lock"
                            size={fontSize.caption}
                            color={mine ? colors.accentText : colors.text}
                          />
                        ) : null}
                        <Text
                          numberOfLines={2}
                          style={{
                            flex: 1,
                            color: mine ? colors.accentText : colors.text,
                            fontSize: fontSize.caption,
                          }}
                        >
                          {marker}
                          {label}
                        </Text>
                      </View>
                    </Pressable>
                  );
                })}
            </View>
          ))}
        </View>
      </ScrollView>
    </View>
  );
}
