"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const redeemInvite_1 = require("../redeemInvite");
const FUTURE_EXPIRY = Date.now() + 24 * 60 * 60 * 1000; // 24 hours from now
const PAST_EXPIRY = Date.now() - 1000; // 1 second ago
const makeValidInvite = (overrides = {}) => (Object.assign({ code: 'ABC123', createdByUid: 'userA', expiresAt: FUTURE_EXPIRY, status: 'pending' }, overrides));
const makeDeps = (overrides = {}) => (Object.assign({ getInvite: jest.fn().mockResolvedValue(makeValidInvite()), createCouple: jest.fn().mockResolvedValue('couple-id-1'), acceptInvite: jest.fn().mockResolvedValue(undefined), linkUserToCouple: jest.fn().mockResolvedValue(undefined) }, overrides));
describe('handleRedeemInvite', () => {
    test('returns coupleId on successful redemption', async () => {
        const deps = makeDeps();
        const result = await (0, redeemInvite_1.handleRedeemInvite)('userB', 'ABC123', deps);
        expect(result).toEqual({ coupleId: 'couple-id-1' });
    });
    test('creates couple with both user UIDs', async () => {
        const deps = makeDeps();
        await (0, redeemInvite_1.handleRedeemInvite)('userB', 'ABC123', deps);
        expect(deps.createCouple).toHaveBeenCalledWith(expect.objectContaining({
            userAUid: 'userA',
            userBUid: 'userB',
            status: 'active',
        }));
    });
    test('links both users to the new couple', async () => {
        const deps = makeDeps();
        await (0, redeemInvite_1.handleRedeemInvite)('userB', 'ABC123', deps);
        expect(deps.linkUserToCouple).toHaveBeenCalledWith('userA', 'couple-id-1');
        expect(deps.linkUserToCouple).toHaveBeenCalledWith('userB', 'couple-id-1');
    });
    test('marks invite as accepted', async () => {
        const deps = makeDeps();
        await (0, redeemInvite_1.handleRedeemInvite)('userB', 'ABC123', deps);
        expect(deps.acceptInvite).toHaveBeenCalledWith('ABC123', 'couple-id-1');
    });
    test('throws NOT_FOUND when invite code does not exist', async () => {
        const deps = makeDeps({ getInvite: jest.fn().mockResolvedValue(null) });
        await expect((0, redeemInvite_1.handleRedeemInvite)('userB', 'ABC123', deps))
            .rejects.toThrow('NOT_FOUND');
    });
    test('throws FAILED_PRECONDITION when invite is already accepted', async () => {
        const deps = makeDeps({
            getInvite: jest.fn().mockResolvedValue(makeValidInvite({ status: 'accepted' })),
        });
        await expect((0, redeemInvite_1.handleRedeemInvite)('userB', 'ABC123', deps))
            .rejects.toThrow('FAILED_PRECONDITION');
    });
    test('throws FAILED_PRECONDITION when invite is marked expired', async () => {
        const deps = makeDeps({
            getInvite: jest.fn().mockResolvedValue(makeValidInvite({ status: 'expired' })),
        });
        await expect((0, redeemInvite_1.handleRedeemInvite)('userB', 'ABC123', deps))
            .rejects.toThrow('FAILED_PRECONDITION');
    });
    test('throws DEADLINE_EXCEEDED when invite expiry timestamp is in the past', async () => {
        const deps = makeDeps({
            getInvite: jest.fn().mockResolvedValue(makeValidInvite({ expiresAt: PAST_EXPIRY })),
        });
        await expect((0, redeemInvite_1.handleRedeemInvite)('userB', 'ABC123', deps))
            .rejects.toThrow('DEADLINE_EXCEEDED');
    });
    test('throws INVALID_ARGUMENT when user tries to redeem their own invite', async () => {
        const deps = makeDeps();
        // 'userA' is the creator — cannot redeem their own code
        await expect((0, redeemInvite_1.handleRedeemInvite)('userA', 'ABC123', deps))
            .rejects.toThrow('INVALID_ARGUMENT');
    });
    test('looks up the invite by the provided code', async () => {
        const deps = makeDeps();
        await (0, redeemInvite_1.handleRedeemInvite)('userB', 'ABC123', deps);
        expect(deps.getInvite).toHaveBeenCalledWith('ABC123');
    });
});
//# sourceMappingURL=redeemInvite.test.js.map