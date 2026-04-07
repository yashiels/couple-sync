# ARCHITECTURE.md

## System Overview

Couple Schedule v1 is a mobile app for long-distance couples to find mutual free time across timezones. The architecture prioritizes real-time sync, privacy, and zero operational costs.

```
┌──────────────────────┐         ┌──────────────────────┐
│   Partner A App      │         │   Partner B App      │
│   (Flutter)          │         │   (Flutter)          │
│  - iOS + Android     │         │  - iOS + Android     │
│  - Riverpod state    │         │  - Riverpod state    │
│  - go_router         │         │  - go_router         │
└──────────┬───────────┘         └──────────┬───────────┘
           │                                │
           │    Cloud Firestore (real-time) │
           │    - users/{uid}               │
           │    - couples/{coupleId}        │
           │    - invites/{code}            │
           │    - timeblocks/{coupleId}/... │
           │    - overlaps/{coupleId}/...   │
           └────────────┬───────────────────┘
                        │
           ┌────────────┴────────────┐
           │  Cloud Functions v2     │
           │  - onBlockWrite         │──────► Overlap computation
           │  - onOverlapWrite       │──────► Push notifications
           │  - onInviteCreate       │──────► Deep link generation
           │  - redeemInvite         │──────► Atomic pairing
           │  - cleanupExpiredInvites│──────► Scheduled cleanup
           └────────────┬────────────┘
                        │
           ┌────────────┴────────────┐
           │  Google Calendar API    │
           │  - freebusy endpoint    │
           │  - OAuth2 (calendar.readonly)
           └─────────────────────────┘
```

## Data Flow

### 1. Auth Flow
```
User taps "Sign in with Google/Apple"
    ↓
Firebase Auth creates session
    ↓
App fetches/creates user doc in Firestore
    ↓
Router checks auth state → redirects to appropriate screen
```

### 2. Pairing Flow
```
Partner A generates invite code
    ↓
Invite doc created in Firestore (status: pending, expires in 48h)
    ↓
onInviteCreate generates deep link URL
    ↓
Partner A shares code/link with Partner B
    ↓
Partner B enters code → calls redeemInvite Cloud Function
    ↓
Function validates → creates couple doc → updates both user docs atomically
    ↓
Both apps detect coupleId change → navigate to home
```

### 3. Block Sync Flow
```
User adds manual block OR Google Calendar sync runs
    ↓
TimeBlock written to timeblocks/{coupleId}/blocks/{blockId}
    ↓
onBlockWrite triggered (after 2s debounce)
    ↓
Compute overlap: fetch all blocks → expand recurrence → intersect free times
    ↓
Write top 20 windows to overlaps/{coupleId}/windows/latest
    ↓
onOverlapWrite triggered
    ↓
Send FCM push to both partners: "New free time found!"
    ↓
Both apps receive real-time Firestore update → UI refreshes
```

## Core Components

### Flutter App

**Entry Point**: `lib/main.dart`
- Initializes Firebase
- Wraps app in `ProviderScope` (Riverpod)
- Renders `MyApp` with `MaterialApp.router`

**Router**: `lib/core/router/app_router.dart`
- Defines all 10 routes
- Implements redirect guards:
  - `!isAuthenticated` → `/auth`
  - `!hasTimezone` → `/timezone-setup`
  - `!hasCouple` → `/pairing`
  - `hasCouple` → `/home`

**Services**:
- `AuthService`: Firebase Auth (Google + Apple sign-in)
- `FirestoreService`: All Firestore CRUD operations
- `CalendarService`: Google Calendar OAuth + freebusy sync
- `NotificationService`: FCM token registration + foreground notifications

**State Management**:
- Riverpod `StateNotifierProvider` for each domain (auth, user, couple, blocks, overlaps)
- All state is immutable, updated via `copyWith()`
- Firestore listeners trigger state updates

### Cloud Functions

**onBlockWrite** (`functions/src/onBlockWrite.ts`)
- Trigger: Firestore onWrite on `timeblocks/{coupleId}/blocks/{blockId}`
- Debounce: 2-second delay + hash comparison
- Algorithm:
  1. Fetch all blocks for couple (14-day horizon)
  2. Expand recurrence rules (rrule library)
  3. Build busy timeline per partner, invert to free
  4. Intersect free intervals
  5. Clip to waking hours (7am-11pm local)
  6. Score windows: `log2(duration+1)*10 + eveningBonus + weekendBonus + timeDecay`
  7. Write top 20 to `overlaps/{coupleId}/windows/latest`

**onOverlapWrite** (`functions/src/onOverlapWrite.ts`)
- Trigger: Firestore onWrite on `overlaps/{coupleId}/windows/latest`
- Sends FCM notification to both partners
- Prunes stale FCM tokens on send failure

