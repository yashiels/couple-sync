import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithCredential,
  signInWithEmailAndPassword,
  signOut as firebaseSignOut,
} from '@react-native-firebase/auth';
import { GoogleSignin } from '@react-native-google-signin/google-signin';
import Constants from 'expo-constants';

import type { CoupleRow } from '../backend/src/wire';
import { api } from './api';
import { unregisterFcmToken } from './notifications';
import { useStore } from './store';
import { disconnect } from './ws';

/**
 * `freeBusy.query` is the only Calendar call we ever make (§5), so we request the narrowest scope that
 * authorizes it. This is deliberately NOT `calendar.readonly`: that scope grants full event-title read,
 * which the consent screen would then advertise — contradicting the app's promise that titles are never
 * requested. Never widened.
 */
export const CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar.freebusy';

/**
 * The over-broad scope earlier builds requested. Kept only so `ensureNarrowedScope()` can detect a user
 * still holding it and migrate them to `CALENDAR_SCOPE`. Do not request it.
 */
const LEGACY_CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar.readonly';

/**
 * Call once at app module load, before any sign-in — `app/_layout.tsx` does. The calendar scope is
 * requested here, in the sign-in consent itself, because Google sign-in *is* how the calendar gets
 * connected; there is no later escalation step and no connect screen. Throws on a missing web client
 * id so the failure is a startup error rather than a sign-in that never resolves.
 */
/** True only in an E2E build (EXPO_PUBLIC_E2E=1). Everything Google is bypassed when set. */
export function isE2E(): boolean {
  return (Constants.expoConfig?.extra as { e2e?: boolean } | undefined)?.e2e === true;
}

export function configureGoogleSignIn(): void {
  if (isE2E()) {
    // No Google in E2E: point Firebase Auth at the emulator. 10.0.2.2 is the Android emulator's
    // alias for the host machine, where the Firebase Auth emulator listens.
    connectAuthEmulator(getAuth(), 'http://10.0.2.2:9099');
    return;
  }
  const extra = Constants.expoConfig?.extra as { googleWebClientId?: string } | undefined;
  if (!extra?.googleWebClientId) {
    throw new Error('GOOGLE_WEB_CLIENT_ID is not set — copy .env.example to .env (the WEB client id)');
  }
  GoogleSignin.configure({ webClientId: extra.googleWebClientId, scopes: [CALENDAR_SCOPE] });
}

/**
 * E2E sign-in: create-or-sign-in a seeded test user against the Auth emulator, then fall through to
 * the exact same downstream path (auth listener -> /auth/verify) a real Google sign-in uses. No
 * calendar scope is granted, so sync() returns 'scope-missing' and E2E exercises manual blocks only.
 */
export async function signInForE2E(email: string, password = 'e2e-password'): Promise<void> {
  const auth = getAuth();
  try {
    await signInWithEmailAndPassword(auth, email, password);
  } catch {
    await createUserWithEmailAndPassword(auth, email, password);
  }
}

/** Resolves without signing in when the user cancels — cancellation is not an error. */
export async function signInWithGoogle(): Promise<void> {
  await GoogleSignin.hasPlayServices({ showPlayServicesUpdateDialog: true });
  const result = await GoogleSignin.signIn();
  if (result.type !== 'success') return;
  const { idToken } = result.data;
  if (!idToken) throw new Error('google sign-in returned no id token');
  await signInWithCredential(getAuth(), GoogleAuthProvider.credential(idToken));
}

/**
 * Existing-grant migration gate — run once at cold start, before any calendar sync. Narrowing the
 * requested scope in `configureGoogleSignIn()` only affects FUTURE consent; a user who already granted
 * the legacy `calendar.readonly` keeps that broad grant indefinitely. So refresh the cached Google user
 * and inspect the granted scopes (`signInSilently()` returns them; `getTokens()` does not). If the
 * narrowed `calendar.freebusy` is present and the legacy scope is gone, we are done. Otherwise revoke
 * and sign out so the next sign-in re-consents to the narrowed scope only.
 *
 * Fails closed: on `'needs-reconsent'` the caller must NOT sync — the user is already signed out and the
 * guard chain routes to /auth. `'no-session'` means there is no Google grant to migrate (the normal
 * `sync()` → `'scope-missing'` path handles that), so the caller proceeds.
 *
 * Ceiling: once the beta cohort has all re-consented this gate is dead weight; it can be deleted after
 * the migration window closes. It stays cheap in the meantime — the `'ok'` fast-path is one silent call.
 */
export async function ensureNarrowedScope(): Promise<'ok' | 'needs-reconsent' | 'no-session'> {
  if (isE2E()) return 'ok';
  let scopes: string[];
  try {
    const res = await GoogleSignin.signInSilently();
    if (res.type !== 'success') return 'no-session';
    scopes = res.data.scopes ?? [];
  } catch {
    return 'no-session';
  }
  if (scopes.includes(CALENDAR_SCOPE) && !scopes.includes(LEGACY_CALENDAR_SCOPE)) return 'ok';
  // Still on the broad grant (or the narrowed scope was never granted): revoke so the re-consent asks
  // for freebusy only, then sign out. revokeAccess is best-effort — even if it fails, signing out
  // forces the fresh sign-in that requests the narrowed scope.
  try {
    await GoogleSignin.revokeAccess();
  } catch {
    // best effort
  }
  await signOut();
  return 'needs-reconsent';
}

