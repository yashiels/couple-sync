import { beforeEach, describe, expect, it, vi } from 'vitest';
import { HttpError } from '../http.js';
import type { CoupleRow } from '../wire.js';

vi.mock('../db.js', () => ({ query: vi.fn() }));

const { query } = await import('../db.js');
const { assertMember, partnerUid } = await import('../couples.js');
const mockQuery = vi.mocked(query);

const COUPLE: CoupleRow = {
  id: 'c1',
  user_a_uid: 'uid-a',
  user_b_uid: 'uid-b',
  status: 'active',
  paired_at: 1_712_000_000_000,
  created_at: 1_712_000_000_000,
};

function rows(...out: CoupleRow[]): void {
  mockQuery.mockResolvedValue(out);
}

async function expectForbidden(p: Promise<unknown>): Promise<void> {
  // 403 for both a non-member and a missing id, so the API never leaks whether an id exists.
  await expect(p).rejects.toMatchObject({ status: 403, code: 'forbidden' });
  await expect(p).rejects.toBeInstanceOf(HttpError);
}

describe('assertMember', () => {
  beforeEach(() => {
    mockQuery.mockReset();
  });

  it('returns the couple row for user_a_uid', async () => {
    rows(COUPLE);
    await expect(assertMember('c1', 'uid-a')).resolves.toEqual(COUPLE);
  });

  it('returns the couple row for user_b_uid', async () => {
    rows(COUPLE);
    await expect(assertMember('c1', 'uid-b')).resolves.toEqual(COUPLE);
  });

  it('throws 403 for a uid that is not a member', async () => {
    rows(COUPLE);
    await expectForbidden(assertMember('c1', 'uid-stranger'));
  });

  it('throws 403 — not 404 — for a coupleId that does not exist', async () => {
    rows();
    await expectForbidden(assertMember('nope', 'uid-a'));
  });

  it('throws 403 when the couple status is inactive', async () => {
    rows({ ...COUPLE, status: 'inactive' });
    await expectForbidden(assertMember('c1', 'uid-a'));
  });
});

describe('partnerUid', () => {
  it('returns b for a, and a for b', () => {
    expect(partnerUid(COUPLE, 'uid-a')).toBe('uid-b');
    expect(partnerUid(COUPLE, 'uid-b')).toBe('uid-a');
  });
});
