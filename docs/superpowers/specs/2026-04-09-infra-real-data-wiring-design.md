# Infrastructure, Real Data Wiring & CI/CD Design

**Date:** 2026-04-09
**Status:** Approved
**Scope:** Terraform IaC, Cloud Functions deployment, mock data removal, GitHub Actions workflows, integration tests

---

## Context

Couple Schedule v1 is a Flutter app for long-distance couples to find mutual free time. The codebase has:
- 10 screens with routing/auth guards fully implemented
- 767 unit tests passing
- 5 Cloud Functions written but never deployed
- Firebase project `nexion-ai-prod` exists on Blaze plan but is a shell (no apps registered, Firestore not created, key APIs disabled)
- 4 screens using hardcoded mock data instead of real Firestore queries
- Basic CI (analyze + test + debug APK) but no deployment workflows

The app needs to launch on Play Store and App Store. This spec covers making it production-ready.

---

## Phase 1: Infrastructure (`infra/`)

### 1.1 Terraform — Project Setup

**Directory:** `infra/terraform/`

**Files:**

| File | Purpose |
|------|---------|
| `main.tf` | Provider config (google-beta), project data source |
| `apis.tf` | Enable 8 missing APIs |
| `firebase_apps.tf` | Register Android + iOS Firebase apps, output config files |
| `firestore.tf` | Create Firestore database (native mode) |
| `budget.tf` | $1/month budget alert |
| `outputs.tf` | App IDs, API keys, config file paths |
| `variables.tf` | Project ID, region, bundle IDs, billing account |
| `environments/prod.tfvars` | Production variable values |

**APIs to enable:**

```hcl
locals {
  required_apis = [
    "firestore.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com",
    "cloudrun.googleapis.com",
    "calendar-json.googleapis.com",
    "people.googleapis.com",
  ]
}
```

**Firebase apps:**

- Android: `com.skyner.coupleSync` — output `google-services.json` via `google_firebase_android_app_config` data source
- iOS: `com.skyner.coupleSync` — output `GoogleService-Info.plist` via `google_firebase_apple_app_config` data source

**Firestore:**

- Mode: `FIRESTORE_NATIVE`
- Location: `nam5` (US multi-region for low-latency, matches Cloud Functions default us-central1)
- This is permanent and cannot be changed after creation

**Budget:**

- $1/month with alerts at 50% and 100% of spend
- Email notification to project owner

### 1.2 Deployment Scripts

**Directory:** `infra/scripts/`

| Script | Purpose | When to run |
|--------|---------|-------------|
| `setup.sh` | Run `terraform apply`, print manual steps checklist | Once, initial setup |
| `configure-flutter.sh` | Run `flutterfire configure`, copy config files to `android/` and `ios/` | After Terraform, or when apps change |
| `deploy-functions.sh` | `cd functions && npm ci && npm run build && firebase deploy --only functions` | On backend changes |
| `deploy-rules.sh` | `firebase deploy --only firestore:rules,firestore:indexes` | On rules/index changes |
| `deploy-all.sh` | Orchestrate: rules + indexes + functions | Full backend deploy |
| `enable-auth.sh` | Print step-by-step guide for manual OAuth + auth provider setup | Once, after Terraform |

All scripts:
- Set `firebase use nexion-ai-prod` at the top
- Use `set -euo pipefail` for safety
- Print what they're doing before each step
- Exit with clear error messages on failure

### 1.3 Manual Steps (Documented in `infra/README.md`)

These cannot be automated via Terraform:

1. **OAuth consent screen** — GCP Console > APIs & Services > OAuth consent screen
   - User type: External
   - Scopes: `calendar.readonly`, `email`, `profile`, `openid`
   - App name: "Couple Schedule"

2. **OAuth client IDs** — GCP Console > APIs & Services > Credentials
   - Android: package `com.skyner.coupleSync` + SHA-1 from debug/release keystore
   - iOS: bundle ID `com.skyner.coupleSync`
   - Web: for Firebase Auth (auto-created when enabling Google Sign-In)