/**
 * The FCM token is deleted FIRST, while the Firebase ID token that authorizes DELETE /auth/fcm-token
 * still exists — otherwise this handset stays attached to the previous user's row and keeps receiving
 * their pushes. It is best-effort inside `unregisterFcmToken`, so an offline sign-out still signs out.
 */
export async function signOut(): Promise<void> {
  await unregisterFcmToken();
  disconnect();
  await GoogleSignin.signOut();
  await firebaseSignOut(getAuth());
  useStore.getState().reset();
}

/**
 * Firebase ID token — for OUR backend only. The Google Calendar API rejects it; that needs
 * getGoogleAccessToken(). Confusing the two is the single easiest mistake in this module.
 */
export async function getIdToken(): Promise<string | null> {
  const user = getAuth().currentUser;
  return user ? await user.getIdToken() : null;
}

/**
 * Google OAuth access token — for the Calendar API only, never sent to our backend. getTokens()
 * *rejects* when there is no cached Google account (it does not return null), and can reject during
 * token recovery; both are expected states, so they map to null and Task 13 turns that into
 * 'no-session' rather than a crash.
 */
export async function getGoogleAccessToken(): Promise<string | null> {
  try {
    const { accessToken } = await GoogleSignin.getTokens();
    return accessToken;
  } catch {
    return null;
  }
}

export function onAuthChange(cb: (uid: string | null) => void): () => void {
  return onAuthStateChanged(getAuth(), (user) => cb(user?.uid ?? null));
}

/** Whichever side of the couple is not you. */
export function partnerUidOf(couple: CoupleRow, uid: string): string {
  return couple.user_a_uid === uid ? couple.user_b_uid : couple.user_a_uid;
}

/**
 * `app/_layout.tsx` registers `calendar.sync(coupleId, { force: true })` here. A seam rather than a
 * direct import so this module does not depend on the Google session plumbing, and so the transition
 * rule below is testable without it. Because every pairing path — the redeemer's HTTP result, the
 * inviter's WS `pairing`, and a `hello` reconciling a missed one — funnels through hydrateFromServer,
 * this one registration covers all three and fires exactly once per real transition.
 */
let firstPairHandler: ((coupleId: string) => void) | null = null;

export function setFirstPairHandler(handler: ((coupleId: string) => void) | null): void {
  firstPairHandler = handler;
}

let inFlight: Promise<string | null> | null = null;
/**
 * False until the first hydration has answered. A cold start for an already-paired couple looks
 * exactly like a fresh pairing — local state is null either way — so the transition is judged
 * against this sentinel and never against `couple === null`.
 */
let authoritativeStateInitialized = false;

/**
 * Idempotent AND single-flight. Called from cold start, every WS `hello`, a WS `pairing`, and a
 * successful invite redeem — including concurrently, which is the point: a `pairing` and a `hello`
 * can land together, both see a local couple_id of null, and both would otherwise fire the
 * first-pair sync. Sharing one in-flight promise makes that exactly one.
 *
 * Blocks are deliberately not fetched: they need a from/to range and only the Calendar tab has one.
 */
export function hydrateFromServer(): Promise<string | null> {
  inFlight ??= doHydrate().finally(() => {
    inFlight = null;
  });
  return inFlight;
}

async function doHydrate(): Promise<string | null> {
  const store = useStore.getState();
  // Read before setUser, or the "previous" value is the one we just wrote.
  const previousCoupleId = store.user?.couple_id ?? null;
  const wasInitialized = authoritativeStateInitialized;

  // api.me() first: the local couple_id can be stale (paired, or unpaired, elsewhere).
  const me = await api.me();
  store.setUser(me);
  // Set on BOTH branches. If only the paired branch set it, an unpaired cold start would leave the
  // sentinel false and the pairing that follows would be read as the initializing hydration — the
  // inviter's first sync would never fire.
  authoritativeStateInitialized = true;

  if (!me.couple_id) {
    store.resetCouple();
    return null;
  }

  const couple = await api.getCouple(me.couple_id);
  const [partner, overlap] = await Promise.all([
    api.getUser(partnerUidOf(couple, me.uid)),
    api.latestOverlap(me.couple_id),
  ]);
  store.setCouple(couple);
  store.setPartner(partner);
  store.setWindows(overlap.windows, overlap.computed_at);

  // Exactly-once first-pair sync: a real null -> set transition, and never the initializing
  // hydration, so an already-paired cold start and a plain reconnect both stay quiet.
  if (wasInitialized && previousCoupleId === null) firstPairHandler?.(me.couple_id);

  return me.couple_id;
}
