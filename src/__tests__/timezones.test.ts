import { describe, expect, it } from 'vitest';

// The server's own validator, imported rather than re-described: the point of the assertion below is
// that the picker cannot offer a zone PATCH /users/:uid would reject. tz.ts imports only luxon, so
// nothing backend-shaped is pulled into the app's program.
import { isValidTimezone } from '../../backend/src/tz';
import { allZones, searchZones } from '../timezones';

describe('allZones', () => {
  it('comes from the runtime and is not empty', () => {
    expect(allZones().length).toBeGreaterThan(100);
    expect(allZones()).toContain('Africa/Johannesburg');
    expect(allZones()).toContain('America/New_York');
  });

  it('offers only zones the server accepts', () => {
    // A fixed offset such as '+02:00' passes luxon's own check and is rejected by the server, so
    // "everything we offer is valid" is the assertion that matters, not "nothing starts with +".
    expect(allZones().filter((zone) => !isValidTimezone(zone))).toEqual([]);
  });

  it('is sorted, which is what groups it by region', () => {
    expect([...allZones()].sort()).toEqual([...allZones()]);
  });
});

describe('searchZones', () => {
  it('returns everything for an empty or whitespace query', () => {
    expect(searchZones('')).toEqual(allZones());
    expect(searchZones('   ')).toEqual(allZones());
  });

  it('matches a city name typed with a space instead of an underscore', () => {
    expect(searchZones('new york')).toEqual(['America/New_York']);
  });

  it('ignores case and matches a region prefix', () => {
    const results = searchZones('africa/');
    expect(results.length).toBeGreaterThan(10);
    expect(results.every((zone) => zone.startsWith('Africa/'))).toBe(true);
  });

  it('matches the underscored form of the id too', () => {
    expect(searchZones('New_York')).toEqual(['America/New_York']);
  });

  it('matches a bare city name without its region', () => {
    expect(searchZones('johannesburg')).toEqual(['Africa/Johannesburg']);
  });

  it('returns nothing rather than everything for a non-match', () => {
    expect(searchZones('mars/olympus')).toEqual([]);
  });
});
