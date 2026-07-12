# Startup Context — Couple Sync

> Foundation context for AI agents. Keep it **factual, not aspirational** — other skills read this to produce tailored output. Mark unknowns `TBD` rather than guessing. Full product detail lives in [`PRD.md`](../PRD.md); technical detail in [`ARCHITECTURE.md`](../ARCHITECTURE.md).

## Product

- **Name:** Couple Sync
- **One-liner:** Mobile app for long-distance couples to find mutual free time across timezones.
- **Stage:** Pre-launch / in development
- **Platform:** Flutter (iOS + Android) + self-hosted Fastify backend
- **Tech stack:** Flutter 3.x + Dart + Riverpod + go_router; Fastify 4 + Postgres 16 + WebSocket (Node 22, TypeScript, pnpm); Firebase Auth + FCM + hosting only (Spark plan)

## What it does

Couples connect via a pairing code, sync their Google Calendars (freebusy only — no event titles), add manual time blocks, and **the device computes overlap windows** and publishes them over WebSocket. The server validates, dedups (`inputHash`), stores (`overlaps_latest`), and fans out to the partner (WS forward, or FCM push if offline).

## Current state

- Flutter app scaffolded with core screens (auth, onboarding, pairing, home, calendar, blocks, overlap, settings)
- Self-hosted Fastify + Postgres + WebSocket backend in `backend/` (no `functions/` directory, no Firestore, no Cloud Functions, no `firestore.rules`, no `firestore.indexes.json`)
- Google Calendar freebusy integration
- Manual time block management with WS broadcast
- Device-computed overlap over WS (server stores + fans out, never computes)
- Not yet launched — development ongoing

## Key product decisions

- **Privacy-first:** Google Calendar freebusy API only — no event titles stored or displayed
- **Cost-conscious:** Firebase Spark plan (Auth + FCM + hosting free); Postgres on a managed Docker platform (Coolify)
- **Device-computed overlap:** the client computes overlap and publishes over WS — the server never computes overlap
- **Server-side security:** Firebase ID-token verification (`backend/src/auth.ts`) + `assertMember()` (`backend/src/couples.ts`) on every REST + WS path; WS `overlap` messages additionally require `computedBy === socketUid`. There are no Firestore rules.
- **Timezone-aware:** every user and block stores an IANA timezone ID; all storage is UTC milliseconds (`BIGINT` in Postgres, `int` in Dart)
- **Couple-scoped data:** all data lives under a couple ID; membership is enforced server-side

## Repository

`github.com/yashiels/couple-sync` — Flutter app in `lib/` with a self-hosted Fastify + Postgres backend in `backend/`. See `AGENTS.md` for conventions, `CLAUDE.md` for build commands, and `backend/README.md` for the authoritative backend description.
