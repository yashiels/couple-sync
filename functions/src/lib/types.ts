export interface TimeBlock {
  id?: string;
  userId: string;
  title: string;
  type: 'busy' | 'free' | 'tentative';
  category?: string;
  startUtc: number; // UTC ms since epoch
  endUtc: number;   // UTC ms since epoch
  timezone: string; // IANA timezone
  recurrenceRule?: string; // RFC 5545 RRULE
  source: 'google' | 'manual';
  visibility: 'bothPartners' | 'onlyMe';
}

export interface OverlapWindow {
  startUtc: number;
  endUtc: number;
  durationMinutes: number;
  score: number;
  reasonableBoth: boolean;
}

export interface OverlapResult {
  windows: OverlapWindow[];
  computedAt: number;
  blockHashA: string;
  blockHashB: string;
}

export interface UserDoc {
  uid?: string;
  email: string;
  displayName: string;
  timezone: string; // IANA timezone
  coupleId?: string;
  fcmTokens: string[];
  createdAt: number;
  showLateNightWindows?: boolean; // if true, skip 07:00–23:00 waking-hours clip for this partner
}

export interface CoupleDoc {
  userAUid: string;
  userBUid: string;
  status: 'active' | 'inactive';
  pairedAt: number;
  createdAt: number;
}

export interface InviteDoc {
  code: string;
  createdByUid: string;
  coupleId?: string;
  expiresAt: number; // UTC ms
  // 'accepted' is a legacy value — no longer written by current code (acceptInvite
  // now only stamps coupleId). Kept here so existing Firestore docs deserialise correctly.
  status: 'pending' | 'redeemed' | 'accepted' | 'expired';
  deepLinkUrl?: string;
}
