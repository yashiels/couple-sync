// snake_case rows in, camelCase JSON out. All timestamps stay UTC epoch millis; the backend does
// zero timezone math, it only carries IANA ids around.

export type UserRow = {
  uid: string;
  email: string;
  display_name: string | null;
  photo_url: string | null;
  timezone: string;
  couple_id: string | null;
  fcm_tokens: string[];
  show_late_night_windows: boolean;
  notifications_enabled: boolean;
  created_at: number;
};

export type CoupleRow = {
  id: string;
  user_a_uid: string;
  user_b_uid: string;
  status: string;
  paired_at: number | null;
  created_at: number;
};

export type BlockRow = {
  id: string;
  couple_id: string;
  user_id: string;
  title: string;
  type: string;
  category: string | null;
  start_utc: number;
  end_utc: number;
  timezone: string;
  recurrence_rule: string | null;
  source: string;
  visibility: string;
  created_at: number;
};

export function toUser(r: UserRow, includeTokens: boolean) {
  return {
    uid: r.uid,
    email: r.email,
    displayName: r.display_name,
    photoUrl: r.photo_url,
    timezone: r.timezone,
    coupleId: r.couple_id,
    showLateNightWindows: r.show_late_night_windows,
    notificationsEnabled: r.notifications_enabled,
    createdAt: r.created_at,
    ...(includeTokens ? { fcmTokens: r.fcm_tokens ?? [] } : {}),
  };
}

export function toCouple(r: CoupleRow) {
  return {
    id: r.id,
    userAUid: r.user_a_uid,
    userBUid: r.user_b_uid,
    status: r.status,
    pairedAt: r.paired_at,
    createdAt: r.created_at,
  };
}

// `onlyMe` is enforced here, server-side. The partner still needs the interval (their device
// computes the overlap) but never learns what the block is.
export function toBlock(r: BlockRow, viewerUid: string) {
  const hide = r.visibility === 'onlyMe' && r.user_id !== viewerUid;
  return {
    id: r.id,
    coupleId: r.couple_id,
    userId: r.user_id,
    title: hide ? null : r.title,
    type: r.type,
    category: hide ? null : r.category,
    startUtc: r.start_utc,
    endUtc: r.end_utc,
    timezone: r.timezone,
    recurrenceRule: r.recurrence_rule,
    source: r.source,
    visibility: r.visibility,
    createdAt: r.created_at,
  };
}