3. **Firebase Auth providers** — Firebase Console > Authentication > Sign-in method
   - Enable Google Sign-In (uses the OAuth client ID)
   - Enable Apple Sign-In (needs Apple Developer account, Services ID, private key)

4. **Android SHA-1 fingerprint** — `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`

---

## Phase 2: Cloud Functions Fixes

### 2.1 Node Runtime Upgrade

**Files:** `functions/package.json`, `firebase.json`

- Change `"node": "18"` to `"node": "20"` in `package.json` engines
- Change `"runtime": "nodejs18"` to `"runtime": "nodejs20"` in `firebase.json`
- Node 18 is EOL since April 2025

### 2.2 Fix `redeemInvite` Dual Logic Path

**File:** `functions/src/redeemInvite.ts`

**Problem:** The exported `handleRedeemInvite` function (tested via DI) performs individual operations, but the actual Cloud Function uses a completely separate `db.runTransaction()` code path that duplicates all validation. Tests give false coverage.

**Fix:** Restructure so the DI-tested function IS the one called inside the transaction. The `handleRedeemInvite` function should accept a transaction object and perform all reads/writes through it. The Cloud Function export wraps it in `db.runTransaction(txn => handleRedeemInvite(code, uid, { ...deps using txn }))`.

### 2.3 Add ESLint Configuration

**File:** `functions/.eslintrc.js`

```js
module.exports = {
  root: true,
  env: { es2020: true, node: true },
  parser: "@typescript-eslint/parser",
  parserOptions: { project: ["tsconfig.json"] },
  plugins: ["@typescript-eslint"],
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
  ],
  rules: {
    "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
  },
};
```

Add `eslint` and `@typescript-eslint/*` to devDependencies if missing.

### 2.4 Function Configuration

Set on all functions:
- **Region:** `us-central1` (explicit, matches Firestore `nam5`)
- **`onBlockWrite` specifically:** `memory: "512MiB"`, `timeoutSeconds: 120` (recurrence expansion can be expensive)

---

## Phase 3: Wire Real Data (Kill All Mocks)

### 3.1 New Riverpod Providers

**Directory:** `lib/services/providers/`

| Provider | Type | Source | Depends On |
|----------|------|--------|------------|
| `coupleProvider` | `FutureProvider<CoupleModel?>` | `couples/{coupleId}` | `currentUserProfileProvider` |
| `partnerProfileProvider` | `FutureProvider<UserModel?>` | `users/{partnerId}` | `coupleProvider`, `currentUserIdProvider` |
| `userBlocksProvider` | `StreamProvider<List<TimeBlock>>` | `timeblocks/{coupleId}/blocks` where `userId == currentUserId` | `currentUserProfileProvider` |
| `partnerBlocksProvider` | `StreamProvider<List<TimeBlock>>` | `timeblocks/{coupleId}/blocks` where `userId == partnerId` | `coupleProvider`, `currentUserIdProvider` |
| `overlapWindowsProvider` | `StreamProvider<OverlapResult?>` | `overlaps/{coupleId}/windows/latest` | `currentUserProfileProvider` |

Use `StreamProvider` (not `FutureProvider`) for blocks and overlaps — these update in real-time when Cloud Functions recompute.

`FirestoreService` already has `getBlocks()` and `getOverlap()` methods, but they return `Future`s. Add corresponding stream methods:
- `watchBlocks(coupleId, {userId})` → `Stream<List<TimeBlock>>`
- `watchOverlap(coupleId)` → `Stream<OverlapResult?>`

### 3.2 Screen Rewrites

**HomeScreen** (`lib/features/home/screens/home_screen.dart`):
- Replace hardcoded `_userTimezone`, `_partnerTimezone`, `_partnerName` with `ref.watch(currentUserProfileProvider)` and `ref.watch(partnerProfileProvider)`
- Replace `_mockOverlapResult` with `ref.watch(overlapWindowsProvider)`
- Show loading/empty states when providers are loading or couple not paired
- Wire "Sync Calendar" quick action to `CalendarService.fetchFreebusy()`

