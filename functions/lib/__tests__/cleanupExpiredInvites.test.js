"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const cleanupExpiredInvites_1 = require("../cleanupExpiredInvites");
const makeDeps = (expiredIds = ['old1', 'old2']) => ({
    getExpiredInvites: jest.fn().mockResolvedValue(expiredIds),
    deleteInvite: jest.fn().mockResolvedValue(undefined),
});
describe('handleCleanupExpiredInvites', () => {
    test('deletes all returned expired invite IDs', async () => {
        const deps = makeDeps(['id1', 'id2', 'id3']);
        await (0, cleanupExpiredInvites_1.handleCleanupExpiredInvites)(deps);
        expect(deps.deleteInvite).toHaveBeenCalledWith('id1');
        expect(deps.deleteInvite).toHaveBeenCalledWith('id2');
        expect(deps.deleteInvite).toHaveBeenCalledWith('id3');
        expect(deps.deleteInvite).toHaveBeenCalledTimes(3);
    });
    test('does nothing when no expired invites returned', async () => {
        const deps = makeDeps([]);
        await (0, cleanupExpiredInvites_1.handleCleanupExpiredInvites)(deps);
        expect(deps.deleteInvite).not.toHaveBeenCalled();
    });
    test('queries with a cutoff approximately 7 days ago', async () => {
        const deps = makeDeps([]);
        const before = Date.now();
        await (0, cleanupExpiredInvites_1.handleCleanupExpiredInvites)(deps);
        const after = Date.now();
        const cutoff = deps.getExpiredInvites.mock.calls[0][0];
        const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
        expect(cutoff).toBeGreaterThanOrEqual(before - sevenDaysMs);
        expect(cutoff).toBeLessThanOrEqual(after - sevenDaysMs + 100);
    });
    test('handles large batches without throwing', async () => {
        const ids = Array.from({ length: 600 }, (_, i) => `invite-${i}`);
        const deps = makeDeps(ids);
        await expect((0, cleanupExpiredInvites_1.handleCleanupExpiredInvites)(deps)).resolves.not.toThrow();
        expect(deps.deleteInvite).toHaveBeenCalledTimes(600);
    });
    test('calls getExpiredInvites exactly once', async () => {
        const deps = makeDeps([]);
        await (0, cleanupExpiredInvites_1.handleCleanupExpiredInvites)(deps);
        expect(deps.getExpiredInvites).toHaveBeenCalledTimes(1);
    });
});
//# sourceMappingURL=cleanupExpiredInvites.test.js.map