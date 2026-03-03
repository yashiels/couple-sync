# Phase 2: Auth Fix, Multi-Calendar, and Remaining MVP Items

**Date:** 2026-03-03
**Status:** Approved

## Problem Statement

Three categories of work remain before the app is shippable:

1. **Infinite loading bug** — Home screen shows infinite spinner after Google Calendar connects (or on app restart) because `currentUserProvider` is never re-hydrated from Firestore when Firebase auto-restores the session.

2. **Multi-Google-account support** — Users need to connect multiple Google accounts (e.g. personal on Android, work on iPhone). Currently the app stores a single `googleConnected: bool`.

3. **Remaining MVP gaps** — Partner timezone display, "Sync Calendars" quick action, Microsoft placeholder, unpair logic, Cloud Functions deployment.

## Design

### 1. Fix Auth Hydration (Infinite Loading)

**Approach:** Auto-hydrate on auth state change.

Add an `AppStartupWidget` wrapper that watches `firebaseAuthStateProvider`. When a Firebase user is detected (fresh login OR session restore):
- Fetch `UserModel` from Firestore → set `currentUserProvider`
- Query `couples` collection for this user → set `currentCoupleProvider`
- Try silent Google Calendar sign-in restore if previously connected

This runs once on app startup and on every auth state change. If the user is not found in Firestore (edge case: deleted doc), sign them out.

### 2. Multi-Google-Account Calendar Connections

**Data model change:**

Replace flat boolean fields with an array in the user's Firestore document:

```
users/{uid}:
  calendarConnections: [
    {
      id: "auto-generated-uuid",
      provider: "google",
      email: "user@gmail.com",
      lastSync: Timestamp,
      connectedAt: Timestamp,
    },
    {
      id: "auto-generated-uuid",
      provider: "google",
      email: "user@work.com",
      lastSync: Timestamp,
      connectedAt: Timestamp,
    }
  ]
```

**Service changes:**
- `GoogleCalendarService` gets a method to add a new account connection (triggers OAuth, stores connection metadata)
- On sync, iterate all Google connections and fetch freebusy for each
- Remove the old `googleConnected`/`microsoftConnected` boolean fields from `UserModel`

**UI changes (Settings):**
- "Calendar Connections" section shows a list of connected accounts with email + last sync
- "Add Google Account" button at the bottom to connect another account
- Swipe-to-delete or remove button per connection

### 3. Partner Timezone Display

Fetch partner's `UserModel` from Firestore using the couple document's partner UID. Display dual timezone clocks on the home screen.

### 4. Sync Calendars Quick Action

Wire the "Sync Calendars" chip to actually trigger `CalendarSyncService.sync()` for all connected accounts. Show a loading indicator and success/error snackbar.

### 5. Microsoft Calendar — Remove Placeholder

Remove the `YOUR_MS_CLIENT_ID` placeholder. Since Microsoft support isn't configured yet, hide the Microsoft connection option in Settings UI but keep the service code for future use.

### 6. Unpair Logic

Implement the unpair flow: delete the couple document, clear `currentCoupleProvider`, and navigate back to pairing screen.

### 7. Cloud Functions

Deploy the overlap computation and notification Cloud Functions to the `astra-488209` Firebase project.

## Out of Scope

- Calendar selection within an account (sync all calendars per account)
- Apple Calendar (EventKit) integration
- Push notifications beyond basic FCM setup