**WeekViewScreen** (`lib/features/calendar/week_view_screen.dart`):
- Remove all mock `TimeBlock` lists and `_currentUserId = 'user_123'`
- Use `ref.watch(userBlocksProvider)` and `ref.watch(partnerBlocksProvider)`
- Use `ref.watch(overlapWindowsProvider)` for overlap display
- Filter blocks to current week in the widget, not the query (Firestore queries by coupleId, client filters by date range)

**OverlapScreen** (`lib/features/overlap/screens/overlap_screen.dart`):
- Remove `_generateMockWindows()` and hardcoded timezones
- Use `ref.watch(overlapWindowsProvider)` for real windows
- Use `ref.watch(currentUserProfileProvider)` and `ref.watch(partnerProfileProvider)` for timezones
- Keep existing filter/sort UI — it operates on the provider data

**BlockManagementScreen** (`lib/features/blocks/screens/block_management_screen.dart`):
- Currently functional for create/edit/delete of individual blocks
- Wire up block listing — use `ref.watch(userBlocksProvider)` to show list of existing blocks
- Add partner blocks display (read-only) for context

**SettingsScreen** (`lib/features/settings/screens/settings_screen.dart`):
- Replace `FutureBuilder` couple/partner fetching with `ref.watch(coupleProvider)` and `ref.watch(partnerProfileProvider)` for consistency
- Wire calendar sync button to `CalendarService.fetchFreebusy()` → `FirestoreService.batchCreateBlocks()`
- Keep unpair as future work (documented in BACKLOG)

**RoutineWizardScreen** (`lib/features/onboarding/screens/routine_wizard_screen.dart`):
- Replace `coupleId ?? 'solo'` fallback with proper validation
- Pre-pairing blocks are saved to `users/{uid}/pendingBlocks/{blockId}` (NOT the couple subcollection, which requires a coupleId)
- During pairing, the `redeemInvite` Cloud Function migrates pending blocks from both users into `timeblocks/{coupleId}/blocks/`
- Add a `migratePendingBlocks(uid, coupleId)` helper to the `redeemInvite` function
- Add Firestore rules for `users/{uid}/pendingBlocks/{blockId}` (owner read/write only)

### 3.3 Empty/Loading/Error States

Every screen that reads from providers must handle:
- **Loading:** Show `CircularProgressIndicator` or shimmer
- **No couple:** Show "Pair with your partner to see data" message + link to pairing screen
- **No data yet:** Show "Add your first block" or "Waiting for overlap computation" message
- **Error:** Show retry button with error message from provider

---

## Phase 4: GitHub Actions Workflows

### 4.1 Enhanced CI (`ci.yml`)

Add to existing workflow:
- **functions-lint-test** job: `cd functions && npm ci && npm run lint && npm run build && npm test`
- Keep existing analyze, test, build jobs
- Add `integration-test` job (Phase 5, runs on emulator)

### 4.2 Deploy Backend (`deploy-backend.yml`)

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'functions/**'
      - 'firestore.rules'
      - 'firestore.indexes.json'
```

Jobs:
1. `deploy-rules`: Deploy Firestore rules + indexes
2. `deploy-functions`: Build + deploy Cloud Functions

Requires GitHub Secrets:
- `FIREBASE_SERVICE_ACCOUNT` — JSON key for `firebase-adminsdk-fbsvc@nexion-ai-prod.iam.gserviceaccount.com`

### 4.3 Build Release (`build-release.yml`)

```yaml
on:
  push:
    tags: ['v*']
