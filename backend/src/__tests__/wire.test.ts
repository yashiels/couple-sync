import { describe, expect, it } from 'vitest';
import {
  scrubBlockForViewer,
  stripTokens,
  toEngineBlock,
  type BlockRow,
  type UserRow,
} from '../wire.js';

const OWNER = 'uid-owner';
const PARTNER = 'uid-partner';

function block(over: Partial<BlockRow> = {}): BlockRow {
  return {
    id: 'b1',
    couple_id: 'c1',
    user_id: OWNER,
    title: 'Therapy',
    type: 'busy',
    category: 'health',
    start_utc: 1_712_345_678_000,
    end_utc: 1_712_349_278_000,
    timezone: 'Africa/Johannesburg',
    recurrence_rule: 'FREQ=WEEKLY;BYDAY=TU',
    source: 'manual',
    visibility: 'onlyMe',
    created_at: 1_712_000_000_000,
    ...over,
  };
}

function user(over: Partial<UserRow> = {}): UserRow {
  return {
    uid: OWNER,
    email: 'a@example.com',
    display_name: 'A',
    photo_url: null,
    timezone: 'Africa/Johannesburg',
    couple_id: 'c1',
    show_late_night_windows: false,
    notifications_enabled: true,
    fcm_tokens: ['tok-1', 'tok-2'],
    created_at: 1_712_000_000_000,
    ...over,
  };
}

describe('scrubBlockForViewer', () => {
  it('is identity for the block owner', () => {
    const b = block();
    expect(scrubBlockForViewer(b, OWNER)).toEqual(b);
  });

  it('nulls title and category on an onlyMe block for the partner', () => {
    const out = scrubBlockForViewer(block(), PARTNER);
    expect(out.title).toBeNull();
    expect(out.category).toBeNull();
  });

  it('preserves start_utc, end_utc, timezone, recurrence_rule and type on a scrubbed block', () => {
    // The load-bearing assertion: the engine still needs the interval, so scrubbing must remove only
    // what the block *is* — never when it is. Drop these and onlyMe blocks stop shaping the overlap.
    const b = block();
    const out = scrubBlockForViewer(b, PARTNER);
    expect(out.start_utc).toBe(b.start_utc);
    expect(out.end_utc).toBe(b.end_utc);
    expect(out.timezone).toBe(b.timezone);
    expect(out.recurrence_rule).toBe(b.recurrence_rule);
    expect(out.type).toBe(b.type);
    // and every remaining field except title/category is untouched
    expect(out).toEqual({ ...b, title: null, category: null });
  });

  it('leaves a bothPartners block untouched for the partner', () => {
    const b = block({ visibility: 'bothPartners' });
    expect(scrubBlockForViewer(b, PARTNER)).toEqual(b);
  });

  it('does not mutate the input block', () => {
    const b = block();
    scrubBlockForViewer(b, PARTNER);
    expect(b.title).toBe('Therapy');
    expect(b.category).toBe('health');
  });
});

describe('stripTokens', () => {
  it('removes fcm_tokens and leaves every other field intact', () => {
    const u = user();
    const out = stripTokens(u);
    expect('fcm_tokens' in out).toBe(false);
    const { fcm_tokens: _dropped, ...rest } = u;
    expect(out).toEqual(rest);
  });

  it('does not mutate the input user', () => {
    const u = user();
    stripTokens(u);
    expect(u.fcm_tokens).toEqual(['tok-1', 'tok-2']);
  });
});

describe('toEngineBlock', () => {
  it('maps all six engine fields and no others', () => {
    const b = block();
    const engine = toEngineBlock(b);
    expect(Object.keys(engine).sort()).toEqual([
      'endUtc',
      'recurrenceRule',
      'startUtc',
      'timezone',
      'type',
      'userId',
    ]);
    expect(engine.userId).toBe(b.user_id);
    expect(engine.type).toBe(b.type);
    expect(engine.startUtc).toBe(b.start_utc);
    expect(engine.endUtc).toBe(b.end_utc);
    expect(engine.timezone).toBe(b.timezone);
    expect(engine.recurrenceRule).toBe(b.recurrence_rule);
    // No title reaches the engine — forwarding one would be a privacy smell.
    expect(JSON.stringify(engine)).not.toContain('Therapy');
  });

  it('passes through a null recurrence_rule as null', () => {
    expect(toEngineBlock(block({ recurrence_rule: null })).recurrenceRule).toBeNull();
  });
});
