# Backlog

## v1 Cloud Functions — implemented

The core v1 backend is implemented and passing (`functions/` — 89 jest tests, build + lint clean).

| Story | Title | Implementation | Status |
|-------|-------|----------------|--------|
| STORY-020 | scheduleOverlaps Cloud Function | `functions/src/onBlockWrite.ts` (overlap engine + write to `overlaps/{coupleId}/windows/latest`) | done |
| STORY-023 | processInviteAcceptance Cloud Function | `functions/src/redeemInvite.ts` (callable: atomic pairing + pending-block migration) | done |
| STORY-024 | cleanupExpiredInvites Cloud Function | `functions/src/cleanupExpiredInvites.ts` (scheduled) | done |
| — | onOverlapWrite (FCM push on new overlaps) | `functions/src/onOverlapWrite.ts` | done |
| — | onInviteCreate (deep link generation) | `functions/src/onInviteCreate.ts` | done |
| — | onUserPrefsWrite (waking-hours preference) | `functions/src/onUserPrefsWrite.ts` | done |
| — | unpairCouple (atomic unpair + shared-data cleanup) | `functions/src/unpairCouple.ts` | done |

## Deferred (post-v1)

**Status:** Backlog
**Reason:** Not required for the v1 north-star (weekly active couples). UI + core overlap loop are validated; these are engagement/retention amplifiers.

| Story | Title | Status |
|-------|-------|--------|
| STORY-021 | dailyPartnerDigest Cloud Function | backlog |
| STORY-022 | sendInviteNotification Cloud Function | backlog |
| STORY-025 | weeklyAnalytics Cloud Function | backlog |
| STORY-026 | monthlyAnalytics Cloud Function | backlog |

**Note:** Implement after v1 launch once engagement metrics justify the compute cost.

---

Created: 2026-04-07
Updated: 2026-06-30