```

Jobs:
1. `build-android`: `flutter build appbundle --release` → upload `app-release.aab` as artifact
2. `build-ios`: `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist` → upload `.ipa` as artifact

Requires GitHub Secrets:
- `ANDROID_KEYSTORE_BASE64` — Release keystore
- `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`
- `IOS_CERTIFICATE_BASE64`, `IOS_PROVISIONING_PROFILE_BASE64`
- `FIREBASE_OPTIONS_DART` — Generated `firebase_options.dart` content (avoid committing API keys)

### 4.4 Deploy Stores (`deploy-stores.yml`)

```yaml
on:
  workflow_dispatch:
    inputs:
      track:
        description: 'Play Store track'
        default: 'internal'
        type: choice
        options: [internal, alpha, beta, production]
```

Uses Fastlane for both platforms. Manual trigger only — never auto-deploy to stores.

Requires:
- `PLAY_STORE_SERVICE_ACCOUNT_JSON` — Google Play Console service account
- `APP_STORE_CONNECT_API_KEY` — App Store Connect API key

---

## Phase 5: Integration Tests

### 5.1 Approach

Use `integration_test/` package (Flutter's official integration test framework) with **Firebase Emulator Suite** for local testing against real Firebase services.

**Directory:** `integration_test/`

**Firebase Emulator config** (`firebase.json` additions):
```json
{
  "emulators": {
    "auth": { "port": 9099 },
    "firestore": { "port": 8080 },
    "functions": { "port": 5001 },
    "ui": { "enabled": true, "port": 4000 }
  }
}
```

### 5.2 Test Flows

| Test | Flow | Verifies |
|------|------|----------|
| `auth_flow_test.dart` | Tap Google Sign-In → profile created in Firestore → redirected to timezone setup | Auth + Firestore user creation |
| `onboarding_flow_test.dart` | Set timezone → complete routine wizard → blocks created in Firestore | Timezone save + batch block creation |
| `pairing_flow_test.dart` | Create invite → enter code on second account → couple created, both users linked | Invite lifecycle + redeemInvite function |
| `block_crud_test.dart` | Create block → edit title → delete → verify Firestore state | Block CRUD operations |
| `overlap_display_test.dart` | Create blocks for both users → overlap computed by function → overlap screen shows windows | Full pipeline: block write → function → overlap display |
| `calendar_sync_test.dart` | Mock OAuth tokens → call freebusy conversion → blocks created with source='google' in Firestore | Freebusy-to-blocks pipeline (OAuth cannot run in emulator; test the conversion + Firestore write, not the Google API call) |

### 5.3 Test Infrastructure

- `integration_test/helpers/emulator_setup.dart` — Connect to Firebase emulators, seed test data
- `integration_test/helpers/test_users.dart` — Pre-configured test user accounts
- `integration_test/helpers/firestore_seeder.dart` — Seed Firestore with known state before each test
- Tests run with `flutter test integration_test/ --device-id=<device>` or on CI with an Android emulator

### 5.4 CI Integration

Add to `ci.yml`:
```yaml
integration-test:
  runs-on: [self-hosted, Linux, X64, astra, android]
  needs: [analyze, test]
  services:
    firebase-emulator: # or use setup step
  steps:
    - uses: actions/checkout@v4
    - uses: subosito/flutter-action@v2
    - run: npm --prefix functions ci && npm --prefix functions run build
    - run: firebase emulators:exec --only auth,firestore,functions "flutter test integration_test/"
