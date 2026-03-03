# Couple Schedule - Product Requirements Document

## Overview

**Couple Schedule** is a mobile app (iOS + Android) that helps long-distance couples find mutual free time by intelligently combining their calendars, custom time blocks, and timezone data to surface available windows for quality time together.

## Vision

"When are you free?" should never be a hard question. Couple Schedule answers it automatically.

## Tech Stack

- **Frontend:** Flutter (single codebase, iOS + Android)
- **Backend:** Firebase (Auth, Firestore, Cloud Functions, FCM)
- **Calendar APIs:** Google Calendar API, Apple EventKit (on-device), Microsoft Graph API (Outlook)
- **State Management:** Riverpod
- **Timezone:** `timezone` package (IANA tz database)
- **CI/CD:** GitHub Actions + Fastlane
- **Analytics:** Firebase Analytics + Crashlytics

### Why Flutter
- Single codebase for both platforms
- Strong calendar plugin ecosystem
- Team familiarity (existing Nexion Tech projects)
- Rapid iteration for MVP

### Why Firebase
- Real-time sync (Firestore) -- critical for couples seeing each other's updates instantly
- Built-in auth (Google, Apple, email)
- Cloud Functions for background overlap computation
- FCM for push notifications
- Scales from 0 to millions without ops overhead

## Architecture

```
+------------------+     +------------------+
|  Partner A App   |     |  Partner B App   |
|  (Flutter)       |     |  (Flutter)       |
+--------+---------+     +--------+---------+
         |                         |
         |    Firebase Firestore   |
         +----------+--------------+
                    |
         +----------+--------------+
         |   Cloud Functions       |
         |   - Overlap calculator  |
         |   - Calendar sync       |
         |   - Push notifications  |
         +----------+--------------+
                    |
    +---------------+---------------+
    |               |               |
 Google Cal    Apple Cal      Outlook Cal
   API         EventKit       Graph API
```

### Data Model

```
users/{uid}
  - email, displayName, timezone (IANA), partnerId
  - calendarSources: [{provider, connected, lastSync}]

couples/{coupleId}
  - partnerA: uid
  - partnerB: uid
  - createdAt
  - settings: {minSlotMinutes, preferredActivities[], quietHoursA, quietHoursB}

timeblocks/{coupleId}/blocks/{blockId}
  - userId
  - type: "calendar_event" | "custom_block" | "recurring"
  - title (optional, privacy-controlled)
  - startUtc, endUtc
  - timezone
  - recurrence (RRULE string, optional)
  - source: "google" | "apple" | "outlook" | "manual"
  - visibility: "busy" | "free" | "tentative"

overlaps/{coupleId}/windows/{windowId}
  - startUtc, endUtc
  - durationMinutes
  - suggestedActivity (optional)
  - notified: boolean
```

### Calendar Sync Strategy

1. **Google Calendar:** OAuth 2.0 + Calendar API v3. Webhook push notifications for real-time updates. Fetch freebusy endpoint for availability without exposing event details.
2. **Apple Calendar:** EventKit framework (on-device only). Background refresh via iOS background modes. No server-side access -- device must sync.
3. **Microsoft Outlook:** OAuth 2.0 + Microsoft Graph API. Similar webhook pattern to Google.
4. **Manual blocks:** User adds custom blocks (commute 07:00-08:00, gym 18:00-19:00) with optional recurrence.

### Overlap Algorithm

```
1. Normalize all blocks to UTC
2. For each partner, build a "busy" timeline (sorted intervals)
3. Merge overlapping busy intervals per partner
4. Invert to get "free" intervals per partner
5. Intersect both partners' free intervals
6. Filter by:
   - Minimum duration (configurable, default 30 min)
   - Quiet hours (sleep, do-not-disturb)
   - Both partners' local time (no 3am suggestions)
7. Rank by:
   - Duration (longer = better)
   - Time of day preference
   - Recurrence (regular slots > one-offs)
8. Return top N windows with suggested activities
```

## Features

### MVP (v1.0)

1. **Onboarding & Pairing**
   - Sign up (email, Google, Apple)
   - Generate/share invite code to link with partner
   - Set timezone (auto-detect + manual override)

