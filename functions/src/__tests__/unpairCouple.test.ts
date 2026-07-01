import { handleUnpairCouple, UnpairCoupleDeps } from '../unpairCouple';
import { CoupleDoc, UnpairHistoryEntry } from '../lib/types';

const NOW = 1_700_000_000_000;

const makeCouple = (overrides: Partial<CoupleDoc> = {}): CoupleDoc => ({
  userAUid: 'userA',
  userBUid: 'userB',
  status: 'active',
  pairedAt: NOW,
  createdAt: NOW,
  ...overrides,
});

const makeDeps = (overrides: Record<string, unknown> = {}): UnpairCoupleDeps => ({
  getCallerProfile: jest.fn().mockResolvedValue({ coupleId: 'couple-1' }),
  getCouple: jest.fn().mockResolvedValue(makeCouple()),
  deactivateCouple: jest.fn().mockResolvedValue(undefined),
  unlinkUser: jest.fn().mockResolvedValue(undefined),
  deleteSharedData: jest.fn().mockResolvedValue(undefined),
  ...overrides,
});

describe('handleUnpairCouple', () => {
  test('unlinks both users and deactivates the couple on success', async () => {
    const deps = makeDeps();
    const result = await handleUnpairCouple('userA', deps);

    expect(result).toEqual({ coupleId: 'couple-1', partnerUid: 'userB' });
    expect(deps.deactivateCouple).toHaveBeenCalledTimes(1);
    expect(deps.unlinkUser).toHaveBeenCalledWith('userA');
    expect(deps.unlinkUser).toHaveBeenCalledWith('userB');
    expect(deps.deleteSharedData).toHaveBeenCalledWith('couple-1');
  });

  test('resolves partnerUid when caller is userB', async () => {
    const deps = makeDeps();
    const result = await handleUnpairCouple('userB', deps);
    expect(result.partnerUid).toBe('userA');
  });

  test('appends a history entry with manual_unpair reason', async () => {
    const deps = makeDeps();
    await handleUnpairCouple('userA', deps);

    const [coupleId, entry] = (deps.deactivateCouple as jest.Mock).mock.calls[0];
    expect(coupleId).toBe('couple-1');
    expect((entry as UnpairHistoryEntry).reason).toBe('manual_unpair');
    expect((entry as UnpairHistoryEntry).at).toBeGreaterThan(0);
  });

  test('throws FAILED_PRECONDITION when caller has no coupleId', async () => {
    const deps = makeDeps({
      getCallerProfile: jest.fn().mockResolvedValue({ coupleId: undefined }),
    });

    await expect(handleUnpairCouple('userA', deps)).rejects.toThrow('FAILED_PRECONDITION');
    expect(deps.deactivateCouple).not.toHaveBeenCalled();
    expect(deps.unlinkUser).not.toHaveBeenCalled();
  });

  test('throws FAILED_PRECONDITION when caller user doc does not exist', async () => {
    const deps = makeDeps({
      getCallerProfile: jest.fn().mockResolvedValue(null),
    });

    await expect(handleUnpairCouple('userA', deps)).rejects.toThrow('FAILED_PRECONDITION');
  });

  test('throws NOT_FOUND when couple doc is missing', async () => {
    const deps = makeDeps({
      getCouple: jest.fn().mockResolvedValue(null),
    });

    await expect(handleUnpairCouple('userA', deps)).rejects.toThrow('NOT_FOUND');
    expect(deps.deactivateCouple).not.toHaveBeenCalled();
  });

  test('throws PERMISSION_DENIED when caller is not a couple member', async () => {
    const deps = makeDeps({
      getCouple: jest.fn().mockResolvedValue(
        makeCouple({ userAUid: 'someoneElse', userBUid: 'anotherUser' })
      ),
    });

    await expect(handleUnpairCouple('userA', deps)).rejects.toThrow('PERMISSION_DENIED');
    expect(deps.deactivateCouple).not.toHaveBeenCalled();
    expect(deps.unlinkUser).not.toHaveBeenCalled();
  });

  test('is idempotent for an already-inactive couple: clears caller only', async () => {
    const deps = makeDeps({
      getCouple: jest.fn().mockResolvedValue(makeCouple({ status: 'inactive' })),
    });

    const result = await handleUnpairCouple('userA', deps);

    expect(result.partnerUid).toBe('userB');
    // Must NOT re-deactivate or delete shared data — already done in a prior unpair.
    expect(deps.deactivateCouple).not.toHaveBeenCalled();
    expect(deps.deleteSharedData).not.toHaveBeenCalled();
    // But it should still clear the caller's stale coupleId so they can re-pair.
    expect(deps.unlinkUser).toHaveBeenCalledWith('userA');
    expect(deps.unlinkUser).not.toHaveBeenCalledWith('userB');
  });
});
