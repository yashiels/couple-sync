import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { setLogLevel } from 'firebase/firestore';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const PROJECT_ID = 'couple-sync-rules-test';

let env: any;
beforeAll(async () => {
  setLogLevel('error');
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: readFileSync(resolve(__dirname, '../../../../firestore.rules'), 'utf8') },
  });
});
afterAll(async () => { await env.cleanup(); });

// couples/{coupleId} has NO client-write rule (functions-only via admin SDK),
// so seed it with security rules disabled. isCoupleMember() then reads it.
async function seedCouple(coupleId: string, a: string, b: string) {
  await env.withSecurityRulesDisabled(async (ctx: any) => {
    await ctx.firestore().doc(`couples/${coupleId}`).set({ userAUid: a, userBUid: b });
  });
  // The membership check also reads users/{uid}.coupleId, so stamp that too.
  await env.withSecurityRulesDisabled(async (ctx: any) => {
    await ctx.firestore().doc(`users/${a}`).set({ coupleId });
  });
}

test('member can write latest with computedBy=self', async () => {
  const cid = 'c1', a = 'uA', b = 'uB';
  await seedCouple(cid, a, b);
  await env.authenticatedContext(a).firestore().doc(`users/${a}`)
    .set({ coupleId: cid });
  const db = env.authenticatedContext(a).firestore();
  await assertSucceeds(db.doc(`overlaps/${cid}/windows/latest`).set({
    windows: [], computedAt: 1, inputHash: 'h', computedBy: a,
  }));
});

test('non-member cannot write latest', async () => {
  const cid = 'c2', a = 'uA', b = 'uB';
  await seedCouple(cid, a, b);
  const db = env.authenticatedContext('stranger').firestore();
  await assertFails(db.doc(`overlaps/${cid}/windows/latest`).set({
    windows: [], computedAt: 1, inputHash: 'h', computedBy: 'stranger',
  }));
});

test('computedBy must equal auth.uid', async () => {
  const cid = 'c3', a = 'uA', b = 'uB';
  await seedCouple(cid, a, b);
  await env.authenticatedContext(a).firestore().doc(`users/${a}`).set({ coupleId: cid });
  const db = env.authenticatedContext(a).firestore();
  await assertFails(db.doc(`overlaps/${cid}/windows/latest`).set({
    windows: [], computedAt: 1, inputHash: 'h', computedBy: b, // forging partner
  }));
});

test('windows.size() > 20 rejected', async () => {
  const cid = 'c4', a = 'uA', b = 'uB';
  await seedCouple(cid, a, b);
  await env.authenticatedContext(a).firestore().doc(`users/${a}`).set({ coupleId: cid });
  const db = env.authenticatedContext(a).firestore();
  const windows = Array.from({ length: 21 }, () => ({ startUtc: 0, endUtc: 1, durationMinutes: 1, score: 0, reasonableBoth: false }));
  await assertFails(db.doc(`overlaps/${cid}/windows/latest`).set({
    windows, computedAt: 1, inputHash: 'h', computedBy: a,
  }));
});

test('write to a non-latest windowId rejected', async () => {
  const cid = 'c5', a = 'uA', b = 'uB';
  await seedCouple(cid, a, b);
  await env.authenticatedContext(a).firestore().doc(`users/${a}`).set({ coupleId: cid });
  const db = env.authenticatedContext(a).firestore();
  await assertFails(db.doc(`overlaps/${cid}/windows/other`).set({
    windows: [], computedAt: 1, inputHash: 'h', computedBy: a,
  }));
});
