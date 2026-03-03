# Couple Schedule MVP Improvements — Design Document

**Date:** 2026-03-03
**Status:** Approved
**Approach:** Evolve current architecture (Approach A)

## Context

Couple Schedule is a Flutter app for long-distance couples to find mutual free time. The current codebase has a working foundation (Riverpod, Firebase, overlap engine, calendar sync) but needs tech debt cleanup and several new features to become a polished, useful MVP.

### User Profiles

| User | Devices | Calendars | Lifestyle |
|------|---------|-----------|-----------|
| User A (him) | iPhone, Android | Google Calendar (work + personal) | Long work days, active social life |
| User B (her) | Android | Microsoft Calendar (school), Google Calendar (personal) | University student, study-heavy schedule |

Same timezone couple, but the app must support different timezones (friend use case).

### Guiding Principles

- All Google Cloud services (startup credits available)
- Reduce friction — the app should make life easier, not add another thing to manage
- Warm & modern UI — inviting, not clinical
- YAGNI — ship what's needed, iterate later

---

## 1. Architecture & Tech Debt Cleanup

### 1.1 Remove Prototype Layer

Delete the dual-layer architecture:
- Remove `main.dart` prototype router (mock data, no auth)
- Remove duplicate screen files in `features/*/screens/` where a simpler version exists in `features/*/`
- Single router: `core/router/router.dart` with auth guards
- All screens backed by Firestore providers

### 1.2 Unify TimeBlock Model

Replace two conflicting `TimeBlock` models with one in `shared/models/`:

```dart
enum BlockType { busy, free, tentative }
enum BlockSource { google, microsoft, apple, manual }
enum BlockCategory { work, study, commute, exercise, social, sleep, personal, other }
enum BlockVisibility { both, onlyMe }
```

Delete `core/models/time_block.dart`. Update all references.

### 1.3 Fix Firestore Overlap Path

Standardize on `overlaps/{coupleId}/windows/latest` everywhere:
- Cloud Function already writes here
- Fix `shared/providers/overlap_providers.dart` to read from this path (currently reads `overlapWindows/{coupleId}`)

### 1.4 Fix Missing Definitions

