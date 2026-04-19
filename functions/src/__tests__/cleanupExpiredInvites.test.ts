import { handleCleanupExpiredInvites } from '../cleanupExpiredInvites';

const makeDeps = (expiredIds: string[] = ['old1', 'old2']) => ({
  getExpiredInvites: jest.fn().mockResolvedValue(expiredIds),
  deleteInviteBatch: jest.fn().mockResolvedValue(undefined),
});

describe('handleCleanupExpiredInvites', () => {
  test('deletes all returned expired invite IDs', async () => {
    const deps = makeDeps(['id1', 'id2', 'id3']);
    await handleCleanupExpiredInvites(deps);

    expect(deps.deleteInviteBatch).toHaveBeenCalledWith(['id1', 'id2', 'id3']);
    expect(deps.deleteInviteBatch).toHaveBeenCalledTimes(1);
  });

  test('does nothing when no expired invites returned', async () => {
    const deps = makeDeps([]);
    await handleCleanupExpiredInvites(deps);

    expect(deps.deleteInviteBatch).not.toHaveBeenCalled();
  });

  test('queries with a cutoff approximately 7 days ago', async () => {
    const deps = makeDeps([]);
    const before = Date.now();
    await handleCleanupExpiredInvites(deps);
    const after = Date.now();

    const cutoff = (deps.getExpiredInvites.mock.calls[0] as [number])[0];
    const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;

    expect(cutoff).toBeGreaterThanOrEqual(before - sevenDaysMs);
    expect(cutoff).toBeLessThanOrEqual(after - sevenDaysMs + 100);
  });

  test('handles large batches by chunking into 500-id slices', async () => {
    const ids = Array.from({ length: 600 }, (_, i) => `invite-${i}`);
    const deps = makeDeps(ids);

    await expect(handleCleanupExpiredInvites(deps)).resolves.not.toThrow();
    expect(deps.deleteInviteBatch).toHaveBeenCalledTimes(2);
    expect(deps.deleteInviteBatch).toHaveBeenNthCalledWith(1, ids.slice(0, 500));
    expect(deps.deleteInviteBatch).toHaveBeenNthCalledWith(2, ids.slice(500));
  });

  test('calls getExpiredInvites exactly once', async () => {
    const deps = makeDeps([]);
    await handleCleanupExpiredInvites(deps);

    expect(deps.getExpiredInvites).toHaveBeenCalledTimes(1);
  });
});