**onInviteCreate** (`functions/src/onInviteCreate.ts`)
- Trigger: Firestore onCreate on `invites/{code}`
- Generates deep link: `coupleschedule://invite/{code}`
- Generates HTTPS fallback: `https://coupleschedule.app/invite/{code}`

**redeemInvite** (`functions/src/redeemInvite.ts`)
- Trigger: HTTPS callable
- Validates invite, creates couple doc, updates both user docs atomically
- Returns coupleId on success

**cleanupExpiredInvites** (`functions/src/cleanupExpiredInvites.ts`)
- Trigger: Cloud Scheduler (daily at 03:00 UTC)
- Batch updates expired invites to `status: expired`

## Data Model

### users/{uid}
```typescript
{
  email: string,
  displayName: string,
  photoUrl?: string,
  timezone: string,        // IANA ID
  coupleId?: string,       // null if unpaired
  fcmTokens: string[],
  createdAt: Timestamp
}
```

### couples/{coupleId}
```typescript
{
  userAUid: string,
  userBUid: string,
  status: "active" | "inactive",
  pairedAt: Timestamp,
  unpairHistory: Array<{at: Timestamp, reason: string}>,
  createdAt: Timestamp
}
```

### invites/{code}
```typescript
{
  code: string,            // 6-char alphanumeric
  createdByUid: string,
  coupleId?: string,       // set on redemption
  expiresAt: Timestamp,    // 48h from creation
  status: "pending" | "accepted" | "expired",
  deepLinkUrl?: string
}
```

### timeblocks/{coupleId}/blocks/{blockId}
```typescript
{
  userId: string,
  title: string,
  type: "busy" | "free" | "tentative",
  category: "work" | "study" | "commute" | "exercise" | "social" | "meals" | "sleep" | "personal" | "other",
  startUtc: number,        // milliseconds since epoch
  endUtc: number,
  timezone: string,        // IANA ID where created
  recurrenceRule?: string, // RFC 5545 RRULE
  source: "google" | "manual",
  visibility: "bothPartners" | "onlyMe",
  createdAt: Timestamp
}
```

### overlaps/{coupleId}/windows/latest
```typescript
{
  windows: [
    {
      startUtc: number,
      endUtc: number,
      durationMinutes: number,
      score: number,
      reasonableBoth: boolean
    }
  ],
  computedAt: Timestamp,
  blockHashA: string,      // change detection
  blockHashB: string
}
```

## Security Model

**Principle**: Users can read their own data and their partner's data. Only Cloud Functions can write to couple-sensitive collections.

**Rules**:
- `users/{uid}`: Owner writes, owner + partner reads
- `couples/{coupleId}`: Functions only (admin SDK)
- `invites/{code}`: Authenticated users read/create, creator updates
- `timeblocks/{coupleId}/blocks/{blockId}`: Couple members read/write (verified via `get()` on couples doc)
- `overlaps/{coupleId}/windows/latest}`: Couple members read, functions write

**Note**: `visibility: onlyMe` blocks are filtered client-side, not server-enforced (accepted trade-off for v1).

## Timezone Handling

- **Storage**: All timestamps as UTC milliseconds
- **User timezone**: Stored in `users/{uid}.timezone`
- **Block timezone**: Stored in `timeblocks/{coupleId}/blocks/{blockId}.timezone` (where block was created)
- **Display**: Convert UTC to viewer's local timezone using `timezone` package
- **Overlap computation**: Uses both partners' timezones for waking-hours clipping (7am-11pm local)
- **Functions**: Luxon for timezone math

## Privacy Model

- **Google Calendar**: freebusy API only — no event titles fetched or stored
- **Manual blocks**: Title visible to partner if `visibility: bothPartners`, otherwise shows as unnamed busy time
- **Server data**: Only busy/free intervals stored, no calendar content

## Offline Behavior

- Firestore offline persistence enabled
- Manual blocks work offline, sync when connected
- Calendar sync requires connectivity
- Overlap results cached locally
- App fully usable for viewing cached data offline

## Deployment

**Flutter**:
- iOS: App Store (manual or Fastlane)
- Android: Play Store (manual or Fastlane)

**Firebase**:
- `firebase deploy` for all services
- Functions: Node.js 18 runtime
- Firestore: Native mode

**CI/CD**: GitHub Actions + Fastlane (future, not in v1)

## Cost Model

| Service | Free Allowance | Expected Usage |
|---------|---------------|----------------|
| Auth | 50k MAU | <10 users |
| Firestore reads | 50k/day | <1k/day |
| Firestore writes | 20k/day | <500/day |
| Functions invocations | 2M/month | <1k/month |
| FCM | Unlimited | Minimal |

**Estimated monthly cost**: $0 (within free tier)
