import { beforeEach, describe, expect, it, vi } from 'vitest';

// vi.mock calls below are hoisted above these imports by vitest, so the stubs are in place first.
import { deviceBusy, listDeviceCalendars, setCalendarEnabled } from '../deviceCalendar';

// expo-calendar and AsyncStorage are native modules; stub them to exercise the pure mapping/selection
// logic in deviceCalendar.ts. SourceType/EntityTypes only need the members the module reads.
const store: Record<string, string> = {};
vi.mock('@react-native-async-storage/async-storage', () => ({
  default: {
    getItem: async (k: string) => store[k] ?? null,
    setItem: async (k: string, v: string) => void (store[k] = v),
  },
}));

const calMocks = {
  getCalendars: vi.fn(),
  getEvents: vi.fn(),
};
vi.mock('expo-calendar/legacy', () => ({
  SourceType: { BIRTHDAYS: 'birthdays', SUBSCRIBED: 'subscribed', LOCAL: 'local' },
  EntityTypes: { EVENT: 'event' },
  getCalendarPermissionsAsync: async () => ({ status: 'granted' }),
  requestCalendarPermissionsAsync: async () => ({ status: 'granted' }),
  getCalendarsAsync: (...a: unknown[]) => calMocks.getCalendars(...a),
  getEventsAsync: (...a: unknown[]) => calMocks.getEvents(...a),
}));

const CALENDARS = [
  { id: 'work', title: 'Work', source: { name: 'work@corp.com', type: 'local' } },
  { id: 'personal', title: 'Personal', source: { name: 'me@gmail.com', type: 'local' } },
  { id: 'holidays', title: 'Holidays', source: { name: 'Subscribed', type: 'subscribed' } },
];

beforeEach(() => {
  for (const k of Object.keys(store)) delete store[k];
  calMocks.getCalendars.mockReset().mockResolvedValue(CALENDARS);
  calMocks.getEvents.mockReset();
});

describe('device calendar selection', () => {
  it('enables real calendars by default but not subscribed/holiday feeds', async () => {
    const cals = await listDeviceCalendars();
    expect(cals.find((c) => c.id === 'work')?.enabled).toBe(true);
    expect(cals.find((c) => c.id === 'holidays')?.enabled).toBe(false);
  });

  it('queries only the enabled calendars', async () => {
    calMocks.getEvents.mockResolvedValue([]);
    await deviceBusy(0, 1000);
    const [ids] = calMocks.getEvents.mock.calls[0];
    expect(ids).toEqual(['work', 'personal']); // holidays excluded by default
  });

  it('respects an explicit toggle but still defaults a newly-added calendar on', async () => {
    await setCalendarEnabled('personal', false); // user turns one off
    // A new work calendar the user has never seen appears later.
    calMocks.getCalendars.mockResolvedValue([
      ...CALENDARS,
      { id: 'work2', title: 'Work 2', source: { name: 'work2@corp.com', type: 'local' } },
    ]);
    const cals = await listDeviceCalendars();
    expect(cals.find((c) => c.id === 'personal')?.enabled).toBe(false); // honoured override
    expect(cals.find((c) => c.id === 'work2')?.enabled).toBe(true); // new calendar defaults on
  });
});

describe('read-failure contract', () => {
  it('returns null (not []) when a native read throws, so the caller preserves prior blocks', async () => {
    calMocks.getEvents.mockRejectedValue(new Error('native calendar failure'));
    expect(await deviceBusy(0, 1000)).toBeNull();
  });

  it('returns [] when there are simply no events, so the caller clears the source', async () => {
    calMocks.getEvents.mockResolvedValue([]);
    expect(await deviceBusy(0, 1000)).toEqual([]);
  });
});

describe('busy interval mapping', () => {
  it('keeps timed events, drops all-day and malformed ones', async () => {
    calMocks.getEvents.mockResolvedValue([
      { startDate: '2026-01-01T09:00:00.000Z', endDate: '2026-01-01T10:00:00.000Z', allDay: false },
      { startDate: new Date('2026-01-01T12:00:00.000Z'), endDate: new Date('2026-01-01T13:00:00.000Z'), allDay: false },
      { startDate: '2026-01-02T00:00:00.000Z', endDate: '2026-01-03T00:00:00.000Z', allDay: true }, // dropped
      { startDate: '2026-01-01T15:00:00.000Z', endDate: '2026-01-01T15:00:00.000Z', allDay: false }, // zero-length, dropped
    ]);
    const busy = await deviceBusy(0, Date.parse('2026-02-01T00:00:00.000Z'));
    expect(busy).toEqual([
      { start_utc: Date.parse('2026-01-01T09:00:00.000Z'), end_utc: Date.parse('2026-01-01T10:00:00.000Z') },
      { start_utc: Date.parse('2026-01-01T12:00:00.000Z'), end_utc: Date.parse('2026-01-01T13:00:00.000Z') },
    ]);
  });
});
