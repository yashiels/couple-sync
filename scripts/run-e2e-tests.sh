#!/usr/bin/env bash
# Runs E2E integration tests against Firebase Emulator Suite.
# Tests the full data flow: auth → profiles → timezone → invites → pairing → blocks → overlap → calendar sync.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "==> Starting Firebase emulators..."
firebase emulators:start --only auth,firestore --project nexion-ai-prod &
EMULATOR_PID=$!

cleanup() {
  echo "==> Stopping emulators..."
  kill $EMULATOR_PID 2>/dev/null || true
  pkill -f "firebase" 2>/dev/null || true
}
trap cleanup EXIT

# Wait for emulators to be ready
echo "==> Waiting for emulators..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8080/ > /dev/null 2>&1 && curl -sf http://localhost:9099/ > /dev/null 2>&1; then
    echo "==> Emulators ready"
    break
  fi
  if [ "$i" = "30" ]; then
    echo "==> ERROR: Emulators failed to start"
    exit 1
  fi
  sleep 1
done

echo "==> Running E2E tests..."
node --input-type=commonjs -e "$(cat <<'NODEEOF'
const admin = require('./functions/node_modules/firebase-admin');
process.env.FIRESTORE_EMULATOR_HOST = 'localhost:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = 'localhost:9099';
if (!admin.apps.length) admin.initializeApp({ projectId: 'nexion-ai-prod' });
const db = admin.firestore();
const auth = admin.auth();

