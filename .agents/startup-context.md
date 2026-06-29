# Startup Context — Couple Sync

> Foundation context for AI agents. Keep it **factual, not aspirational** — other skills read this to produce tailored output. Mark unknowns `TBD` rather than guessing. Full product detail lives in [`PRD.md`](../PRD.md); technical detail in [`ARCHITECTURE.md`](../ARCHITECTURE.md).

## Product

- **Name:** Couple Sync
- **One-liner:** Mobile app for long-distance couples to find mutual free time across timezones.
- **Stage:** Pre-launch / in development
- **Platform:** Flutter (iOS + Android) + Firebase backend
- **Tech stack:** Flutter 3.x + Dart + Riverpod + go_router; Firebase Auth + Firestore + Cloud Functions v2 (TypeScript) + FCM

## What it does

Couples connect via a pairing code, sync their Google Calendars (freebusy only — no event titles), add manual time blocks, and the app computes overlap windows server-side with push notifications when new mutual free time appears.

## Current state

- Flutter app scaffolded with core screens (auth, onboarding, pairing, home, calendar, blocks, overlap, settings)
- Firebase backend with Firestore rules, Cloud Functions for overlap computation and notifications
- Google Calendar freebusy integration
- Manual time block management
- Not yet launched — development ongoing

## Key product decisions

- **Privacy-first:** Google Calendar freebusy API only — no event titles stored or displayed
- **Cost-conscious:** Firebase Blaze plan, stay within free quotas (50k Firestore reads/day, 2M function invocations/month)
- **Server-side overlap computation:** Cloud Functions compute overlaps on block write, not client-side
- **Timezone-aware:** Every user and block stores an IANA timezone ID; all computation uses UTC internally
- **Couple-scoped data:** All data lives under a couple ID; security rules enforce couple membership

## Repository

`github.com/yashiels/couple-sync` — single Flutter project with `functions/` subdirectory for backend. See `AGENTS.md` for conventions and `CLAUDE.md` for build commands.
