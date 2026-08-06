// The wire contract. Row shapes ARE the wire shapes: snake_case, exactly as pg returns them, with no
// DTO mapping layer. The app imports these type-only:
//   import type { UserRow } from '../backend/src/wire'
// so nothing in here may reach a runtime dependency. Engine types therefore come from
// ./overlap/types.js (zero imports) and never ./overlap/index.js (which pulls in rrule).
import type { Block, OverlapWindow } from './overlap/types.js';

// Imported *and* re-exported: a bare `export type { X } from` creates no local binding, and
// WsMessage below references OverlapWindow.
export type { Block, OverlapWindow };

export interface UserRow {
  uid: string;
  email: string;
  display_name: string | null;
  photo_url: string | null;
  /** null until confirmed in onboarding — the app's router guard depends on it. */
  timezone: string | null;
  couple_id: string | null;
  show_late_night_windows: boolean;
  notifications_enabled: boolean;
  /** Stripped before a partner ever sees the row. */
  fcm_tokens: string[];
  created_at: number;
}

export interface CoupleRow {
  id: string;
  user_a_uid: string;
  user_b_uid: string;
  status: 'active' | 'inactive';
  paired_at: number;
  created_at: number;
}

export interface BlockRow {
  id: string;
  couple_id: string;
  user_id: string;
  /** Nullable on the wire, not in the table: scrubBlockForViewer nulls it for a partner. */
  title: string | null;
  type: 'busy' | 'free' | 'tentative';
  category: string | null;
  start_utc: number;
  end_utc: number;
  timezone: string;
  recurrence_rule: string | null;
  source: 'google' | 'manual';
  visibility: 'bothPartners' | 'onlyMe';
  created_at: number;
}

/**
 * Identity when viewerUid owns the block. Otherwise, for visibility === 'onlyMe', a copy with title
 * and category nulled. Never drops the interval: the overlap engine needs it, the partner just must
 * not see what the block is. The previous build shipped this control as a no-op.
 */
export function scrubBlockForViewer(block: BlockRow, viewerUid: string): BlockRow {
  if (block.user_id === viewerUid || block.visibility !== 'onlyMe') return block;
  return { ...block, title: null, category: null };
}

/** Drops fcm_tokens. Every path except GET /users/me sends the result of this. */
export function stripTokens(user: UserRow): Omit<UserRow, 'fcm_tokens'> {
  const { fcm_tokens: _dropped, ...rest } = user;
  return rest;
}

/**
 * snake_case row -> the engine's camelCase Block: the single place the two vocabularies meet.
 * Block has exactly six fields (overlap/types.ts). id, couple_id, title, category, source and
 * visibility are irrelevant to computation, and forwarding a title into the engine would be a
 * privacy smell.
 */
export function toEngineBlock(row: BlockRow): Block {
  return {
    userId: row.user_id,
    type: row.type,
    startUtc: row.start_utc,
    endUtc: row.end_utc,
    timezone: row.timezone,
    recurrenceRule: row.recurrence_rule,
  };
}

/**
 * A block plus every instance intersecting a requested [from,to], already clamped to it. Returned
 * only by GET /blocks; never present on a block:set broadcast, because the server cannot know a
 * client's visible range.
 */
export interface BlockWithOccurrences extends BlockRow {
  occurrences: { start_utc: number; end_utc: number }[];
}

export type WsMessage =
  | { t: 'hello'; uid: string; couple_id: string | null }
  | { t: 'block:set'; block: BlockRow }
  | { t: 'block:del'; id: string }
  /**
   * One message for a whole-set replacement (PUT /blocks/google). Emitting block:set per interval
   * would cause one ranged GET per busy interval, and an empty replacement cannot be expressed as a
   * block:set at all. Receivers refetch their visible range once.
   */
  | { t: 'blocks:changed'; couple_id: string }
  | { t: 'overlap'; couple_id: string; windows: OverlapWindow[]; computed_at: number }
  | { t: 'unpair'; couple_id: string }
  | { t: 'pairing'; couple_id: string; partner_uid: string }
  | { t: 'user:update'; user: Omit<UserRow, 'fcm_tokens'> };
