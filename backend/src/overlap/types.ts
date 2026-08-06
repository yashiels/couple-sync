export const ALGO_VERSION = 1;
export const HORIZON_DAYS = 14;
export const MIN_WINDOW_MINUTES = 30;
export const MAX_WINDOWS = 20;
export const WAKE_HOUR = 7;
export const SLEEP_HOUR = 23;

export interface Block {
  userId: string;
  type: 'busy' | 'free' | 'tentative';
  startUtc: number;
  endUtc: number;
  timezone: string; // IANA, anchors recurrence expansion
  recurrenceRule: string | null;
}

export interface Prefs {
  showLateNightWindows: boolean;
}

export interface OverlapWindow {
  startUtc: number;
  endUtc: number;
  durationMinutes: number;
  score: number;
  reasonableBoth: boolean;
}

export interface OverlapInput {
  blocksA: Block[];
  blocksB: Block[];
  timezoneA: string; // couple.user_a_uid's zone — scoring anchor
  timezoneB: string;
  prefsA: Prefs;
  prefsB: Prefs;
  now: number; // UTC epoch ms; the engine floors it to the hour itself
}