- Add `AppColors.success` (#7BC47F) to `app_theme.dart`

### 1.5 Fix Platform Configs

**iOS (`Info.plist`):**
- Add `NSCalendarsUsageDescription` (even if device calendar removed, for future-proofing)
- Add notification usage description

**Android (`AndroidManifest.xml`):**
- Add `INTERNET` permission
- Add FCM service declaration
- Add `RECEIVE_BOOT_COMPLETED` for scheduled notifications

**Firebase (`firebase.json`):**
- Add `functions` configuration
- Add `firestore` rules and indexes configuration

### 1.6 Remove device_calendar Dependency

Since both users will connect via API (Google/Microsoft), remove the `device_calendar` package and `AppleCalendarService`. Simplifies the codebase and removes iOS EventKit permission requirements.

---

## 2. Authentication

### 2.1 Google & Apple Sign-In Only

Remove email/password auth flow. Users sign in with:
- **Google Sign-In** — covers Android + iOS, and pre-authorizes Google Calendar access
- **Apple Sign-In** — required for iOS App Store, covers Apple ecosystem users

### 2.2 Auth Screen Redesign

Simple screen with two buttons:
- "Continue with Google" (Google-branded button)
- "Continue with Apple" (Apple-branded button, iOS only or cross-platform)

On sign-in, upsert `users/{uid}` with timezone auto-detected from device.

---

## 3. Calendar Integration

### 3.1 Google Calendar (enhanced)

**Existing:** OAuth2 + `freebusy.query` for busy periods.

**Add:**
- Support selecting multiple calendars (work + personal)
- Write-back via `events.insert` with `conferenceDataVersion: 1` for Meet link creation
- Store selected calendar IDs in user preferences

### 3.2 Microsoft Calendar (new)

**OAuth2 flow:**
- Microsoft Identity Platform via `flutter_appauth` (PKCE)
- Scopes: `Calendars.Read`, `User.Read`

**Sync:**
- Microsoft Graph API `GET /me/calendarView` for busy periods (14-day window)
- Normalize to UTC TimeBlocks with `source: microsoft`
- Same batch write + deduplication pipeline as Google

**Token management:**
- Store refresh token securely (Flutter Secure Storage)
- Auto-refresh on expiry

### 3.3 Unified Sync Pipeline

```
Calendar Source (Google/Microsoft)
  → Fetch busy periods (14-day lookahead)
  → Normalize to UTC TimeBlocks
  → Deduplicate by (source, startMs, endMs)
  → Batch write to Firestore (400-op chunks)
  → Triggers onBlockWrite Cloud Function
  → Recomputes overlap windows
```

### 3.4 Calendar Connection Screen

Redesigned screen showing:
- Google Calendar: Connect/disconnect, shows synced calendar names
- Microsoft Calendar: Connect/disconnect, shows synced calendar names
- Last sync timestamp per source
- Manual "Sync Now" button

---

## 4. Google Meet Integration

### 4.1 Flow

1. Free window appears in app with "Schedule Call" button
2. User taps → confirmation bottom sheet:
   - Time in both timezones (or single timezone if same)
   - Duration
   - AI-suggested activity (from Gemini)
   - Editable event title (defaults to suggestion)
3. On confirm → Cloud Function:
   - Creates Google Calendar event via Calendar API v3
   - `conferenceData` auto-generates Meet link
   - Event added to initiator's personal Google Calendar
   - Partner added as attendee (added to their calendar if Google-connected)
   - If partner only has Microsoft, Meet link sent via push notification + stored in app
4. Push notification to partner: "Date scheduled! [day] [time] — [activity] [Meet link]"

### 4.2 Implementation

- Cloud Function `createMeetEvent` triggered via Firestore write (user writes a "scheduling request" doc)
- Uses initiator's stored OAuth token to call Calendar API
- Meet link stored in `overlaps/{coupleId}/windows/latest` on the relevant window
- Event created in the user's designated "couple events" calendar (selectable in settings, defaults to primary/personal)

---

## 5. Pattern Detection

### 5.1 Cloud Function: `detectPatterns`

**Trigger:** Scheduled (weekly) + on-demand via Firestore write

**Algorithm:**
1. Fetch overlap windows from the last 4 weeks
2. Group by day-of-week
3. For each day, find time slots that overlap across 3+ weeks (30-min tolerance)
4. Score: 4/4 weeks = "strong", 3/4 = "moderate"
5. Write to `couples/{coupleId}/recurringWindows`:
   ```
   {
     dayOfWeek: "tuesday",
     startTime: "20:00",
     endTime: "21:00",
     consistency: "strong",  // 4/4 weeks
     weeksDetected: 4,
     suggestedActivity: "Movie night",  // from Gemini
     confirmed: false
   }
   ```
6. Push notification: "You're both consistently free on Tuesdays 8-9pm — make it a weekly date?"

### 5.2 In-App Experience

- "Patterns" section on home screen (below hero card)
- Card per pattern: day, time, consistency badge, suggested activity
- "Lock In" button → creates recurring Google Calendar event with Meet link
- Confirmed patterns distinguished visually (solid vs dashed border)
- If a pattern breaks (new commitment conflicts), notification: "Your Tuesday 8pm window may be affected"

---

## 6. AI Smart Suggestions (Gemini)

### 6.1 Scope

Activity suggestions for free windows. Not a conversational assistant.

### 6.2 Implementation

- Cloud Function calls Gemini Flash via Vertex AI (Google Cloud project)
- Triggered alongside overlap computation (part of `onBlockWrite` pipeline)
- Input: window duration, time of day, day of week, whether weekend
- Output: 1-2 activity suggestions per window

### 6.3 Prompt Template

```
Given a free window for a couple:
- Duration: {duration} minutes
- Time: {startTime} to {endTime} (local)
- Day: {dayOfWeek}
- Weekend: {isWeekend}

Suggest 1-2 couple activities. Be specific and fun.
Keep suggestions under 8 words each.
Examples: "Cook pasta together over video", "Watch a movie on Teleparty"
```

### 6.4 Where Suggestions Appear

- Free window cards: subtle chip below time info
- Schedule Call confirmation sheet: pre-filled as event title
- Pattern cards: suggested recurring activity

### 6.5 Cost

Gemini Flash: ~$0.075/million input tokens. At this volume (<100 calls/day per couple), effectively free.

---

## 7. Manual Blocks & Study Time

### 7.1 Enhanced Categories

```dart
enum BlockCategory {
  work,      // Work hours, meetings
  study,     // Classes, study sessions, exams
  commute,   // Travel time
  exercise,  // Gym, runs, sports
  social,    // Plans with friends/family
  sleep,     // Sleep, quiet hours
  personal,  // Errands, appointments
  other,     // Catch-all
}
```

Each category has a default color and icon.

### 7.2 Quick-Add Presets

Bottom sheet with preset chips:
- "Study session" (2hr default)
- "Gym" (1hr default)
- "Commute" (30min default)
- "Work" (8hr default)
- "Custom" (opens full form)

Tapping a preset pre-fills the form. User adjusts time and saves.

### 7.3 Recurrence

- None (one-off)
- Daily
- Weekdays (Mon-Fri)
- Weekly (same day each week)
- Custom (opens day-of-week picker)

Stored as RRULE string in Firestore.

### 7.4 Block Form

Bottom sheet (not full screen):
- Category chip selector (top row)
- Title (optional, auto-filled from category)
- Date picker
- Start time / End time pickers
- Recurrence toggle
- Visibility toggle (both partners / only me)
- Save button

---

## 8. Timezone Handling

### 8.1 Same Timezone

When both partners share a timezone:
- Single clock on home screen (not dual)
- Free window times shown once (not side-by-side)
- Simpler display throughout

### 8.2 Different Timezones

When timezones differ:
- Dual clocks on home screen (rose = you, blue = partner)
- Free window times shown in both timezones
- "It's 9pm for you, 3pm for them" contextual display
- Timezone auto-detected from device, manual override in settings

### 8.3 Detection

Timezone auto-detected on sign-up. Stored as IANA string in `users/{uid}.timezone`. Can be manually overridden in settings.

---

## 9. UI Design System

### 9.1 Color Palette

```dart
// Identity
rose: #E8849A           // User's color
roseLight: #FCEEF1      // User's background tint
partnerBlue: #7AB4E8    // Partner's color
partnerBlueLight: #EBF3FC // Partner's background tint

// Overlap
overlapGradientStart: #B794D6  // Lavender
overlapGradientEnd: #E8849A    // Rose

// Surfaces
background: #FFF8F5     // Warm cream
surface: #FFFFFF         // Cards
surfaceElevated: #FFFFFF // Elevated cards (with shadow)
divider: #F0E8F5         // Subtle lavender divider

// Semantic
success: #7BC47F         // Confirmed, positive
warning: #F5C842         // Attention
error: #E85D5D           // Errors, destructive

// Text
textPrimary: #2D2D3A     // Charcoal
textSecondary: #6B6B80   // Gray
textTertiary: #A0A0B0    // Light gray
```

### 9.2 Typography

System fonts: SF Pro (iOS), Roboto (Android). No custom fonts.

- Display: 28px bold — hero numbers, countdown
- Title: 20px semibold — screen titles
- Body: 16px regular — content
- Caption: 13px regular — secondary info
- Label: 11px medium — chips, badges

### 9.3 Components

- **Cards:** White, 16px radius, subtle shadow (elevation 1-2)
- **Chips:** Rounded pill shape, category-colored
- **Buttons:** Rounded (24px radius), gradient fill for primary actions
- **Bottom sheets:** Rounded top corners (20px), drag handle
- **Animations:** Shared element heroes for window cards, breathing gradient on overlap zones, smooth page transitions

### 9.4 Screen Layout

**Home:**
- Timezone clock(s) at top
- Hero card: next free window with countdown timer
- "Patterns" section: detected recurring windows
- Daily timeline: horizontally scrollable, color-coded blocks
- Quick actions: "Add Block", "Sync Calendars", "View All Windows"

**Calendar:**
- Week view with swipe navigation
- Left half = your blocks, right half = partner's blocks
- Overlap zones highlighted with gradient glow
- Tap block/window for detail sheet

**Free Windows:**
- Cards sorted by soonest
- Each card: time (both TZ if different), duration badge, Gemini suggestion chip
- "Schedule Call" button with Meet icon
- Filter: minimum duration slider

**Settings:**
- Calendar connections (Google, Microsoft status)
- Default calendar for couple events
- Notification preferences (new windows, daily digest, quiet hours)
- Privacy (show titles vs busy-only)
- Timezone override
- Account (sign out, unpair)

---

## 10. Firestore Schema (Final)

```
users/{uid}
  displayName: string
  email: string
  photoUrl: string?
  timezone: string (IANA)
  coupleId: string?
  fcmToken: string?
  tokenUpdatedAt: timestamp?
  googleConnected: bool
  microsoftConnected: bool
  microsoftEmail: string?
  defaultCoupleCalendarId: string?  // Google Calendar ID for couple events
  createdAt: timestamp

invites/{code}
  createdByUid: string
  expiresAt: timestamp
  status: "pending" | "accepted" | "declined" | "expired"

couples/{coupleId}
  userAUid: string
  userBUid: string
  pairedAt: timestamp
  settings: {
    showTitles: bool (default false)
    minSlotDurationMinutes: int (default 30)
  }

couples/{coupleId}/calendarSources/{id}
  type: "google" | "microsoft"
  userId: string
  email: string
  displayName: string
  calendarIds: string[]  // Selected calendar IDs
  lastSync: timestamp

couples/{coupleId}/recurringWindows/{id}
  dayOfWeek: string
  startTime: string (HH:mm)
  endTime: string (HH:mm)
  consistency: "strong" | "moderate"
  weeksDetected: int
  suggestedActivity: string?
  confirmed: bool
  meetLink: string?
  createdAt: timestamp

timeblocks/{coupleId}/blocks/{blockId}
  userId: string
  coupleId: string
  type: "busy" | "free" | "tentative"
  source: "google" | "microsoft" | "manual"
  category: "work" | "study" | "commute" | "exercise" | "social" | "sleep" | "personal" | "other"
  title: string?
  startUtc: timestamp
  endUtc: timestamp
  timezone: string (IANA)
  recurrenceRule: string? (RRULE)
  visibility: "both" | "onlyMe"
  createdAt: timestamp

overlaps/{coupleId}/windows/latest
  windows: [{
    startUtc: timestamp
    endUtc: timestamp
    durationMinutes: int
    score: number
    reasonableBoth: bool
    suggestedActivity: string?
    meetLink: string?
    seen: bool
  }]
  computedAt: timestamp
  coupleId: string

schedulingRequests/{requestId}
  coupleId: string
  requestedByUid: string
  windowStartUtc: timestamp
  windowEndUtc: timestamp
  title: string
  status: "pending" | "created" | "failed"
  meetLink: string?
  calendarEventId: string?
  createdAt: timestamp
```

---

## 11. Cloud Functions (Final)

| Function | Trigger | Purpose |
|----------|---------|---------|
| `onBlockWrite` | Firestore `timeblocks/{coupleId}/blocks/{blockId}` write | Recompute overlap windows, call Gemini for suggestions |
| `onOverlapWrite` | Firestore `overlaps/{coupleId}/windows/latest` write | Send FCM push notifications for new windows |
| `detectPatterns` | Cloud Scheduler (weekly) + manual trigger | Analyze 4 weeks of overlaps, detect recurring patterns |
| `createMeetEvent` | Firestore `schedulingRequests/{id}` create | Create Google Calendar event with Meet link |

---

## 12. Dependencies (Changes)

**Add:**
- `flutter_appauth` — Microsoft OAuth PKCE flow
- `flutter_secure_storage` — Secure token storage for Microsoft
- `sign_in_with_apple` — Apple Sign-In

**Remove:**
- `device_calendar` — No longer needed (API-only calendar sync)

**Keep:**
- `flutter_riverpod`, `go_router`, `firebase_*`, `google_sign_in`, `googleapis`
- `firebase_messaging`, `flutter_local_notifications`
- `shared_preferences`, `uuid`, `timezone`, `intl`, `http`

**Cloud Functions add:**
- `@google-cloud/aiplatform` or `@google/generative-ai` — Gemini API
- `googleapis` (Node) — Google Calendar API for Meet event creation
- `@azure/msal-node` — Microsoft token validation (if needed)
