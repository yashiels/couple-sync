# Backlog

## v1 backend — implemented

The core v1 backend lives in `backend/` (self-hosted Fastify + Postgres + WebSocket). It is implemented and passing (`cd backend && pnpm test` — vitest).

| Area | Implementation | Status |
|------|----------------|--------|
| Fastify bootstrap + WS + cron | `backend/src/index.ts` | done |
| Firebase ID-token verify | `backend/src/auth.ts` | done |
| Couple-membership guard | `backend/src/couples.ts` (`assertMember`) | done |
| Overlap WS handler (validate/dedup/store/fan-out/push) | `backend/src/overlap.ts` | done |
| Block CRUD + batch + WS broadcast | `backend/src/routes/blocks.ts` | done |
| WS sync + `computedBy === socketUid` | `backend/src/routes/sync.ts` | done |
| Invite create + atomic redeem | `backend/src/routes/invites.ts` | done |
| Couple GET + unpair | `backend/src/routes/couples.ts` | done |
| Reconnect fetch of latest overlap | `backend/src/routes/overlaps.ts` | done |
| Daily 03:00 UTC invite cleanup + admin trigger | `backend/src/cron.ts` | done |
| Postgres schema + migrations | `backend/src/migrations/001_init.sql` | done |

**Note:** the server does NOT compute overlap — the device does. The server only validates shape, dedups via `inputHash`, stores `overlaps_latest`, and fans out (WS forward or FCM push).

## v1 Flutter app — implemented

Core screens scaffolded (auth, onboarding, pairing, home, calendar, blocks, overlap, settings). `SyncService` (`lib/services/sync_service.dart`) is the REST + WS client, block cache (Hive), and the overlap compute + publish path.

## Deferred (post-v1)

**Status:** Backlog
**Reason:** Not required for the v1 north-star (weekly active couples). Core loop is validated; these are engagement/retention amplifiers or hygiene.

| Item | Title | Status |
|------|-------|--------|
| STORY-021 | dailyPartnerDigest | backlog |
| STORY-022 | sendInviteNotification | backlog |
| STORY-025 | weeklyAnalytics | backlog |
| STORY-026 | monthlyAnalytics | backlog |
| — | Split `SyncService` into smaller providers (block cache, WS client, overlap compute) | backlog |
| — | Hive → another store migration if Hive box growth bites | backlog |
| — | Localization sweep (i18n, non-en locales) | backlog |
| — | Accessibility sweep (semantics labels, contrast, dynamic type) | backlog |

**Note:** Implement after v1 launch once engagement metrics justify the compute cost.

---

Created: 2026-04-07
Updated: 2026-07-12