2. **Calendar Integration**
   - Connect Google Calendar (OAuth)
   - Connect Apple Calendar (EventKit)
   - Connect Outlook Calendar (OAuth)
   - View synced events as busy blocks (no detail leakage by default)

3. **Custom Time Blocks**
   - Add one-off blocks (e.g., "Dentist appointment Tue 14:00-15:00")
   - Add recurring blocks (e.g., "Commute Mon-Fri 07:00-08:00")
   - Categories: commute, exercise, meals, sleep, personal, other

4. **Availability Overlap**
   - Real-time computation of mutual free windows
   - Display in both partners' local times side by side
   - Minimum slot duration filter (15/30/60 min)

5. **Timezone Display**
   - Always show both timezones
   - "It's 9pm for you, 3pm for them" contextual display
   - World clock widget on home screen

6. **Notifications**
   - "New free window found: Tomorrow 8pm-10pm your time"
   - Daily digest: "You have 3 free windows together this week"
   - Configurable quiet hours

7. **Settings**
   - Privacy controls (show event titles vs busy-only)
   - Quiet hours per partner
   - Notification preferences
   - Disconnect/reconnect calendars

### v2.0 (Post-Launch)

- **AI Suggestions:** "You both had dinner together last Tuesday -- want to make it weekly?"
- **Activity Templates:** Video call, watch party, online game, cook together
- **Shared Notes:** Pin notes to time windows ("Let's watch that movie")
- **Calendar Event Creation:** One-tap to create a Google/Apple event from a free window
- **Widgets:** iOS/Android home screen widget showing next mutual free window
- **Relationship Stats:** "You spent 12 hours together this month" (up from 8 last month)

### v3.0 (Future)

- **Group Mode:** Friend groups / family across timezones
- **Smart Rescheduling:** "Your gym moved to 6pm -- new free window at 7pm!"
- **Wearable Integration:** Apple Watch / Wear OS complications
- **Web Dashboard:** Browser access for desktop users

## Screens (MVP)

1. **Splash / Onboarding** -- 3-screen intro + sign-up
2. **Pairing** -- Generate code / enter partner's code
3. **Home** -- Today's schedule overlay + next free window + timezone clocks
4. **Calendar View** -- Week view with both partners' blocks + highlighted free overlaps
5. **Add Block** -- Form: title, time, recurrence, category
6. **Free Windows** -- List of upcoming mutual free slots, sorted by soonest
7. **Settings** -- Calendar connections, privacy, notifications, account
8. **Partner Profile** -- Timezone, connected calendars, relationship stats

## Non-Functional Requirements

- **Privacy:** Busy/free only by default. Event titles opt-in. No calendar data stored on server beyond busy intervals (freebusy pattern).
- **Performance:** Overlap computation < 500ms for 2 weeks of data.
- **Offline:** Custom blocks work offline, sync when connected.
- **Security:** Firebase Auth + Firestore security rules. OAuth tokens encrypted at rest. HTTPS only.
- **Accessibility:** WCAG 2.1 AA compliance. VoiceOver / TalkBack support.

## Success Metrics

- **North Star:** Weekly active couples (both partners open app in same week)
- **Activation:** % of sign-ups who complete pairing within 24h
- **Engagement:** Free windows viewed per week, events created from suggestions
- **Retention:** Week 4 retention > 40%
- **Revenue:** Premium conversion > 5% of WAC at month 3

## Timeline (Estimated)

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Design & Setup | 2 weeks | Figma designs, Flutter project scaffold, Firebase setup |
| MVP Core | 6 weeks | Auth, pairing, calendar sync, overlap engine, notifications |
| Polish & Testing | 2 weeks | UI polish, beta testing, crash fixes |
| Launch | 1 week | App Store + Play Store submission |
| **Total** | **~11 weeks** | |

## Open Questions

1. App name -- "Couple Schedule" is working title. Explore: SyncUp, OurTime, TimeForTwo, InSync
2. Should v1 include in-app chat or rely on existing messaging apps?
3. Apple Calendar limitation (on-device only) -- acceptable for MVP or need workaround?
4. Freemium gate -- what goes behind paywall in v1?
