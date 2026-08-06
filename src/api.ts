import Constants from 'expo-constants';

import type {
  BlockRow,
  BlockWithOccurrences,
  CoupleRow,
  OverlapWindow,
  UserRow,
} from '../backend/src/wire';
import { getIdToken } from './auth';

/**
 * Request body for a manual block. The server sets id, user_id, source and created_at, and ignores
 * them in a body, so they are absent here rather than optional.
 */
export type NewBlock = Pick<
  BlockRow,
  'title' | 'type' | 'category' | 'start_utc' | 'end_utc' | 'timezone' | 'recurrence_rule' | 'visibility'
>;

/** `status` is 0 for a transport failure — there was no HTTP response to carry one. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(`${status} ${code}`);
    this.name = 'ApiError';
  }
}

/**
 * No default: a silent `http://localhost:3000` fallback would fail on a device with a timeout rather
 * than a message naming the missing variable. Read per request, not at module load, so a test (and a
 * screen) can be reached without the env being set.
 */
export function baseUrl(): string {
  const extra = Constants.expoConfig?.extra as { apiBaseUrl?: string } | undefined;
  if (!extra?.apiBaseUrl) throw new Error('API_BASE_URL is not set — copy .env.example to .env');
  return extra.apiBaseUrl.replace(/\/$/, '');
}

/**
 * The whole client. Every call carries the current Firebase ID token, and there is no retry: v1 is
 * online-only (§0.8), so a failure is the caller's to surface, not this layer's to hide behind a
 * spinner that never ends. The backend's error body is `{ error, detail? }` — `error` is the code.
 */
async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const token = await getIdToken();
  // Skipping the round trip: without a token the server answers 401 missing_token, and `no_session`
  // tells the caller the difference between "signed out" and "rejected".
  if (!token) throw new ApiError(401, 'no_session');

  let res: Response;
  try {
    res = await fetch(`${baseUrl()}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch (err) {
    // fetch rejects with a bare TypeError on a dead network. Callers should only ever have to catch
    // ApiError.
    throw new ApiError(0, err instanceof Error && err.message ? err.message : 'network_error');
  }

  if (!res.ok) {
    const parsed = (await res.json().catch(() => null)) as { error?: unknown } | null;
    const code = typeof parsed?.error === 'string' ? parsed.error : `http_${res.status}`;
    throw new ApiError(res.status, code);
  }
  // Every 2xx on this API carries a JSON body; the `{ ok: true }` ones are simply discarded.
  return (await res.json().catch(() => null)) as T;
}

export const api = {
  /** Upserts the user row from the verified token claims and returns it (own row: fcm_tokens kept). */
  verify: async (): Promise<UserRow> =>
    (await request<{ user: UserRow }>('POST', '/auth/verify')).user,

  me: async (): Promise<UserRow> => (await request<{ user: UserRow }>('GET', '/users/me')).user,

  /** Self or partner only; a partner's row arrives with fcm_tokens stripped. */
  getUser: async (uid: string): Promise<Omit<UserRow, 'fcm_tokens'>> =>
    (await request<{ user: Omit<UserRow, 'fcm_tokens'> }>('GET', `/users/${uid}`)).user,

  patchUser: async (
    uid: string,
    patch: Partial<
      Pick<UserRow, 'timezone' | 'show_late_night_windows' | 'notifications_enabled' | 'display_name'>
    >,
  ): Promise<UserRow> =>
    (await request<{ user: UserRow }>('PATCH', `/users/${uid}`, patch)).user,

  getCouple: async (id: string): Promise<CoupleRow> =>
    (await request<{ couple: CoupleRow }>('GET', `/couples/${id}`)).couple,

  unpair: async (id: string): Promise<void> => {
    await request<{ ok: true }>('POST', `/couples/${id}/unpair`);
  },

  createInvite: (): Promise<{ code: string; expires_at: number }> =>
    request('POST', '/invites'),

  redeemInvite: (code: string): Promise<{ couple_id: string }> =>
    request('POST', `/invites/${encodeURIComponent(code)}/redeem`),

  /** from/to are REQUIRED: the server expands recurrence into that range and the client cannot. */
  listBlocks: async (coupleId: string, from: number, to: number): Promise<BlockWithOccurrences[]> =>
    (
      await request<{ blocks: BlockWithOccurrences[] }>(
        'GET',
        `/blocks?coupleId=${encodeURIComponent(coupleId)}&from=${from}&to=${to}`,
      )
    ).blocks,

  // couple_id travels in the body on writes and as `coupleId` in the query on reads and deletes —
  // that is the server's spelling (§7), not a slip.
  createBlock: async (coupleId: string, block: NewBlock): Promise<BlockRow> =>
    (await request<{ block: BlockRow }>('POST', '/blocks', { ...block, couple_id: coupleId })).block,

  updateBlock: async (
    coupleId: string,
    id: string,
    patch: Partial<NewBlock>,
  ): Promise<BlockRow> =>
    (await request<{ block: BlockRow }>('PATCH', `/blocks/${id}`, { ...patch, couple_id: coupleId }))
      .block,

  deleteBlock: async (coupleId: string, id: string): Promise<void> => {
    await request<{ ok: true }>('DELETE', `/blocks/${id}?coupleId=${encodeURIComponent(coupleId)}`);
  },

  /** Whole-set replacement of this user's google blocks. Returns how many the server stored. */
  putGoogleBlocks: async (
    coupleId: string,
    intervals: { start_utc: number; end_utc: number }[],
  ): Promise<number> =>
    (await request<{ count: number }>('PUT', '/blocks/google', { couple_id: coupleId, intervals }))
      .count,

  /** The server recomputes first when the stored hash is stale, so this is never a rotten read. */
  latestOverlap: (coupleId: string): Promise<{ windows: OverlapWindow[]; computed_at: number }> =>
    request('GET', `/overlaps/latest?coupleId=${encodeURIComponent(coupleId)}`),

  registerFcmToken: async (token: string): Promise<void> => {
    await request<{ fcm_tokens: string[] }>('POST', '/auth/fcm-token', { token });
  },

  /** Called on sign-out, so a shared handset never keeps a previous user's token. */
  deleteFcmToken: async (token: string): Promise<void> => {
    await request<{ fcm_tokens: string[] }>('DELETE', '/auth/fcm-token', { token });
  },
};