```

---

## File Change Summary

### New Files

| Path | Purpose |
|------|---------|
| `infra/terraform/main.tf` | Provider config |
| `infra/terraform/apis.tf` | API enablement |
| `infra/terraform/firebase_apps.tf` | App registration + config output |
| `infra/terraform/firestore.tf` | Database creation |
| `infra/terraform/budget.tf` | Cost alert |
| `infra/terraform/outputs.tf` | Outputs |
| `infra/terraform/variables.tf` | Variables |
| `infra/terraform/environments/prod.tfvars` | Prod values |
| `infra/scripts/setup.sh` | Initial setup |
| `infra/scripts/configure-flutter.sh` | FlutterFire configure |
| `infra/scripts/deploy-functions.sh` | Deploy functions |
| `infra/scripts/deploy-rules.sh` | Deploy rules + indexes |
| `infra/scripts/deploy-all.sh` | Deploy everything |
| `infra/scripts/enable-auth.sh` | Auth setup guide |
| `infra/README.md` | Full setup documentation |
| `lib/services/providers/couple_provider.dart` | Couple data provider |
| `lib/services/providers/partner_profile_provider.dart` | Partner profile provider |
| `lib/services/providers/blocks_provider.dart` | User + partner blocks stream providers |
| `lib/services/providers/overlap_provider.dart` | Overlap windows stream provider |
| `functions/.eslintrc.js` | ESLint config |
| `.github/workflows/deploy-backend.yml` | Backend deploy workflow |
| `.github/workflows/build-release.yml` | Release build workflow |
| `.github/workflows/deploy-stores.yml` | Store deploy workflow |
| `integration_test/auth_flow_test.dart` | Auth integration test |
| `integration_test/onboarding_flow_test.dart` | Onboarding integration test |
| `integration_test/pairing_flow_test.dart` | Pairing integration test |
| `integration_test/block_crud_test.dart` | Block CRUD integration test |
| `integration_test/overlap_display_test.dart` | Overlap integration test |
| `integration_test/calendar_sync_test.dart` | Calendar sync integration test |
| `integration_test/helpers/emulator_setup.dart` | Emulator connection helper |
| `integration_test/helpers/test_users.dart` | Test user data |
| `integration_test/helpers/firestore_seeder.dart` | Firestore test seeder |

### Modified Files

| Path | Changes |
|------|---------|
| `functions/package.json` | Node 18 → 20, add ESLint devDependencies |
| `firebase.json` | Node runtime 18 → 20, add emulators config |
| `functions/src/redeemInvite.ts` | Align DI path with transaction path, add `migratePendingBlocks` |
| `functions/src/index.ts` | Add region config to all function exports |
| `functions/src/onBlockWrite.ts` | Add memory/timeout config |
| `lib/services/firestore_service.dart` | Add `watchBlocks()` and `watchOverlap()` stream methods |
| `lib/features/home/screens/home_screen.dart` | Replace mock data with providers |
| `lib/features/calendar/week_view_screen.dart` | Replace mock data with providers |
| `lib/features/overlap/screens/overlap_screen.dart` | Replace mock data with providers |
| `lib/features/blocks/screens/block_management_screen.dart` | Wire block listing |
| `lib/features/settings/screens/settings_screen.dart` | Wire calendar sync, convert to providers |
| `lib/features/onboarding/screens/routine_wizard_screen.dart` | Fix coupleId validation, save to pendingBlocks |
| `firestore.rules` | Add `users/{uid}/pendingBlocks/{blockId}` rules |
| `.github/workflows/ci.yml` | Add functions lint/test job, integration test job |

---

## Out of Scope

- Unpair/disconnect couple functionality (BACKLOG)
- Foreground notification display (LocalNotificationDisplay implementation)
- App Store / Play Store listing assets (screenshots, descriptions)
- Apple Developer account setup
- Production OAuth consent screen verification (requires Google review)
- Deep link Universal Links setup (App Links association files)

---

## Success Criteria

1. `terraform apply` provisions all GCP resources from zero
2. `infra/scripts/deploy-all.sh` deploys functions + rules successfully
3. App launches on physical device, completes auth flow with real Google Sign-In
4. Blocks created in app appear in Firestore within 1 second
5. Overlap windows computed by Cloud Function within 5 seconds of block change
6. All screens display real data (zero mock data in lib/)
7. All 6 integration tests pass against Firebase Emulator Suite
8. CI pipeline runs functions lint/test on every PR
9. Backend auto-deploys on merge to main
10. Release builds produce signed APK + IPA on git tag
