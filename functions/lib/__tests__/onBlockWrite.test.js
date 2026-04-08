"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const onBlockWrite_1 = require("../onBlockWrite");
const makeCouple = (overrides = {}) => (Object.assign({ userAUid: 'userA', userBUid: 'userB', status: 'active', pairedAt: 0, createdAt: 0 }, overrides));
const makeDeps = (overrides = {}) => (Object.assign({ getCouple: jest.fn().mockResolvedValue(makeCouple()), getUser: jest.fn().mockResolvedValue({ timezone: 'UTC' }), getBlocks: jest.fn().mockResolvedValue([]), getCurrentOverlap: jest.fn().mockResolvedValue(null), saveOverlap: jest.fn().mockResolvedValue(undefined) }, overrides));
describe('handleBlockWrite', () => {
    test('fetches couple document and saves overlap result', async () => {
        const deps = makeDeps();
        await (0, onBlockWrite_1.handleBlockWrite)('couple1', deps);
        expect(deps.getCouple).toHaveBeenCalledWith('couple1');
        expect(deps.saveOverlap).toHaveBeenCalledWith('couple1', expect.objectContaining({
            computedAt: expect.any(Number),
            windows: expect.any(Array),
            blockHashA: expect.any(String),
            blockHashB: expect.any(String),
        }));
    });
    test('does nothing when couple not found', async () => {
        const deps = makeDeps({ getCouple: jest.fn().mockResolvedValue(null) });
        await (0, onBlockWrite_1.handleBlockWrite)('couple1', deps);
        expect(deps.getCouple).toHaveBeenCalledWith('couple1');
        expect(deps.saveOverlap).not.toHaveBeenCalled();
    });
    test('fetches user timezones for both partners', async () => {
        const getUser = jest.fn()
            .mockResolvedValueOnce({ timezone: 'America/New_York' })
            .mockResolvedValueOnce({ timezone: 'America/Los_Angeles' });
        const deps = makeDeps({ getUser });
        await (0, onBlockWrite_1.handleBlockWrite)('couple1', deps);
        expect(getUser).toHaveBeenCalledWith('userA');
        expect(getUser).toHaveBeenCalledWith('userB');
    });
    test('uses UTC fallback when user doc missing timezone', async () => {
        const deps = makeDeps({ getUser: jest.fn().mockResolvedValue(null) });
        await expect((0, onBlockWrite_1.handleBlockWrite)('couple1', deps)).resolves.not.toThrow();
        expect(deps.saveOverlap).toHaveBeenCalled();
    });
    test('skips recomputation when block hashes are unchanged', async () => {
        const block = {
            userId: 'userA',
            title: 'Meeting',
            type: 'busy',
            startUtc: 1700000000000,
            endUtc: 1700003600000,
            timezone: 'UTC',
            source: 'manual',
            visibility: 'bothPartners',
        };
        // First call to compute initial hashes
        const depsFirst = makeDeps({
            getBlocks: jest.fn().mockResolvedValue([block]),
        });
        await (0, onBlockWrite_1.handleBlockWrite)('couple1', depsFirst);
        const savedResult = depsFirst.saveOverlap.mock.calls[0][1];
        // Second call with same blocks — hashes match existing overlap
        const depsSecond = makeDeps({
            getBlocks: jest.fn().mockResolvedValue([block]),
            getCurrentOverlap: jest.fn().mockResolvedValue({
                blockHashA: savedResult.blockHashA,
                blockHashB: savedResult.blockHashB,
            }),
        });
        await (0, onBlockWrite_1.handleBlockWrite)('couple1', depsSecond);
        expect(depsSecond.saveOverlap).not.toHaveBeenCalled();
    });
    test('recomputes when block hashes differ from stored overlap', async () => {
        const deps = makeDeps({
            getCurrentOverlap: jest.fn().mockResolvedValue({
                blockHashA: 'old-hash-a',
                blockHashB: 'old-hash-b',
            }),
        });
        await (0, onBlockWrite_1.handleBlockWrite)('couple1', deps);
        expect(deps.saveOverlap).toHaveBeenCalled();
    });
    test('filters blocks per user before computing overlap', async () => {
        const blocksUserA = [{
                userId: 'userA',
                title: 'A meeting',
                type: 'busy',
                startUtc: Date.now(),
                endUtc: Date.now() + 3600000,
                timezone: 'UTC',
                source: 'manual',
                visibility: 'bothPartners',
            }];
        const blocksUserB = [{
                userId: 'userB',
                title: 'B meeting',
                type: 'busy',
                startUtc: Date.now() + 7200000,
                endUtc: Date.now() + 10800000,
                timezone: 'UTC',
                source: 'manual',
                visibility: 'bothPartners',
            }];
        const deps = makeDeps({
            getBlocks: jest.fn().mockResolvedValue([...blocksUserA, ...blocksUserB]),
        });
        await (0, onBlockWrite_1.handleBlockWrite)('couple1', deps);
        expect(deps.saveOverlap).toHaveBeenCalled();
    });
});
//# sourceMappingURL=onBlockWrite.test.js.map