import AsyncStorage from '@react-native-async-storage/async-storage';
// The SDK 57 default entry deprecates these read methods and throws at runtime; the stable read API
// (getCalendarsAsync / getEventsAsync / permission getters / SourceType) lives on the /legacy subpath.
import * as Calendar from 'expo-calendar/legacy';

/**
 * Device-calendar busy source (Phase 1 of "pull my whole device calendar"). The OS calendar store
 * already aggregates every account the user has added — personal Google, work Google, iCloud,
 * Exchange — so reading busy intervals from it captures the work calendar without a second OAuth
 * login. Like §5's freebusy rule, only start/end are read here: an event title never leaves this
 * module, so it cannot reach the store or the partner.
 *
 * Ceiling: this reads the local OS store, so it reflects whatever the device has synced. A calendar
 * that only exists in a browser (never added to the phone) is invisible here — that is what the
 * deferred "link work account" Google OAuth path (Phase 2) would cover.
 */

export type BusyInterval = { start_utc: number; end_utc: number };

/**
 * Persisted per-calendar overrides: id → explicit on/off the user chose in Settings. A calendar with
 * no entry falls back to onByDefault(), so a calendar added to the phone *after* the user last toggled
 * (e.g. a new work account) is included automatically instead of defaulting to off.
 */
const OVERRIDES_KEY = 'deviceCalendar.overrides';

export interface DeviceCalendar {
  id: string;
  title: string;
  /** The owning account, e.g. a Google address — shown in the picker so "work" is identifiable. */
  source: string;
  enabled: boolean;
}

/** The library does not re-export its Calendar type by name; derive it from the query it comes from. */
type DeviceCal = Awaited<ReturnType<typeof Calendar.getCalendarsAsync>>[number];

/**
 * A calendar is on by default unless it is the kind that would blanket-block days with things that
 * are not real commitments: birthdays and subscribed (read-only feed, e.g. holidays) calendars. The
 * user can still switch any of these on from Settings.
 */
function onByDefault(cal: DeviceCal): boolean {
  if (cal.source?.type === Calendar.SourceType.BIRTHDAYS) return false;
  if (cal.source?.type === Calendar.SourceType.SUBSCRIBED) return false;
  return true;
}

async function readOverrides(): Promise<Record<string, boolean>> {
  try {
    const raw = await AsyncStorage.getItem(OVERRIDES_KEY);
    return raw ? (JSON.parse(raw) as Record<string, boolean>) : {};
  } catch {
    return {};
  }
}

/** Requests read permission if needed. Returns false on denial — the caller then syncs Google-only. */
export async function ensureCalendarPermission(): Promise<boolean> {
  const { status } = await Calendar.getCalendarPermissionsAsync();
  if (status === 'granted') return true;
  const req = await Calendar.requestCalendarPermissionsAsync();
  return req.status === 'granted';
}

/** For the Settings picker: every device calendar with its current enabled state. */
export async function listDeviceCalendars(): Promise<DeviceCalendar[]> {
  if (!(await ensureCalendarPermission())) return [];
  const cals = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
  const overrides = await readOverrides();
  return cals.map((c) => ({
    id: c.id,
    title: c.title,
    source: c.source?.name ?? '',
    enabled: overrides[c.id] ?? onByDefault(c),
  }));
}

/**
 * Records one calendar's on/off choice. Reads and writes only the overrides map — never the calendar
 * list — so a revoked permission or an empty native result cannot wipe the user's selection.
 */
export async function setCalendarEnabled(id: string, enabled: boolean): Promise<void> {
  const overrides = await readOverrides();
  overrides[id] = enabled;
  await AsyncStorage.setItem(OVERRIDES_KEY, JSON.stringify(overrides));
}

/**
 * Busy intervals from the enabled device calendars over [fromMs, toMs).
 *
 * Return contract distinguishes "no busy times" from "could not read", because the caller replaces
 * the device block set on the server:
 *   - `[]`   permission denied, or genuinely no events / no calendars enabled → the caller CLEARS the
 *            device blocks (correct: the user turned the source off or has nothing).
 *   - `null` a native call THREW → a read failure; the caller SKIPS the device write so a transient
 *            error can never delete previously-synced device blocks.
 *
 * All-day events are dropped: a "Public holiday" or "Anniversary" spanning a whole day is not a real
 * commitment, and letting it block every free window is the opposite of what this app is for. Timed
 * events — the ones that actually occupy time — are what become busy.
 */
export async function deviceBusy(fromMs: number, toMs: number): Promise<BusyInterval[] | null> {
  let granted: boolean;
  try {
    granted = await ensureCalendarPermission();
  } catch {
    return null; // even the permission check can throw natively — treat as a read failure, not denial.
  }
  if (!granted) return [];

  try {
    const enabled = (await listDeviceCalendars()).filter((c) => c.enabled).map((c) => c.id);
    if (enabled.length === 0) return [];
    const events = await Calendar.getEventsAsync(enabled, new Date(fromMs), new Date(toMs));
    const out: BusyInterval[] = [];
    for (const e of events) {
      if (e.allDay) continue;
      // expo-calendar returns ISO strings (or Date on some platforms); Date.parse handles both.
      const start = typeof e.startDate === 'string' ? Date.parse(e.startDate) : e.startDate.getTime();
      const end = typeof e.endDate === 'string' ? Date.parse(e.endDate) : e.endDate.getTime();
      if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) continue;
      // getEventsAsync returns events *overlapping* the range, so one can extend past either edge. Clip
      // to [fromMs, toMs) — positioning an interval on the window, not interval algebra — so no busy
      // time is ever posted outside the range this sync represents.
      const clipStart = Math.max(start, fromMs);
      const clipEnd = Math.min(end, toMs);
      if (clipEnd > clipStart) out.push({ start_utc: clipStart, end_utc: clipEnd });
    }
    return out;
  } catch {
    return null; // native read failure — caller preserves prior device blocks rather than clearing.
  }
}
