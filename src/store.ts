import { create } from 'zustand';

import type {
  BlockWithOccurrences,
  CoupleRow,
  OverlapWindow,
  UserRow,
} from '../backend/src/wire';

/** What every path except GET /users/me returns: a user row with fcm_tokens stripped. */
type PublicUser = Omit<UserRow, 'fcm_tokens'>;

interface State {
  hydrated: boolean;
  /** Own row, so fcm_tokens is present. */
  user: UserRow | null;
  /**
   * The partner is a separate slot on purpose: a `user:update` WS message can be for either party, so
   * the handler dispatches on msg.user.uid. Writing it into `user` unconditionally would overwrite the
   * signed-in user with their partner's row.
   */
  partner: PublicUser | null;
  couple: CoupleRow | null;
  blocks: BlockWithOccurrences[];
  windows: OverlapWindow[];
  computedAt: number | null;
  /** Parked from a couplesync://invite/:code deep link, across the sign-in round trip. */
  pendingInviteCode: string | null;
  lastCalendarSyncMs: number | null;
  /** The Calendar tab's current week. Null until the tab is opened. */
  visibleRange: { from: number; to: number } | null;
  /** Set on a failed cold start; drives a retry screen. */
  hydrationError: string | null;
}

interface Actions {
  setHydrated(v: boolean): void;
  setHydrationError(e: string | null): void;
  setUser(u: UserRow | null): void;
  setPartner(p: PublicUser | null): void;
  setCouple(c: CoupleRow | null): void;
  setBlocks(b: BlockWithOccurrences[]): void;
  removeBlock(id: string): void;
  /** The week the Calendar tab is showing. The WS layer reads it to refetch the right range. */
  setVisibleRange(from: number, to: number): void;
  setWindows(w: OverlapWindow[], computedAt: number): void;
  setPendingInvite(code: string | null): void;
  setLastCalendarSync(ms: number): void;
  /** Unpair: keep the authenticated user and their timezone, drop everything couple-scoped. */
  resetCouple(): void;
  /** Sign-out: drop everything including the user. */
  reset(): void;
}

const initialState: State = {
  hydrated: false,
  user: null,
  partner: null,
  couple: null,
  blocks: [],
  windows: [],
  computedAt: null,
  pendingInviteCode: null,
  lastCalendarSyncMs: null,
  visibleRange: null,
  hydrationError: null,
};

/** Everything that stops being meaningful the moment the couple goes away. */
const coupleScoped = {
  partner: null,
  couple: null,
  blocks: [],
  windows: [],
  computedAt: null,
  pendingInviteCode: null,
  lastCalendarSyncMs: null,
  visibleRange: null,
} satisfies Partial<State>;

/**
 * Set by `app/_layout.tsx` to `calendar.clearSyncLimiter`. A seam rather than an import because the
 * limiter's authoritative copy lives in expo-secure-store, and importing that here would drag a
 * native module into every test that touches the store. Both resets fire it: the in-memory
 * `lastCalendarSyncMs` below is only a mirror, and clearing the mirror alone would leave the persisted
 * timestamp suppressing the re-sync that repopulates a re-paired couple's google blocks.
 */
let clearPersistedCalendarSync: (() => void) | null = null;

export function setPersistedCalendarSyncCleaner(fn: (() => void) | null): void {
  clearPersistedCalendarSync = fn;
}

// There is deliberately no upsertBlock. A block:set broadcast carries a BlockRow with no
// `occurrences` — the server cannot know this client's visible week — so merging it into `blocks`
// would put an un-renderable block on the grid. The WS handler reads visibleRange and refetches the
// range via setBlocks instead, or skips entirely when visibleRange is null.
export const useStore = create<State & Actions>((set) => ({
  ...initialState,

  setHydrated: (hydrated) => set({ hydrated }),
  setHydrationError: (hydrationError) => set({ hydrationError }),
  setUser: (user) => set({ user }),
  setPartner: (partner) => set({ partner }),
  setCouple: (couple) => set({ couple }),
  setBlocks: (blocks) => set({ blocks }),
  removeBlock: (id) => set((s) => ({ blocks: s.blocks.filter((b) => b.id !== id) })),
  setVisibleRange: (from, to) => set({ visibleRange: { from, to } }),
  setWindows: (windows, computedAt) => set({ windows, computedAt }),
  setPendingInvite: (pendingInviteCode) => set({ pendingInviteCode }),
  setLastCalendarSync: (lastCalendarSyncMs) => set({ lastCalendarSyncMs }),

  // couple_id is cleared on the local row too: the guard chain is what sends the user back to
  // /pairing, and it reads user.couple_id.
  resetCouple: () => {
    clearPersistedCalendarSync?.();
    set((s) => ({ ...coupleScoped, user: s.user ? { ...s.user, couple_id: null } : null }));
  },

  // hydrated stays true: sign-out is a known-empty state, not an unknown one, and dropping it would
  // leave the splash up forever (hydration runs once per launch).
  reset: () => {
    clearPersistedCalendarSync?.();
    set({ ...initialState, hydrated: true });
  },
}));
