# App Audit Fixes Design

## Problem
The app has broken UX flows, non-functional features, and incomplete integrations that confuse users.

## Fixes

### 1. Settings Navigation
- Add back button in AppBar
- Wrap in WillPopScope to navigate to /home instead of closing app

### 2. Partner Clock on Home Screen
- Re-add partner timezone clock using couple data from Firestore
- Show "Not paired yet" placeholder when no partner

### 3. Calendar Page Cleanup
- Remove "Connect calendars" banners (Google + Microsoft)
- Fix hardcoded `userId == 'me'` in week_view.dart to use Firebase Auth UID
- Fix partner timezone offset to use Firestore partner profile data

### 4. Settings Page Cleanup
- Remove "Coming soon" features (quiet hours, default couple calendar)
- Remove non-persisted toggles (notifications, privacy, scheduling)
- Keep: calendar connections, timezone, sign out, unpair
- Only show "Unpair" when actually paired

### 5. Pairing State Consistency
- Show "Unpair" only when paired
- Show appropriate state when not paired

### 6. Remove Microsoft Calendar UI
- Remove incomplete Microsoft integration from calendar + settings

## Out of Scope
- OAuth 403 fix (requires Google Cloud Console access)
- Google Meet integration
- Actual notification implementation
