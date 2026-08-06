import { describe, expect, it } from 'vitest';

import { buildRrule, describeRrule, parseRrule, weekdayCode } from '../recurrence';

/**
 * The contract under test is the backend's: `backend/src/routes/blocks.ts` validates every rule with
 * `rrulestr` + `RRule.parseString` and rejects any FREQ outside DAILY|WEEKLY|MONTHLY|YEARLY. A rule
 * this module emits that the server refuses is a 400 the user cannot act on, so the emitted forms are
 * asserted literally rather than round-tripped.
 */
describe('buildRrule', () => {
  it('emits FREQ only for daily and monthly', () => {
    expect(buildRrule({ freq: 'DAILY', byday: [] })).toBe('FREQ=DAILY');
    expect(buildRrule({ freq: 'MONTHLY', byday: [] })).toBe('FREQ=MONTHLY');
  });

  it('emits BYDAY for a weekly rule, comma separated in RRULE weekday codes', () => {
    expect(buildRrule({ freq: 'WEEKLY', byday: ['TU', 'WE'] })).toBe('FREQ=WEEKLY;BYDAY=TU,WE');
  });

  it('drops BYDAY when it is empty rather than emitting BYDAY=', () => {
    // `BYDAY=` fails rrulestr, so the server would answer 400 invalid_recurrence_rule.
    expect(buildRrule({ freq: 'WEEKLY', byday: [] })).toBe('FREQ=WEEKLY');
  });

  it('ignores BYDAY on a frequency where the picker cannot set it', () => {
    expect(buildRrule({ freq: 'DAILY', byday: ['MO'] })).toBe('FREQ=DAILY');
  });

  it('emits no RRULE: prefix and no parameter the backend does not accept', () => {
    const rules = (['DAILY', 'WEEKLY', 'MONTHLY'] as const).map((freq) =>
      buildRrule({ freq, byday: ['MO', 'SA'] }),
    );
    for (const rule of rules) {
      expect(rule.startsWith('FREQ=')).toBe(true);
      for (const part of rule.split(';')) {
        expect(part.split('=')[0]).toMatch(/^(FREQ|BYDAY)$/);
      }
    }
  });
});

describe('parseRrule', () => {
  it('reads back everything buildRrule emits', () => {
    expect(parseRrule('FREQ=WEEKLY;BYDAY=TU,WE')).toEqual({ freq: 'WEEKLY', byday: ['TU', 'WE'] });
    expect(parseRrule('FREQ=DAILY')).toEqual({ freq: 'DAILY', byday: [] });
    expect(parseRrule('FREQ=MONTHLY')).toEqual({ freq: 'MONTHLY', byday: [] });
  });

  it('tolerates the optional RRULE: prefix and lower case, which the server also accepts', () => {
    expect(parseRrule('RRULE:FREQ=WEEKLY;BYDAY=mo')).toEqual({ freq: 'WEEKLY', byday: ['MO'] });
    expect(parseRrule('freq=daily')).toEqual({ freq: 'DAILY', byday: [] });
  });

  it('returns null for no rule at all', () => {
    expect(parseRrule(null)).toBeNull();
    expect(parseRrule('   ')).toBeNull();
  });

  it('returns null for a rule the server accepts but this picker cannot represent', () => {
    // Legal server-side (§3.2), so it must show as "custom" rather than be silently rewritten.
    expect(parseRrule('FREQ=YEARLY')).toBeNull();
    expect(parseRrule('FREQ=WEEKLY;INTERVAL=2')).toBeNull();
    expect(parseRrule('FREQ=DAILY;COUNT=5')).toBeNull();
    expect(parseRrule('FREQ=WEEKLY;UNTIL=20261231T000000Z')).toBeNull();
  });

  it('returns null for a rule the server would reject outright', () => {
    expect(parseRrule('FREQ=HOURLY')).toBeNull();
    expect(parseRrule('BYDAY=MO')).toBeNull(); // no FREQ
    expect(parseRrule('FREQ=WEEKLY;BYDAY=FUNDAY')).toBeNull();
  });
});

describe('describeRrule', () => {
  it('names the weekdays of a weekly rule', () => {
    expect(describeRrule('FREQ=WEEKLY;BYDAY=TU,WE')).toBe('Repeats weekly on Tue, Wed');
  });

  it('describes the simple frequencies', () => {
    expect(describeRrule('FREQ=DAILY')).toBe('Repeats daily');
    expect(describeRrule('FREQ=MONTHLY')).toBe('Repeats monthly');
    expect(describeRrule('FREQ=WEEKLY')).toBe('Repeats weekly');
  });

  it('says nothing for a block that does not repeat', () => {
    expect(describeRrule(null)).toBeNull();
  });

  it('admits a rule it cannot describe instead of dropping it', () => {
    expect(describeRrule('FREQ=WEEKLY;INTERVAL=2')).toBe('Repeats on a custom schedule');
  });
});

describe('weekdayCode', () => {
  it('reads the weekday in the block zone, not in UTC', () => {
    // Mon 3 Aug 2026 23:30 Berlin is already Tuesday in UTC.
    const at = Date.UTC(2026, 7, 3, 21, 30);
    expect(weekdayCode(at, 'Europe/Berlin')).toBe('MO');
    expect(weekdayCode(at, 'UTC')).toBe('MO');
    // Mon 3 Aug 2026 00:30 Berlin is still Sunday in New York.
    const earlyMonday = Date.UTC(2026, 7, 2, 22, 30);
    expect(weekdayCode(earlyMonday, 'Europe/Berlin')).toBe('MO');
    expect(weekdayCode(earlyMonday, 'America/New_York')).toBe('SU');
  });

  it('maps every weekday, with Sunday last as RRULE numbers them', () => {
    const monday = Date.UTC(2026, 7, 3, 12);
    const codes = [0, 1, 2, 3, 4, 5, 6].map((day) =>
      weekdayCode(monday + day * 86_400_000, 'UTC'),
    );
    expect(codes).toEqual(['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU']);
  });
});