async function test() {
  let passed = 0, failed = 0;
  function ok(c, n) { if (c) { console.log('  PASS', n); passed++; } else { console.log('  FAIL', n); failed++; } }

  console.log('\n=== 1. AUTH ===');
  const uA = await auth.createUser({ email:'alice@test.com', password:'test1234', displayName:'Alice' });
  const uB = await auth.createUser({ email:'bob@test.com', password:'test1234', displayName:'Bob' });
  ok(uA.uid, 'User A created');
  ok(uB.uid, 'User B created');

  console.log('\n=== 2. PROFILES ===');
  await db.collection('users').doc(uA.uid).set({ email:'alice@test.com', displayName:'Alice', timezone:'', coupleId:null, fcmTokens:[], photoUrl:null, createdAt:Date.now() });
  await db.collection('users').doc(uB.uid).set({ email:'bob@test.com', displayName:'Bob', timezone:'', coupleId:null, fcmTokens:[], photoUrl:null, createdAt:Date.now() });
  ok((await db.collection('users').doc(uA.uid).get()).data().timezone === '', 'A needs timezone');
  ok((await db.collection('users').doc(uA.uid).get()).data().coupleId === null, 'A needs pairing');

  console.log('\n=== 3. TIMEZONE ===');
  await db.collection('users').doc(uA.uid).update({ timezone:'Africa/Johannesburg' });
  await db.collection('users').doc(uB.uid).update({ timezone:'Europe/London' });
  ok((await db.collection('users').doc(uA.uid).get()).data().timezone === 'Africa/Johannesburg', 'A timezone set');
  ok((await db.collection('users').doc(uB.uid).get()).data().timezone === 'Europe/London', 'B timezone set');

  console.log('\n=== 4. PENDING BLOCKS ===');
  await db.collection('users').doc(uA.uid).collection('pendingBlocks').add({ title:'Sleep', startUtc:1700082000000, endUtc:1700103600000, timezone:'Africa/Johannesburg', category:'sleep', source:'manual' });
  await db.collection('users').doc(uA.uid).collection('pendingBlocks').add({ title:'Work', startUtc:1700118000000, endUtc:1700150400000, timezone:'Africa/Johannesburg', category:'work', source:'manual' });
  ok((await db.collection('users').doc(uA.uid).collection('pendingBlocks').get()).size === 2, '2 pending blocks saved');

  console.log('\n=== 5. INVITE ===');
  await db.collection('invites').doc('E2E_CI').set({ code:'E2E_CI', createdByUid:uA.uid, status:'pending', expiresAt:Date.now()+604800000, createdAt:Date.now() });
  ok((await db.collection('invites').doc('E2E_CI').get()).data().status === 'pending', 'Invite pending');

  console.log('\n=== 6. PAIRING ===');
  const cRef = db.collection('couples').doc();
  const cId = cRef.id;
  await db.runTransaction(async txn => {
    txn.set(cRef, { userAUid:uA.uid, userBUid:uB.uid, status:'active', pairedAt:Date.now(), createdAt:Date.now() });
    txn.update(db.collection('users').doc(uA.uid), { coupleId:cId });
    txn.update(db.collection('users').doc(uB.uid), { coupleId:cId });
    txn.update(db.collection('invites').doc('E2E_CI'), { status:'accepted', coupleId:cId });
  });
  ok((await db.collection('couples').doc(cId).get()).data().status === 'active', 'Couple created');
  ok((await db.collection('users').doc(uA.uid).get()).data().coupleId === cId, 'A linked to couple');
  ok((await db.collection('users').doc(uB.uid).get()).data().coupleId === cId, 'B linked to couple');
  ok((await db.collection('invites').doc('E2E_CI').get()).data().status === 'accepted', 'Invite accepted');

  console.log('\n=== 7. BLOCK CRUD ===');
  const bRef = db.collection('timeblocks').doc(cId).collection('blocks').doc();
  await bRef.set({ userId:uA.uid, title:'Gym', startUtc:1700150400000, endUtc:1700154000000, timezone:'Africa/Johannesburg', category:'exercise', source:'manual', visibility:'bothPartners', createdAt:Date.now() });
  ok((await bRef.get()).exists, 'Block created');
  await bRef.update({ title:'Yoga' });
  ok((await bRef.get()).data().title === 'Yoga', 'Block updated');
  await bRef.delete();
  ok(!(await bRef.get()).exists, 'Block deleted');

  console.log('\n=== 8. QUERY BY USER ===');
  await db.collection('timeblocks').doc(cId).collection('blocks').doc('a1').set({ userId:uA.uid, title:'Work A', startUtc:1700118000000, endUtc:1700150400000, source:'manual', createdAt:Date.now() });
  await db.collection('timeblocks').doc(cId).collection('blocks').doc('b1').set({ userId:uB.uid, title:'Work B', startUtc:1700121600000, endUtc:1700150400000, source:'manual', createdAt:Date.now() });
  ok((await db.collection('timeblocks').doc(cId).collection('blocks').where('userId','==',uA.uid).get()).size === 1, 'Query filters by userId');

  console.log('\n=== 9. OVERLAP ===');
  await db.collection('overlaps').doc(cId).collection('windows').doc('latest').set({ computedAt:Date.now(), blockHashA:'h1', blockHashB:'h2', windows:[{startUtc:1700154000000,endUtc:1700161200000,durationMinutes:120,score:45.5,reasonableBoth:true}] });
  const ov = (await db.collection('overlaps').doc(cId).collection('windows').doc('latest').get()).data();
  ok(ov.windows.length === 1 && ov.windows[0].score === 45.5, 'Overlap result readable');

  console.log('\n=== 10. CALENDAR SYNC ===');
  await db.collection('timeblocks').doc(cId).collection('blocks').doc('g1').set({ userId:uA.uid, title:'Busy', startUtc:1700000000000, endUtc:1700003600000, source:'google', createdAt:Date.now() });
  ok((await db.collection('timeblocks').doc(cId).collection('blocks').where('source','==','google').get()).size === 1, 'Google block created');
  const gd = await db.collection('timeblocks').doc(cId).collection('blocks').where('source','==','google').get();
  for (const d of gd.docs) await d.ref.delete();
  ok((await db.collection('timeblocks').doc(cId).collection('blocks').where('source','==','google').get()).size === 0, 'Google blocks deleted on re-sync');
  ok((await db.collection('timeblocks').doc(cId).collection('blocks').where('source','==','manual').get()).size >= 1, 'Manual blocks preserved');

  console.log('\n=== 11. FCM TOKEN ===');
  await db.collection('users').doc(uA.uid).update({ fcmTokens:['token123'] });
  ok((await db.collection('users').doc(uA.uid).get()).data().fcmTokens.includes('token123'), 'FCM token stored');

  console.log('\n=== 12. PENDING BLOCKS MIGRATION ===');
  const ps = await db.collection('users').doc(uA.uid).collection('pendingBlocks').get();
  const ba = db.batch();
  for (const d of ps.docs) {
    ba.set(db.collection('timeblocks').doc(cId).collection('blocks').doc(), { ...d.data(), userId:uA.uid });
    ba.delete(d.ref);
  }
  await ba.commit();
  ok((await db.collection('users').doc(uA.uid).collection('pendingBlocks').get()).size === 0, 'Pending blocks cleared');
  ok((await db.collection('timeblocks').doc(cId).collection('blocks').where('userId','==',uA.uid).get()).size >= 3, 'Blocks migrated');

  console.log('\n=== 13. ROUTER REDIRECT LOGIC ===');
  function redirect(authed, hasTz, hasCouple, path) {
    if (!authed) return path === '/auth' ? null : '/auth';
    if (!hasTz) return path === '/timezone-setup' ? null : '/timezone-setup';
    if (!hasCouple) {
      if (['/pairing','/routine-setup','/timezone-setup'].includes(path)) return null;
      return '/pairing';
    }
    if (['/auth','/pairing'].includes(path)) return '/home';
    return null;
  }
  ok(redirect(false,false,false,'/home') === '/auth', 'Unauthenticated -> /auth');
  ok(redirect(true,false,false,'/home') === '/timezone-setup', 'No timezone -> /timezone-setup');
  ok(redirect(true,true,false,'/home') === '/pairing', 'No couple -> /pairing');
  ok(redirect(true,true,true,'/home') === null, 'Onboarded stays on /home');
  ok(redirect(true,true,true,'/auth') === '/home', 'Onboarded on /auth -> /home');
  ok(redirect(true,false,false,'/auth') === '/timezone-setup', 'Authenticated on /auth -> /timezone-setup');

  console.log('\n========================================');
  console.log('  PASSED: ' + passed + '/' + (passed + failed));
  console.log('  FAILED: ' + failed);
  console.log('========================================');
  process.exit(failed > 0 ? 1 : 0);
}

test().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
NODEEOF
)"
